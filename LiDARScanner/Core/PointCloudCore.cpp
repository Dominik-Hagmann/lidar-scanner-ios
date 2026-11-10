#include "PointCloudCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <deque>
#include <fstream>
#include <limits>
#include <locale>
#include <sstream>
#include <string>
#include <unordered_map>

namespace {
struct Voxel {
    int32_t x, y, z;
    bool operator==(const Voxel &b) const { return x == b.x && y == b.y && z == b.z; }
};
struct VoxelHash {
    size_t operator()(const Voxel &v) const {
        uint64_t h = uint32_t(v.x) * UINT64_C(73856093);
        h ^= uint32_t(v.y) * UINT64_C(19349663);
        h ^= uint32_t(v.z) * UINT64_C(83492791);
        return size_t(h ^ (h >> 32));
    }
};
PCConfig sanitized(PCConfig c) {
    if (!std::isfinite(c.voxelMeters)) c.voxelMeters = 0.01f;
    if (!std::isfinite(c.minDepth)) c.minDepth = 0.2f;
    if (!std::isfinite(c.maxDepth)) c.maxDepth = 5.f;
    c.voxelMeters = std::max(0.002f, std::min(0.1f, c.voxelMeters));
    c.minDepth = std::max(0.1f, std::min(4.f, c.minDepth));
    c.maxDepth = std::max(c.minDepth + 0.1f, std::min(8.f, c.maxDepth));
    c.pixelStep = std::max(1, std::min(8, c.pixelStep));
    if (c.maxPoints == 0) c.maxPoints = std::numeric_limits<uint32_t>::max();
    c.minConfidence = std::min(uint8_t(2), c.minConfidence);
    return c;
}
uint8_t byte(float x) { return uint8_t(std::lround(std::max(0.f, std::min(255.f, x)))); }

void colorAt(const PCFrame &f, int x, int y, PCPoint &p) {
    const int ix = std::min(f.imageWidth - 1, int(int64_t(x) * f.imageWidth / f.width));
    const int iy = std::min(f.imageHeight - 1, int(int64_t(y) * f.imageHeight / f.height));
    const int ux = std::min(f.chromaWidth - 1, int(int64_t(ix) * f.chromaWidth / f.imageWidth));
    const int uy = std::min(f.chromaHeight - 1, int(int64_t(iy) * f.chromaHeight / f.imageHeight));
    float l = f.luma[size_t(iy) * f.lumaRowBytes + size_t(ix)];
    const uint8_t *uv = f.chroma + size_t(uy) * f.chromaRowBytes + size_t(ux) * 2;
    float cb = float(uv[0]) - 128.f, cr = float(uv[1]) - 128.f;
    if (f.videoRange) { l = (l - 16.f) * (255.f / 219.f); cb *= 255.f / 224.f; cr *= 255.f / 224.f; }
    if (f.matrix709) {
        p.r = byte(l + 1.5748f * cr);
        p.g = byte(l - 0.187324f * cb - 0.468124f * cr);
        p.b = byte(l + 1.8556f * cb);
    } else {
        p.r = byte(l + 1.402f * cr);
        p.g = byte(l - 0.344136f * cb - 0.714136f * cr);
        p.b = byte(l + 1.772f * cb);
    }
}

void putFloatLE(std::ostream &out, float value) {
    static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559, "IEEE 754 required");
    uint32_t bits;
    std::memcpy(&bits, &value, 4);
    char bytes[4];
    for (int i = 0; i < 4; ++i) bytes[i] = char((bits >> (8 * i)) & 255);
    out.write(bytes, 4);
}
void errorText(char *out, size_t size, const char *message) {
    if (out && size) std::snprintf(out, size, "%s", message);
}
}

struct PCCloud {
    using VoxelIndex = std::unordered_map<Voxel, uint32_t, VoxelHash>;
    PCConfig config;
    // Segmented points avoid a full-size allocation/copy when a vector grows.
    // Shards limit transient bucket-array growth while keeping global deduplication.
    std::deque<PCPoint> points;
    std::array<VoxelIndex, 64> voxelShards;
    uint64_t accepted = 0;
    explicit PCCloud(PCConfig c) : config(sanitized(c)) {}
};

PCCloud *pc_create(PCConfig config) {
    try { return new PCCloud(config); } catch (...) { return nullptr; }
}
void pc_destroy(PCCloud *cloud) { delete cloud; }
void pc_reset(PCCloud *c, PCConfig config) {
    if (!c) return;
    c->points.clear();
    for (auto &shard : c->voxelShards) shard.clear();
    // Releasing spare capacity is best effort; no exception may cross the C ABI.
    try {
        std::deque<PCPoint>().swap(c->points);
        for (auto &shard : c->voxelShards) PCCloud::VoxelIndex().swap(shard);
    } catch (...) {}
    c->accepted = 0;
    c->config = sanitized(config);
}
PCStats pc_stats(const PCCloud *c) {
    if (!c) return PCStats{};
    return PCStats{uint32_t(c->points.size()), c->accepted,
        c->points.size() >= c->config.maxPoints ? 1 : 0};
}

int32_t pc_ingest(PCCloud *c, PCFrame f) {
    if (!c || !f.depth || !f.confidence || !f.luma || !f.chroma || !f.cameraToWorld ||
        f.width <= 0 || f.height <= 0 || f.imageWidth <= 0 || f.imageHeight <= 0 ||
        f.chromaWidth <= 0 || f.chromaHeight <= 0 ||
        f.depthRowBytes < size_t(f.width) * 4 || f.confidenceRowBytes < size_t(f.width) ||
        f.lumaRowBytes < size_t(f.imageWidth) || f.chromaRowBytes < size_t(f.chromaWidth) * 2 ||
        !std::isfinite(f.fx) || !std::isfinite(f.fy) || f.fx <= 0 || f.fy <= 0 ||
        !std::isfinite(f.cx) || !std::isfinite(f.cy)) return -1;
    for (int i = 0; i < 16; ++i) if (!std::isfinite(f.cameraToWorld[i])) return -1;
    int accepted = 0;
    try {
        for (int y = 0; y < f.height; y += c->config.pixelStep) {
            const uint8_t *row = static_cast<const uint8_t *>(f.depth) + size_t(y) * f.depthRowBytes;
            for (int x = 0; x < f.width; x += c->config.pixelStep) {
                float d;
                std::memcpy(&d, row + size_t(x) * 4, 4);
                const uint8_t confidence = f.confidence[size_t(y) * f.confidenceRowBytes + size_t(x)];
                if (!std::isfinite(d) || d < c->config.minDepth || d > c->config.maxDepth ||
                    confidence > 2 || confidence < c->config.minConfidence) continue;
                /* Image: X right, Y down, Z forward. ARKit camera: X right,
                   Y up, looks along -Z. Depth is axial, NOT Euclidean range. */
                const float a = (float(x) - f.cx) * d / f.fx;
                const float b = -(float(y) - f.cy) * d / f.fy;
                const float z = -d;
                const float *m = f.cameraToWorld;
                PCPoint p{m[0]*a + m[4]*b + m[8]*z + m[12],
                          m[1]*a + m[5]*b + m[9]*z + m[13],
                          m[2]*a + m[6]*b + m[10]*z + m[14], 0, 0, 0, confidence};
                /* Bound integer voxel conversion even for malformed transforms. */
                if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z) ||
                    std::fabs(p.x) > 100000.f || std::fabs(p.y) > 100000.f ||
                    std::fabs(p.z) > 100000.f) continue;
                const float v = c->config.voxelMeters;
                const Voxel key{int32_t(std::floor(p.x/v)), int32_t(std::floor(p.y/v)), int32_t(std::floor(p.z/v))};
                auto &voxels = c->voxelShards[VoxelHash{}(key) % c->voxelShards.size()];
                auto found = voxels.find(key);
                if (found == voxels.end()) {
                    if (c->points.size() >= c->config.maxPoints) continue;
                    colorAt(f, x, y, p);
                    const auto index = uint32_t(c->points.size());
                    c->points.push_back(p);
                    try { voxels.emplace(key, index); }
                    catch (...) { c->points.pop_back(); throw; }
                } else if (confidence > c->points[found->second].confidence) {
                    colorAt(f, x, y, p);
                    c->points[found->second] = p;
                }
                ++accepted; ++c->accepted;
            }
        }
    } catch (...) { return -2; }
    return accepted;
}

size_t pc_copy_preview(const PCCloud *c, PCPoint *out, size_t capacity) {
    if (!c || !out || !capacity || c->points.empty()) return 0;
    const size_t n = std::min(capacity, c->points.size());
    for (size_t i = 0; i < n; ++i) out[i] = c->points[i * c->points.size() / n];
    return n;
}

static void putU16LE(std::ostream &os, uint16_t v) {
    char b[2]{char(v & 0xFF), char((v >> 8) & 0xFF)};
    os.write(b, 2);
}

static void putU32LE(std::ostream &os, uint32_t v) {
    char b[4]{char(v & 0xFF), char((v >> 8) & 0xFF), char((v >> 16) & 0xFF), char((v >> 24) & 0xFF)};
    os.write(b, 4);
}

static void putI32LE(std::ostream &os, int32_t v) {
    putU32LE(os, static_cast<uint32_t>(v));
}

static void putDoubleLE(std::ostream &os, double v) {
    static_assert(sizeof(double) == 8, "double must be 8 bytes");
    uint64_t u = 0;
    std::memcpy(&u, &v, sizeof(u));
    char b[8];
    for (int i = 0; i < 8; ++i) {
        b[i] = char((u >> (i * 8)) & 0xFF);
    }
    os.write(b, 8);
}

static void exportLAS(const PCCloud *c, std::ostream &out) {
    double min_x = std::numeric_limits<double>::infinity();
    double max_x = -std::numeric_limits<double>::infinity();
    double min_y = std::numeric_limits<double>::infinity();
    double max_y = -std::numeric_limits<double>::infinity();
    double min_z = std::numeric_limits<double>::infinity();
    double max_z = -std::numeric_limits<double>::infinity();

    for (const auto &p : c->points) {
        double x = p.x;
        double y = -p.z;
        double z = p.y;
        if (x < min_x) min_x = x;
        if (x > max_x) max_x = x;
        if (y < min_y) min_y = y;
        if (y > max_y) max_y = y;
        if (z < min_z) min_z = z;
        if (z > max_z) max_z = z;
    }

    const double scale = 0.001; // 1 mm precision
    const double offset_x = std::floor(min_x);
    const double offset_y = std::floor(min_y);
    const double offset_z = std::floor(min_z);
    const uint32_t count = static_cast<uint32_t>(c->points.size());

    // 227-byte ASPRS LAS 1.2 Header
    out.write("LASF", 4);
    putU16LE(out, 0); // File Source ID
    putU16LE(out, 0); // Global Encoding
    putU32LE(out, 0); // Project ID GUID 1
    putU16LE(out, 0); // Project ID GUID 2
    putU16LE(out, 0); // Project ID GUID 3
    char guid4[8]{};
    out.write(guid4, 8); // Project ID GUID 4
    out.put(1); // Version Major
    out.put(2); // Version Minor
    char sys_id[32]{};
    std::strncpy(sys_id, "iOS LiDAR Scanner", 31);
    out.write(sys_id, 32);
    char gen_soft[32]{};
    std::strncpy(gen_soft, "LiDAR-Scanner 1.2", 31);
    out.write(gen_soft, 32);
    putU16LE(out, 1); // Creation Day
    putU16LE(out, 2026); // Creation Year
    putU16LE(out, 227); // Header Size
    putU32LE(out, 227); // Offset to points
    putU32LE(out, 0); // Number of VLRs
    out.put(2); // Point Data Format ID: 2 (XYZ + RGB)
    putU16LE(out, 26); // Point Data Record Length: 26 bytes
    putU32LE(out, count); // Number of point records
    putU32LE(out, count); // Points by return 1
    putU32LE(out, 0);     // Return 2
    putU32LE(out, 0);     // Return 3
    putU32LE(out, 0);     // Return 4
    putU32LE(out, 0);     // Return 5
    putDoubleLE(out, scale);    // X scale
    putDoubleLE(out, scale);    // Y scale
    putDoubleLE(out, scale);    // Z scale
    putDoubleLE(out, offset_x); // X offset
    putDoubleLE(out, offset_y); // Y offset
    putDoubleLE(out, offset_z); // Z offset
    putDoubleLE(out, max_x);
    putDoubleLE(out, min_x);
    putDoubleLE(out, max_y);
    putDoubleLE(out, min_y);
    putDoubleLE(out, max_z);
    putDoubleLE(out, min_z);

    // Write Point Records (Format 2: 26 bytes each)
    for (const auto &p : c->points) {
        double x = p.x;
        double y = -p.z;
        double z = p.y;
        int32_t ix = static_cast<int32_t>(std::lround((x - offset_x) / scale));
        int32_t iy = static_cast<int32_t>(std::lround((y - offset_y) / scale));
        int32_t iz = static_cast<int32_t>(std::lround((z - offset_z) / scale));
        putI32LE(out, ix);
        putI32LE(out, iy);
        putI32LE(out, iz);
        putU16LE(out, static_cast<uint16_t>(p.confidence * 32767)); // Intensity
        out.put(0x09); // Return 1 of 1
        out.put(0);    // Classification (Created, unclassified)
        out.put(0);    // Scan Angle Rank
        out.put(p.confidence); // User Data
        putU16LE(out, 1);      // Point Source ID
        putU16LE(out, static_cast<uint16_t>(p.r) * 257); // Red (16-bit)
        putU16LE(out, static_cast<uint16_t>(p.g) * 257); // Green (16-bit)
        putU16LE(out, static_cast<uint16_t>(p.b) * 257); // Blue (16-bit)
        if (!out) break;
    }
}

int32_t pc_export(const PCCloud *c, const char *path, int32_t format, char *error, size_t capacity) {
    if (!c || c->points.empty() || !path || !*path || format < 0 || format > 3) {
        errorText(error, capacity, "Keine Punkte oder ungültiges Exportziel."); return 0;
    }
    std::string temporary;
    try {
        temporary = std::string(path) + ".partial";
        std::ofstream out(temporary, std::ios::binary | std::ios::trunc);
        if (!out) { errorText(error, capacity, "Exportdatei konnte nicht angelegt werden."); return 0; }
        out.imbue(std::locale::classic());
        out.precision(9); /* round-trippable float32, independent of device locale */
        if (format == 3) {
            exportLAS(c, out);
        } else {
            if (format != 2) {
                out << "ply\nformat " << (format == 0 ? "binary_little_endian" : "ascii") << " 1.0\n"
                    << "comment LiDAR-Scanner Build 4; units metres; local right-handed Z-up\n"
                    << "comment export XYZ = ARKit (X, -Z, Y); no geographic CRS\n"
                    << "element vertex " << c->points.size() << "\n"
                    << "property float x\nproperty float y\nproperty float z\n"
                    << "property uchar red\nproperty uchar green\nproperty uchar blue\n"
                    << "property uchar confidence\nend_header\n";
            }
            for (const auto &p : c->points) {
                if (format == 0) {
                    putFloatLE(out, p.x); putFloatLE(out, -p.z); putFloatLE(out, p.y);
                    const char rgba[]{char(p.r), char(p.g), char(p.b), char(p.confidence)};
                    out.write(rgba, 4);
                } else {
                    out << p.x << ' ' << -p.z << ' ' << p.y;
                    if (format == 1) out << ' ' << int(p.r) << ' ' << int(p.g) << ' ' << int(p.b) << ' ' << int(p.confidence);
                    out << '\n';
                }
                if (!out) break;
            }
        }
        out.flush();
        bool good = bool(out);
        out.close();
        good = good && !out.fail();
        if (!good || std::rename(temporary.c_str(), path) != 0) {
            std::remove(temporary.c_str());
            errorText(error, capacity, "Export fehlgeschlagen. Bitte freien Speicher und Ziel prüfen."); return 0;
        }
        errorText(error, capacity, ""); return 1;
    } catch (...) {
        if (!temporary.empty()) std::remove(temporary.c_str());
        errorText(error, capacity, "Export konnte nicht abgeschlossen werden."); return 0;
    }
}

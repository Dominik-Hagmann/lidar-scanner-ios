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

void computeNormal(const PCFrame &f, int x, int y, float d, int step, float &nx, float &ny, float &nz) {
    const float *m = f.cameraToWorld;
    float def_nx = m[8], def_ny = m[9], def_nz = m[10];
    float def_len = std::sqrt(def_nx*def_nx + def_ny*def_ny + def_nz*def_nz);
    if (def_len > 1e-4f) { def_nx /= def_len; def_ny /= def_len; def_nz /= def_len; }
    else { def_nx = 0.f; def_ny = 0.f; def_nz = 1.f; }

    auto getDepth = [&](int px, int py, float &outD) -> bool {
        if (px < 0 || px >= f.width || py < 0 || py >= f.height) return false;
        const uint8_t *row = static_cast<const uint8_t *>(f.depth) + size_t(py) * f.depthRowBytes;
        float val;
        std::memcpy(&val, row + size_t(px) * 4, 4);
        if (!std::isfinite(val) || val <= 0.1f) return false;
        if (std::fabs(val - d) > 0.15f * d) return false;
        outD = val;
        return true;
    };

    float dl = 0.f, dr = 0.f, du = 0.f, dd = 0.f;
    bool hasL = getDepth(x - step, y, dl);
    bool hasR = getDepth(x + step, y, dr);
    bool hasU = getDepth(x, y - step, du);
    bool hasD = getDepth(x, y + step, dd);

    float p_c[3] = { (float(x) - f.cx) * d / f.fx, -(float(y) - f.cy) * d / f.fy, -d };

    float dx_c[3] = { 0.f, 0.f, 0.f };
    if (hasL && hasR) {
        float pl[3] = { (float(x - step) - f.cx) * dl / f.fx, -(float(y) - f.cy) * dl / f.fy, -dl };
        float pr[3] = { (float(x + step) - f.cx) * dr / f.fx, -(float(y) - f.cy) * dr / f.fy, -dr };
        dx_c[0] = pr[0] - pl[0]; dx_c[1] = pr[1] - pl[1]; dx_c[2] = pr[2] - pl[2];
    } else if (hasR) {
        float pr[3] = { (float(x + step) - f.cx) * dr / f.fx, -(float(y) - f.cy) * dr / f.fy, -dr };
        dx_c[0] = pr[0] - p_c[0]; dx_c[1] = pr[1] - p_c[1]; dx_c[2] = pr[2] - p_c[2];
    } else if (hasL) {
        float pl[3] = { (float(x - step) - f.cx) * dl / f.fx, -(float(y) - f.cy) * dl / f.fy, -dl };
        dx_c[0] = p_c[0] - pl[0]; dx_c[1] = p_c[1] - pl[1]; dx_c[2] = p_c[2] - pl[2];
    } else {
        nx = def_nx; ny = def_ny; nz = def_nz; return;
    }

    float dy_c[3] = { 0.f, 0.f, 0.f };
    if (hasU && hasD) {
        float pu[3] = { (float(x) - f.cx) * du / f.fx, -(float(y - step) - f.cy) * du / f.fy, -du };
        float pd[3] = { (float(x) - f.cx) * dd / f.fx, -(float(y + step) - f.cy) * dd / f.fy, -dd };
        dy_c[0] = pd[0] - pu[0]; dy_c[1] = pd[1] - pu[1]; dy_c[2] = pd[2] - pu[2];
    } else if (hasD) {
        float pd[3] = { (float(x) - f.cx) * dd / f.fx, -(float(y + step) - f.cy) * dd / f.fy, -dd };
        dy_c[0] = pd[0] - p_c[0]; dy_c[1] = pd[1] - p_c[1]; dy_c[2] = pd[2] - p_c[2];
    } else if (hasU) {
        float pu[3] = { (float(x) - f.cx) * du / f.fx, -(float(y - step) - f.cy) * du / f.fy, -du };
        dy_c[0] = p_c[0] - pu[0]; dy_c[1] = p_c[1] - pu[1]; dy_c[2] = p_c[2] - pu[2];
    } else {
        nx = def_nx; ny = def_ny; nz = def_nz; return;
    }

    float n_cam[3] = {
        dy_c[1] * dx_c[2] - dy_c[2] * dx_c[1],
        dy_c[2] * dx_c[0] - dy_c[0] * dx_c[2],
        dy_c[0] * dx_c[1] - dy_c[1] * dx_c[0]
    };
    float len = std::sqrt(n_cam[0]*n_cam[0] + n_cam[1]*n_cam[1] + n_cam[2]*n_cam[2]);
    if (len < 1e-6f) { nx = def_nx; ny = def_ny; nz = def_nz; return; }
    n_cam[0] /= len; n_cam[1] /= len; n_cam[2] /= len;
    if (n_cam[2] < 0.f) { n_cam[0] = -n_cam[0]; n_cam[1] = -n_cam[1]; n_cam[2] = -n_cam[2]; }

    float wx = m[0]*n_cam[0] + m[4]*n_cam[1] + m[8]*n_cam[2];
    float wy = m[1]*n_cam[0] + m[5]*n_cam[1] + m[9]*n_cam[2];
    float wz = m[2]*n_cam[0] + m[6]*n_cam[1] + m[10]*n_cam[2];
    float wlen = std::sqrt(wx*wx + wy*wy + wz*wz);
    if (wlen > 1e-6f) { nx = wx/wlen; ny = wy/wlen; nz = wz/wlen; }
    else { nx = def_nx; ny = def_ny; nz = def_nz; }
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
                float nx = 0.f, ny = 0.f, nz = 0.f;
                computeNormal(f, x, y, d, c->config.pixelStep, nx, ny, nz);
                PCPoint p{m[0]*a + m[4]*b + m[8]*z + m[12],
                          m[1]*a + m[5]*b + m[9]*z + m[13],
                          m[2]*a + m[6]*b + m[10]*z + m[14],
                          nx, ny, nz, 0, 0, 0, confidence};
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

int32_t pc_export(const PCCloud *c, const char *path, int32_t format, char *error, size_t capacity) {
    if (!c || c->points.empty() || !path || !*path || format < 0 || format > 2) {
        errorText(error, capacity, "Keine Punkte oder ungültiges Exportziel."); return 0;
    }
    std::string temporary;
    try {
        temporary = std::string(path) + ".partial";
        std::ofstream out(temporary, std::ios::binary | std::ios::trunc);
        if (!out) { errorText(error, capacity, "Exportdatei konnte nicht angelegt werden."); return 0; }
        out.imbue(std::locale::classic());
        out.precision(9); /* round-trippable float32, independent of device locale */
        if (format != 2) {
            out << "ply\nformat " << (format == 0 ? "binary_little_endian" : "ascii") << " 1.0\n"
                << "comment LiDAR-Scanner Build 4; units metres; local right-handed Z-up\n"
                << "comment export XYZ = ARKit (X, -Z, Y); normal = (NX, -NZ, NY); no geographic CRS\n"
                << "element vertex " << c->points.size() << "\n"
                << "property float x\nproperty float y\nproperty float z\n"
                << "property float nx\nproperty float ny\nproperty float nz\n"
                << "property uchar red\nproperty uchar green\nproperty uchar blue\n"
                << "property uchar confidence\nend_header\n";
        }
        for (const auto &p : c->points) {
            if (format == 0) {
                putFloatLE(out, p.x); putFloatLE(out, -p.z); putFloatLE(out, p.y);
                putFloatLE(out, p.nx); putFloatLE(out, -p.nz); putFloatLE(out, p.ny);
                const char rgba[]{char(p.r), char(p.g), char(p.b), char(p.confidence)};
                out.write(rgba, 4);
            } else {
                out << p.x << ' ' << -p.z << ' ' << p.y;
                if (format == 1) out << ' ' << p.nx << ' ' << -p.nz << ' ' << p.ny << ' ' << int(p.r) << ' ' << int(p.g) << ' ' << int(p.b) << ' ' << int(p.confidence);
                out << '\n';
            }
            if (!out) break;
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

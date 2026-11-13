#pragma once

#include "PointCloudCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <fstream>
#include <iomanip>
#include <limits>
#include <locale>
#include <sstream>
#include <string>
#include <vector>

namespace pc_e57 {

inline uint32_t crc32c(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (int b = 0; b < 8; ++b) {
            crc = (crc & 1u) ? ((crc >> 1) ^ 0x82F63B78u) : (crc >> 1);
        }
    }
    return crc ^ 0xFFFFFFFFu;
}

inline void writeU16LE(std::vector<uint8_t> &buf, size_t pos, uint16_t v) {
    buf[pos] = uint8_t(v & 0xFFu);
    buf[pos + 1] = uint8_t((v >> 8) & 0xFFu);
}

inline void writeU32LE(std::vector<uint8_t> &buf, size_t pos, uint32_t v) {
    buf[pos] = uint8_t(v & 0xFFu);
    buf[pos + 1] = uint8_t((v >> 8) & 0xFFu);
    buf[pos + 2] = uint8_t((v >> 16) & 0xFFu);
    buf[pos + 3] = uint8_t((v >> 24) & 0xFFu);
}

inline void writeU64LE(std::vector<uint8_t> &buf, size_t pos, uint64_t v) {
    for (int i = 0; i < 8; ++i) {
        buf[pos + i] = uint8_t((v >> (8 * i)) & 0xFFu);
    }
}

inline void writeU32BE(std::array<uint8_t, 4> &buf, uint32_t v) {
    buf[0] = uint8_t((v >> 24) & 0xFFu);
    buf[1] = uint8_t((v >> 16) & 0xFFu);
    buf[2] = uint8_t((v >> 8) & 0xFFu);
    buf[3] = uint8_t(v & 0xFFu);
}

class PagedWriter {
public:
    static constexpr size_t kPagePayload = 1020;
    static constexpr size_t kPageTotal = 1024;

    explicit PagedWriter(std::ostream &os) : os_(os) {
        page0_.fill(0);
        cur_.fill(0);
    }

    void writeLogical(const uint8_t *data, size_t len) {
        size_t offset = 0;
        while (offset < len) {
            size_t avail = kPagePayload - curUsed_;
            size_t take = std::min(avail, len - offset);
            std::memcpy(cur_.data() + curUsed_, data + offset, take);
            curUsed_ += take;
            offset += take;
            totalLogical_ += take;
            if (curUsed_ == kPagePayload) {
                flushPage();
            }
        }
    }

    void writeLogical(const std::string &s) {
        writeLogical(reinterpret_cast<const uint8_t *>(s.data()), s.size());
    }

    uint64_t logicalPos() const { return totalLogical_; }
    uint64_t currentPhysicalPos() const {
        return totalLogical_ + 4u * (totalLogical_ / kPagePayload);
    }

    uint64_t finish() {
        if (curUsed_ > 0 || pageIndex_ == 0) {
            std::fill(cur_.begin() + curUsed_, cur_.end(), 0);
            flushPage();
        }
        return totalPhysical_;
    }

    std::array<uint8_t, kPagePayload> &page0Mutable() {
        if (pageIndex_ == 0) {
            // Shouldn't happen after finish(), but keep consistent.
            page0_ = cur_;
        }
        return page0_;
    }

private:
    void flushPage() {
        if (pageIndex_ == 0) {
            page0_ = cur_;
        }
        std::array<uint8_t, 4> crcBytes{};
        writeU32BE(crcBytes, crc32c(cur_.data(), kPagePayload));
        os_.write(reinterpret_cast<const char *>(cur_.data()), kPagePayload);
        os_.write(reinterpret_cast<const char *>(crcBytes.data()), 4);
        totalPhysical_ += kPageTotal;
        ++pageIndex_;
        curUsed_ = 0;
        cur_.fill(0);
    }

    std::ostream &os_;
    std::array<uint8_t, kPagePayload> cur_{};
    std::array<uint8_t, kPagePayload> page0_{};
    size_t curUsed_ = 0;
    uint64_t pageIndex_ = 0;
    uint64_t totalLogical_ = 0;
    uint64_t totalPhysical_ = 0;
};

inline bool exportE57(const std::deque<PCPoint> &points, std::fstream &file) {
    if (points.empty()) return false;

    float minX = std::numeric_limits<float>::infinity();
    float maxX = -std::numeric_limits<float>::infinity();
    float minY = std::numeric_limits<float>::infinity();
    float maxY = -std::numeric_limits<float>::infinity();
    float minZ = std::numeric_limits<float>::infinity();
    float maxZ = -std::numeric_limits<float>::infinity();

    for (const auto &p : points) {
        const float x = p.x;
        const float y = -p.z;
        const float z = p.y;
        minX = std::min(minX, x); maxX = std::max(maxX, x);
        minY = std::min(minY, y); maxY = std::max(maxY, y);
        minZ = std::min(minZ, z); maxZ = std::max(maxZ, z);
    }

    PagedWriter writer(file);

    // Reserve 48-byte E57FileHeader + 32-byte CompressedVectorSectionHeader at start of logical stream.
    std::vector<uint8_t> preamble(80, 0);
    std::memcpy(preamble.data(), "ASTM-E57", 8);
    writeU32LE(preamble, 8, 1);  // versionMajor
    writeU32LE(preamble, 12, 0); // versionMinor
    writeU64LE(preamble, 40, 1024); // pageSize
    // CV section header at logical offset 48 (physical offset 48)
    writeU64LE(preamble, 48, 1);  // sectionId = 1 (CompressedVector)
    writeU64LE(preamble, 64, 80); // dataPhysicalOffset = 48 + 32
    writeU64LE(preamble, 72, 0);  // indexPhysicalOffset = 0
    writer.writeLogical(preamble.data(), preamble.size());

    // Stream DataPackets (type=1, 6 bytestreams: x, y, z float32, r, g, b uint8).
    constexpr size_t kMaxPointsPerPacket = 4000;
    std::vector<uint8_t> packet;
    packet.reserve(18 + kMaxPointsPerPacket * 15 + 4);

    for (size_t base = 0; base < points.size(); base += kMaxPointsPerPacket) {
        const size_t n = std::min(kMaxPointsPerPacket, points.size() - base);
        const uint16_t b0Size = uint16_t(n * 4);
        const uint16_t b3Size = uint16_t(n);
        const size_t rawLen = 6 + 6 * 2 + 3 * size_t(b0Size) + 3 * size_t(b3Size);
        const size_t paddedLen = (rawLen + 3u) & ~size_t(3u);
        packet.assign(paddedLen, 0);

        packet[0] = 1; // E57_DATA_PACKET
        packet[1] = 0; // flags
        writeU16LE(packet, 2, uint16_t(paddedLen - 1));
        writeU16LE(packet, 4, 6); // bytestreamCount
        writeU16LE(packet, 6, b0Size);
        writeU16LE(packet, 8, b0Size);
        writeU16LE(packet, 10, b0Size);
        writeU16LE(packet, 12, b3Size);
        writeU16LE(packet, 14, b3Size);
        writeU16LE(packet, 16, b3Size);

        size_t offX = 18;
        size_t offY = offX + b0Size;
        size_t offZ = offY + b0Size;
        size_t offR = offZ + b0Size;
        size_t offG = offR + b3Size;
        size_t offB = offG + b3Size;

        for (size_t i = 0; i < n; ++i) {
            const PCPoint &p = points[base + i];
            const float x = p.x;
            const float y = -p.z;
            const float z = p.y;
            uint32_t ux = 0, uy = 0, uz = 0;
            std::memcpy(&ux, &x, 4);
            std::memcpy(&uy, &y, 4);
            std::memcpy(&uz, &z, 4);
            writeU32LE(packet, offX + i * 4, ux);
            writeU32LE(packet, offY + i * 4, uy);
            writeU32LE(packet, offZ + i * 4, uz);
            packet[offR + i] = p.r;
            packet[offG + i] = p.g;
            packet[offB + i] = p.b;
        }
        writer.writeLogical(packet.data(), packet.size());
    }

    const uint64_t cvSectionLogicalLength = writer.logicalPos() - 48u;
    const uint64_t xmlPhysicalOffset = writer.currentPhysicalPos();

    std::ostringstream xml;
    xml.imbue(std::locale::classic());
    xml << std::setprecision(9);
    xml << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        << "<e57Root type=\"Structure\" xmlns=\"http://www.astm.org/COMMIT/E57/2010-e57-v1.0\">\n"
        << "  <formatName type=\"String\"><![CDATA[ASTM E57 3D Imaging Data File]]></formatName>\n"
        << "  <guid type=\"String\"><![CDATA[{549B7A26-4E5B-4B94-9E75-2E92A4C0E571}]]></guid>\n"
        << "  <versionMajor type=\"Integer\">1</versionMajor>\n"
        << "  <versionMinor type=\"Integer\">0</versionMinor>\n"
        << "  <e57LibraryVersion type=\"String\"><![CDATA[LiDAR-Scanner 1.2]]></e57LibraryVersion>\n"
        << "  <data3D type=\"Vector\" allowHeterogeneousChildren=\"1\">\n"
        << "    <vectorChild type=\"Structure\">\n"
        << "      <guid type=\"String\"><![CDATA[{7C389C8B-80E4-4A6A-B59D-89D4A5E6C901}]]></guid>\n"
        << "      <name type=\"String\"><![CDATA[Scan 0]]></name>\n"
        << "      <description type=\"String\"><![CDATA[LiDAR-Scanner local Z-up point cloud (metres)]]></description>\n"
        << "      <colorLimits type=\"Structure\">\n"
        << "        <colorRedMinimum type=\"Integer\">0</colorRedMinimum>\n"
        << "        <colorRedMaximum type=\"Integer\">255</colorRedMaximum>\n"
        << "        <colorGreenMinimum type=\"Integer\">0</colorGreenMinimum>\n"
        << "        <colorGreenMaximum type=\"Integer\">255</colorGreenMaximum>\n"
        << "        <colorBlueMinimum type=\"Integer\">0</colorBlueMinimum>\n"
        << "        <colorBlueMaximum type=\"Integer\">255</colorBlueMaximum>\n"
        << "      </colorLimits>\n"
        << "      <cartesianBounds type=\"Structure\">\n"
        << "        <xMinimum type=\"Float\">" << minX << "</xMinimum>\n"
        << "        <xMaximum type=\"Float\">" << maxX << "</xMaximum>\n"
        << "        <yMinimum type=\"Float\">" << minY << "</yMinimum>\n"
        << "        <yMaximum type=\"Float\">" << maxY << "</yMaximum>\n"
        << "        <zMinimum type=\"Float\">" << minZ << "</zMinimum>\n"
        << "        <zMaximum type=\"Float\">" << maxZ << "</zMaximum>\n"
        << "      </cartesianBounds>\n"
        << "      <pose type=\"Structure\">\n"
        << "        <rotation type=\"Structure\">\n"
        << "          <w type=\"Float\">1</w><x type=\"Float\">0</x><y type=\"Float\">0</y><z type=\"Float\">0</z>\n"
        << "        </rotation>\n"
        << "        <translation type=\"Structure\">\n"
        << "          <x type=\"Float\">0</x><y type=\"Float\">0</y><z type=\"Float\">0</z>\n"
        << "        </translation>\n"
        << "      </pose>\n"
        << "      <points type=\"CompressedVector\" fileOffset=\"48\" recordCount=\"" << points.size() << "\">\n"
        << "        <prototype type=\"Structure\">\n"
        << "          <cartesianX type=\"Float\" precision=\"single\" minimum=\"" << minX << "\" maximum=\"" << maxX << "\"/>\n"
        << "          <cartesianY type=\"Float\" precision=\"single\" minimum=\"" << minY << "\" maximum=\"" << maxY << "\"/>\n"
        << "          <cartesianZ type=\"Float\" precision=\"single\" minimum=\"" << minZ << "\" maximum=\"" << maxZ << "\"/>\n"
        << "          <colorRed type=\"Integer\" minimum=\"0\" maximum=\"255\"/>\n"
        << "          <colorGreen type=\"Integer\" minimum=\"0\" maximum=\"255\"/>\n"
        << "          <colorBlue type=\"Integer\" minimum=\"0\" maximum=\"255\"/>\n"
        << "        </prototype>\n"
        << "        <codecs type=\"Vector\" allowHeterogeneousChildren=\"1\"/>\n"
        << "      </points>\n"
        << "    </vectorChild>\n"
        << "  </data3D>\n"
        << "  <images2D type=\"Vector\" allowHeterogeneousChildren=\"1\"/>\n"
        << "</e57Root>\n";

    const std::string xmlStr = xml.str();
    writer.writeLogical(xmlStr);
    const uint64_t filePhysicalLength = writer.finish();
    if (!file) return false;

    // Patch Page 0 header & CV section length, then rewrite Page 0 + its big-endian CRC32C.
    auto &p0 = writer.page0Mutable();
    std::vector<uint8_t> patched(p0.begin(), p0.end());
    writeU64LE(patched, 16, filePhysicalLength);
    writeU64LE(patched, 24, xmlPhysicalOffset);
    writeU64LE(patched, 32, uint64_t(xmlStr.size()));
    writeU64LE(patched, 56, cvSectionLogicalLength);
    std::memcpy(p0.data(), patched.data(), PagedWriter::kPagePayload);

    std::array<uint8_t, 4> p0Crc{};
    writeU32BE(p0Crc, crc32c(p0.data(), PagedWriter::kPagePayload));

    file.seekp(0, std::ios::beg);
    file.write(reinterpret_cast<const char *>(p0.data()), PagedWriter::kPagePayload);
    file.write(reinterpret_cast<const char *>(p0Crc.data()), 4);
    file.flush();
    return bool(file);
}

} // namespace pc_e57

#pragma once

#include "PointCloudCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <fstream>
#include <limits>
#include <memory>
#include <vector>

namespace pc_las {

inline void putU16LE(std::ostream &os, uint16_t v) {
    const char b[2]{char(v & 0xFFu), char((v >> 8) & 0xFFu)};
    os.write(b, 2);
}

inline void putU32LE(std::ostream &os, uint32_t v) {
    const char b[4]{char(v & 0xFFu), char((v >> 8) & 0xFFu), char((v >> 16) & 0xFFu), char((v >> 24) & 0xFFu)};
    os.write(b, 4);
}

inline void putI32LE(std::ostream &os, int32_t v) {
    putU32LE(os, static_cast<uint32_t>(v));
}

inline void putI64LE(std::ostream &os, int64_t v) {
    const uint64_t u = static_cast<uint64_t>(v);
    char b[8];
    for (int i = 0; i < 8; ++i) b[i] = char((u >> (8 * i)) & 0xFFu);
    os.write(b, 8);
}

inline void putDoubleLE(std::ostream &os, double v) {
    static_assert(sizeof(double) == 8, "double must be 8 bytes");
    uint64_t u = 0;
    std::memcpy(&u, &v, sizeof(u));
    char b[8];
    for (int i = 0; i < 8; ++i) b[i] = char((u >> (8 * i)) & 0xFFu);
    os.write(b, 8);
}

struct LASPoint2 {
    int32_t x, y, z;
    uint16_t intensity;
    uint8_t flags;          // return 1 of 1 = 0x09
    uint8_t classification; // 0
    int8_t scanAngleRank;   // 0
    uint8_t userData;       // confidence
    uint16_t pointSourceId; // 1
    uint16_t r, g, b;       // 16-bit RGB
};

inline void writeRawPoint2(std::ostream &os, const LASPoint2 &pt) {
    putI32LE(os, pt.x);
    putI32LE(os, pt.y);
    putI32LE(os, pt.z);
    putU16LE(os, pt.intensity);
    os.put(static_cast<char>(pt.flags));
    os.put(static_cast<char>(pt.classification));
    os.put(static_cast<char>(pt.scanAngleRank));
    os.put(static_cast<char>(pt.userData));
    putU16LE(os, pt.pointSourceId);
    putU16LE(os, pt.r);
    putU16LE(os, pt.g);
    putU16LE(os, pt.b);
}

inline void writeLASHeader(std::ostream &os, uint32_t count, double scale,
                           double offsetX, double offsetY, double offsetZ,
                           double minX, double maxX, double minY, double maxY, double minZ, double maxZ,
                           uint32_t offsetToPoints, uint32_t numVLRs, uint8_t pointFormatId) {
    os.write("LASF", 4);
    putU16LE(os, 0); // File Source ID
    putU16LE(os, 0); // Global Encoding
    putU32LE(os, 0); // GUID 1
    putU16LE(os, 0); // GUID 2
    putU16LE(os, 0); // GUID 3
    char guid4[8]{};
    os.write(guid4, 8);
    os.put(1); // Version Major
    os.put(2); // Version Minor
    char sysId[32]{};
    std::strncpy(sysId, "iOS LiDAR Scanner", 31);
    os.write(sysId, 32);
    char genSoft[32]{};
    std::strncpy(genSoft, "LiDAR-Scanner 1.2", 31);
    os.write(genSoft, 32);
    putU16LE(os, 1);    // Creation Day
    putU16LE(os, 2026); // Creation Year
    putU16LE(os, 227);  // Header Size
    putU32LE(os, offsetToPoints);
    putU32LE(os, numVLRs);
    os.put(static_cast<char>(pointFormatId));
    putU16LE(os, 26); // Point Data Record Length (Format 2)
    putU32LE(os, count);
    putU32LE(os, count);
    for (int i = 0; i < 4; ++i) putU32LE(os, 0);
    putDoubleLE(os, scale);
    putDoubleLE(os, scale);
    putDoubleLE(os, scale);
    putDoubleLE(os, offsetX);
    putDoubleLE(os, offsetY);
    putDoubleLE(os, offsetZ);
    putDoubleLE(os, maxX);
    putDoubleLE(os, minX);
    putDoubleLE(os, maxY);
    putDoubleLE(os, minY);
    putDoubleLE(os, maxZ);
    putDoubleLE(os, minZ);
}

inline void computeBounds(const std::deque<PCPoint> &points,
                          double &minX, double &maxX,
                          double &minY, double &maxY,
                          double &minZ, double &maxZ) {
    minX = std::numeric_limits<double>::infinity();
    maxX = -std::numeric_limits<double>::infinity();
    minY = std::numeric_limits<double>::infinity();
    maxY = -std::numeric_limits<double>::infinity();
    minZ = std::numeric_limits<double>::infinity();
    maxZ = -std::numeric_limits<double>::infinity();
    for (const auto &p : points) {
        const double x = p.x, y = -p.z, z = p.y;
        minX = std::min(minX, x); maxX = std::max(maxX, x);
        minY = std::min(minY, y); maxY = std::max(maxY, y);
        minZ = std::min(minZ, z); maxZ = std::max(maxZ, z);
    }
}

inline LASPoint2 toLASPoint(const PCPoint &p, double scale, double ox, double oy, double oz) {
    const double x = p.x, y = -p.z, z = p.y;
    return LASPoint2{
        static_cast<int32_t>(std::lround((x - ox) / scale)),
        static_cast<int32_t>(std::lround((y - oy) / scale)),
        static_cast<int32_t>(std::lround((z - oz) / scale)),
        static_cast<uint16_t>(p.confidence * 32767u),
        0x09u,
        0u,
        0,
        p.confidence,
        1u,
        static_cast<uint16_t>(uint32_t(p.r) * 257u),
        static_cast<uint16_t>(uint32_t(p.g) * 257u),
        static_cast<uint16_t>(uint32_t(p.b) * 257u)
    };
}

inline void exportLAS(const std::deque<PCPoint> &points, std::ostream &out) {
    double minX, maxX, minY, maxY, minZ, maxZ;
    computeBounds(points, minX, maxX, minY, maxY, minZ, maxZ);
    const double scale = 0.001;
    const double ox = std::floor(minX), oy = std::floor(minY), oz = std::floor(minZ);
    const uint32_t count = static_cast<uint32_t>(points.size());
    writeLASHeader(out, count, scale, ox, oy, oz, minX, maxX, minY, maxY, minZ, maxZ, 227, 0, 2);
    for (const auto &p : points) {
        writeRawPoint2(out, toLASPoint(p, scale, ox, oy, oz));
        if (!out) break;
    }
}

// ---------------------------------------------------------------------------
// Clean-room MIT-licensed LASzip v2 encoder (POINTWISE_AND_CHUNKED, Format 2:
// POINT10 v2 + RGB12 v2, compatible with LASzip / PDAL / lazrs / QGIS).
// ---------------------------------------------------------------------------
namespace laszip_v2 {

constexpr uint32_t AC_MinLength = 0x01000000U;
constexpr uint32_t AC_MaxLength = 0xFFFFFFFFU;
constexpr uint32_t BM_LengthShift = 13U;
constexpr uint32_t BM_MaxCount = 1U << BM_LengthShift;
constexpr uint32_t DM_LengthShift = 15U;
constexpr uint32_t DM_MaxCount = 1U << DM_LengthShift;

struct ArithmeticBitModel {
    uint32_t update_cycle = 4;
    uint32_t bits_until_update = 4;
    uint32_t bit_0_prob = 1U << (BM_LengthShift - 1U);
    uint32_t bit_0_count = 1;
    uint32_t bit_count = 2;

    void init() {
        bit_0_count = 1;
        bit_count = 2;
        bit_0_prob = 1U << (BM_LengthShift - 1U);
        update_cycle = bits_until_update = 4;
    }

    void update() {
        if ((bit_count += update_cycle) > BM_MaxCount) {
            bit_count = (bit_count + 1U) >> 1U;
            bit_0_count = (bit_0_count + 1U) >> 1U;
            if (bit_0_count == bit_count) ++bit_count;
        }
        uint32_t scale = 0x80000000U / bit_count;
        bit_0_prob = (bit_0_count * scale) >> (31U - BM_LengthShift);
        update_cycle = (5U * update_cycle) >> 2U;
        if (update_cycle > 64U) update_cycle = 64U;
        bits_until_update = update_cycle;
    }
};

struct ArithmeticModel {
    uint32_t symbols = 0;
    std::vector<uint32_t> distribution;
    std::vector<uint32_t> symbol_count;
    uint32_t total_count = 0;
    uint32_t update_cycle = 0;
    uint32_t symbols_until_update = 0;
    uint32_t last_symbol = 0;

    explicit ArithmeticModel(uint32_t numSymbols) : symbols(numSymbols) {
        init();
    }

    void init() {
        distribution.assign(symbols, 0);
        symbol_count.assign(symbols, 1);
        last_symbol = symbols - 1;
        total_count = 0;
        update_cycle = symbols;
        update();
        symbols_until_update = update_cycle = (symbols + 6U) >> 1U;
    }

    void update() {
        if ((total_count += update_cycle) > DM_MaxCount) {
            total_count = 0;
            for (uint32_t n = 0; n < symbols; ++n) {
                total_count += (symbol_count[n] = (symbol_count[n] + 1U) >> 1U);
            }
        }
        uint32_t s = 0;
        uint32_t scale = 0x80000000U / total_count;
        for (uint32_t k = 0; k < symbols; ++k) {
            distribution[k] = (scale * s) >> (31U - DM_LengthShift);
            s += symbol_count[k];
        }
        update_cycle = (5U * update_cycle) >> 2U;
        uint32_t max_cycle = (symbols + 6U) << 3U;
        if (update_cycle > max_cycle) update_cycle = max_cycle;
        symbols_until_update = update_cycle;
    }
};

class ArithmeticEncoder {
public:
    void init(std::vector<uint8_t> *target) {
        out_ = target;
        base_ = 0;
        length_ = AC_MaxLength;
    }

    void done() {
        uint32_t init_base = base_;
        bool another_byte = true;
        if (length_ > 2U * AC_MinLength) {
            base_ += AC_MinLength;
            length_ = AC_MinLength >> 1U;
        } else {
            base_ += AC_MinLength >> 1U;
            length_ = AC_MinLength >> 9U;
            another_byte = false;
        }
        if (init_base > base_) propagateCarry();
        renormEncInterval();
        out_->push_back(uint8_t((base_ >> 24U) & 0xFFU));
        if (another_byte) out_->push_back(uint8_t((base_ >> 16U) & 0xFFU));
        out_->push_back(0);
        out_->push_back(0);
    }

    void encodeBit(ArithmeticBitModel &m, uint32_t sym) {
        uint32_t x = m.bit_0_prob * (length_ >> BM_LengthShift);
        if (sym == 0) {
            length_ = x;
            ++m.bit_0_count;
        } else {
            uint32_t init_base = base_;
            base_ += x;
            length_ -= x;
            if (init_base > base_) propagateCarry();
        }
        if (length_ < AC_MinLength) renormEncInterval();
        if (--m.bits_until_update == 0) m.update();
    }

    void encodeSymbol(ArithmeticModel &m, uint32_t sym) {
        uint32_t x, init_base = base_;
        if (sym == m.last_symbol) {
            x = m.distribution[sym] * (length_ >> DM_LengthShift);
            base_ += x;
            length_ -= x;
        } else {
            x = m.distribution[sym] * (length_ >> DM_LengthShift);
            base_ += x;
            length_ = m.distribution[sym + 1] * (length_ >> DM_LengthShift) - x;
        }
        if (init_base > base_) propagateCarry();
        if (length_ < AC_MinLength) renormEncInterval();
        ++m.symbol_count[sym];
        if (--m.symbols_until_update == 0) m.update();
    }

    void writeBit(uint32_t sym) {
        uint32_t init_base = base_;
        length_ >>= 1U;
        if (sym) base_ += length_;
        if (init_base > base_) propagateCarry();
        if (length_ < AC_MinLength) renormEncInterval();
    }

    void writeBits(uint32_t bits, uint32_t sym) {
        if (bits > 19U) {
            writeShort(static_cast<uint16_t>(sym & 0xFFFFU));
            sym >>= 16U;
            bits -= 16U;
        }
        uint32_t init_base = base_;
        length_ >>= bits;
        base_ += sym * length_;
        if (init_base > base_) propagateCarry();
        if (length_ < AC_MinLength) renormEncInterval();
    }

    void writeByte(uint8_t sym) { writeBits(8U, sym); }
    void writeShort(uint16_t sym) { writeBits(16U, sym); }
    void writeInt(uint32_t sym) {
        writeShort(static_cast<uint16_t>(sym & 0xFFFFU));
        writeShort(static_cast<uint16_t>((sym >> 16U) & 0xFFFFU));
    }

private:
    void propagateCarry() {
        size_t idx = out_->size();
        while (idx > 0) {
            --idx;
            if ((*out_)[idx] != 255U) {
                ++(*out_)[idx];
                break;
            }
            (*out_)[idx] = 0U;
        }
    }

    void renormEncInterval() {
        do {
            out_->push_back(uint8_t(base_ >> 24U));
            base_ <<= 8U;
            length_ <<= 8U;
        } while (length_ < AC_MinLength);
    }

    std::vector<uint8_t> *out_ = nullptr;
    uint32_t base_ = 0;
    uint32_t length_ = AC_MaxLength;
};

class IntegerCompressor {
public:
    IntegerCompressor(uint32_t bits, uint32_t contexts, uint32_t bitsHigh = 8, uint32_t range = 0)
        : bits_(bits), contexts_(contexts), bitsHigh_(bitsHigh), range_(range) {
        if (range_) {
            corrBits_ = 0;
            uint32_t r = range_;
            while (r > 0) { r >>= 1U; ++corrBits_; }
            corrRange_ = range_;
        } else if (bits_) {
            corrBits_ = bits_;
            corrRange_ = (bits_ < 32U) ? (1U << bits_) : 0U;
        }
        if (bits_ < 32U) {
            corrMax_ = int32_t((1U << bits_) / 2U - 1U);
            corrMin_ = -corrMax_ - 1;
        } else {
            corrMax_ = INT32_MAX;
            corrMin_ = INT32_MIN;
        }
    }

    void initCompressor() {
        k_ = 0;
        mBits_.clear();
        for (uint32_t c = 0; c < contexts_; ++c) {
            mBits_.emplace_back(corrBits_ + 1U);
        }
        mCorrector0_.init();
        mCorrectorModels_.clear();
        for (uint32_t i = 1U; i <= corrBits_; ++i) {
            uint32_t mBits = (i <= bitsHigh_) ? i : bitsHigh_;
            mCorrectorModels_.emplace_back(1U << mBits);
        }
    }

    uint32_t k() const { return k_; }

    void compress(ArithmeticEncoder &enc, int32_t pred, int32_t real, uint32_t context) {
        int32_t corr = real - pred;
        if (corrRange_) {
            if (corr < corrMin_) corr += int32_t(corrRange_);
            else if (corr > corrMax_) corr -= int32_t(corrRange_);
        }
        writeCorrector(enc, corr, mBits_[context]);
    }

private:
    void writeCorrector(ArithmeticEncoder &enc, int32_t c, ArithmeticModel &model) {
        if (c == 0) {
            enc.encodeSymbol(model, 0U);
            enc.encodeBit(mCorrector0_, 0U);
            k_ = 0;
            return;
        }
        if (c == 1) {
            enc.encodeSymbol(model, 0U);
            enc.encodeBit(mCorrector0_, 1U);
            k_ = 0;
            return;
        }
        if (c == corrMin_) {
            k_ = corrBits_;
            enc.encodeSymbol(model, k_);
            enc.encodeBit(mCorrector0_, 1U);
            return;
        }
        uint32_t abs_v = (c > 0) ? static_cast<uint32_t>(c - 1) : static_cast<uint32_t>(-c);
        uint32_t k = 0U;
        uint32_t v = abs_v;
        while (v > 0U) { v >>= 1U; ++k; }
        enc.encodeSymbol(model, k);
        k_ = k;
        if (k == 1U) {
            enc.encodeSymbol(mCorrectorModels_[0], c > 0 ? 1U : 0U);
            return;
        }
        uint32_t mapped = (c > 0)
            ? static_cast<uint32_t>(c - 1)
            : static_cast<uint32_t>(int64_t(c) + (INT64_C(1) << k) - 1);
        if (k > bitsHigh_) {
            enc.encodeSymbol(mCorrectorModels_[k - 1U], mapped >> (k - bitsHigh_));
            enc.writeBits(k - bitsHigh_, mapped & ((1U << (k - bitsHigh_)) - 1U));
        } else {
            enc.encodeSymbol(mCorrectorModels_[k - 1U], mapped);
        }
    }

    uint32_t bits_, contexts_, bitsHigh_, range_;
    uint32_t corrBits_ = 32, corrRange_ = 0;
    int32_t corrMin_ = INT32_MIN, corrMax_ = INT32_MAX;
    uint32_t k_ = 0;
    std::vector<ArithmeticModel> mBits_;
    ArithmeticBitModel mCorrector0_;
    std::vector<ArithmeticModel> mCorrectorModels_;
};

struct StreamingMedian5 {
    int32_t values[5]{0, 0, 0, 0, 0};
    bool high = true;
    void init() { values[0] = values[1] = values[2] = values[3] = values[4] = 0; high = true; }
    void add(int32_t v) {
        if (high) {
            if (v < values[2]) {
                values[4] = values[3]; values[3] = values[2];
                if (v < values[0]) { values[2] = values[1]; values[1] = values[0]; values[0] = v; }
                else if (v < values[1]) { values[2] = values[1]; values[1] = v; }
                else { values[2] = v; }
            } else {
                if (v < values[3]) { values[4] = values[3]; values[3] = v; }
                else { values[4] = v; }
                high = false;
            }
        } else {
            if (values[2] < v) {
                values[0] = values[1]; values[1] = values[2];
                if (values[4] < v) { values[2] = values[3]; values[3] = values[4]; values[4] = v; }
                else if (values[3] < v) { values[2] = values[3]; values[3] = v; }
                else { values[2] = v; }
            } else {
                if (values[1] < v) { values[0] = values[1]; values[1] = v; }
                else { values[0] = v; }
                high = true;
            }
        }
    }
    int32_t get() const { return values[2]; }
};

class ChunkEncoder {
public:
    ChunkEncoder()
        : icIntensity_(16, 4),
          icPointSourceID_(16, 1),
          icDx_(32, 2),
          icDy_(32, 22),
          icZ_(32, 20),
          mChangedValues_(64),
          mByteUsed_(128),
          mRgbDiff0_(256),
          mRgbDiff1_(256),
          mRgbDiff2_(256),
          mRgbDiff3_(256),
          mRgbDiff4_(256),
          mRgbDiff5_(256) {}

    void init(const LASPoint2 &first, ArithmeticEncoder &enc) {
        enc_ = &enc;
        icIntensity_.initCompressor();
        icPointSourceID_.initCompressor();
        icDx_.initCompressor();
        icDy_.initCompressor();
        icZ_.initCompressor();
        mChangedValues_.init();
        mByteUsed_.init();
        mRgbDiff0_.init(); mRgbDiff1_.init(); mRgbDiff2_.init();
        mRgbDiff3_.init(); mRgbDiff4_.init(); mRgbDiff5_.init();
        mScanAngleRank_[0].init();
        mScanAngleRank_[1].init();
        for (int i = 0; i < 8; ++i) lastHeight_[i] = 0;
        for (int i = 0; i < 16; ++i) { lastXDiff_[i].init(); lastYDiff_[i].init(); }
        for (int i = 0; i < 4; ++i) lastIntensity_[i] = 0;
        lastIncr_ = 0;
        for (auto &m : mBitByte_) m.reset();
        for (auto &m : mClass_) m.reset();
        for (auto &m : mUserData_) m.reset();

        last_ = first;
    }

    void writePoint(const LASPoint2 &pt) {
        uint32_t r = pt.flags & 0x07U;
        uint32_t n = (pt.flags >> 3U) & 0x07U;
        uint32_t m = 0;
        uint32_t lr = last_.flags & 0x07U;
        uint32_t ln = (last_.flags >> 3U) & 0x07U;
        // LASzip numberReturnMap[n][r] & numberReturnLevel[n][r] simplified for r=1, n=1:
        // m = numberReturnMap[n][r] -> for r=1,n=1 in LASzip map[1][1] = 0!
        if (n == 1U && r == 1U) m = 0U;
        else m = ((n << 2U) | r) & 0x3FU;
        uint32_t lm = (ln == 1U && lr == 1U) ? 0U : (((ln << 2U) | lr) & 0x3FU);

        if (last_.pointSourceId != pt.pointSourceId) { lastIncr_ = 0; }
        else if (r < lr) { lastIncr_ = 0; }
        else if (r == lr && n == ln) { lastIncr_ = 0; }

        int changed = 0;
        if (last_.flags != pt.flags) changed |= 32;
        if (lastIntensity_[m] != pt.intensity) changed |= 16;
        if (last_.classification != pt.classification) changed |= 8;
        if (last_.scanAngleRank != pt.scanAngleRank) changed |= 4;
        if (last_.userData != pt.userData) changed |= 2;
        if (last_.pointSourceId != pt.pointSourceId) changed |= 1;

        enc_->encodeSymbol(mChangedValues_, static_cast<uint32_t>(changed));

        if (changed & 32) {
            auto &model = mBitByte_[last_.flags];
            if (!model) model = std::make_unique<ArithmeticModel>(256);
            enc_->encodeSymbol(*model, pt.flags);
        }
        if (changed & 16) {
            icIntensity_.compress(*enc_, lastIntensity_[m], pt.intensity, (m < 3U ? m : 3U));
            lastIntensity_[m] = pt.intensity;
        }
        if (changed & 8) {
            auto &model = mClass_[last_.classification];
            if (!model) model = std::make_unique<ArithmeticModel>(256);
            enc_->encodeSymbol(*model, pt.classification);
        }
        if (changed & 4) {
            enc_->encodeSymbol(mScanAngleRank_[pt.pointSourceId != last_.pointSourceId ? 1U : 0U],
                               static_cast<uint8_t>(pt.scanAngleRank - last_.scanAngleRank));
        }
        if (changed & 2) {
            auto &model = mUserData_[last_.userData];
            if (!model) model = std::make_unique<ArithmeticModel>(256);
            enc_->encodeSymbol(*model, pt.userData);
        }
        if (changed & 1) {
            icPointSourceID_.compress(*enc_, last_.pointSourceId, pt.pointSourceId, 0);
        }

        uint32_t lm_idx = lm < 16U ? lm : 15U;
        uint32_t isSingle = (n == 1U) ? 1U : 0U;
        int32_t median_x = lastXDiff_[lm_idx].get();
        icDx_.compress(*enc_, median_x, pt.x - last_.x, isSingle);
        lastXDiff_[lm_idx].add(pt.x - last_.x);

        int32_t median_y = lastYDiff_[lm_idx].get();
        uint32_t k_dx = icDx_.k();
        icDy_.compress(*enc_, median_y, pt.y - last_.y, isSingle + (k_dx < 20U ? (k_dx & ~1U) : 20U));
        lastYDiff_[lm_idx].add(pt.y - last_.y);

        uint32_t k_dy = icDy_.k();
        uint32_t k_avg = (k_dx + k_dy) >> 1U;
        uint32_t level = (n == 1U) ? 0U : 1U;
        uint32_t ctx_z = isSingle + (k_avg < 18U ? (k_avg & ~1U) : 18U);
        icZ_.compress(*enc_, lastHeight_[level], pt.z, ctx_z);
        lastHeight_[level] = pt.z;

        // Compress RGB12 v2
        uint32_t sym = 0;
        if ((last_.r & 0x00FFU) != (pt.r & 0x00FFU)) sym |= 1U;
        if ((last_.r & 0xFF00U) != (pt.r & 0xFF00U)) sym |= 2U;
        if ((last_.g & 0x00FFU) != (pt.g & 0x00FFU)) sym |= 4U;
        if ((last_.g & 0xFF00U) != (pt.g & 0xFF00U)) sym |= 8U;
        if ((last_.b & 0x00FFU) != (pt.b & 0x00FFU)) sym |= 16U;
        if ((last_.b & 0xFF00U) != (pt.b & 0xFF00U)) sym |= 32U;
        if ((pt.r & 0x00FFU) != (pt.g & 0x00FFU) || (pt.r & 0x00FFU) != (pt.b & 0x00FFU) ||
            (pt.r & 0xFF00U) != (pt.g & 0xFF00U) || (pt.r & 0xFF00U) != (pt.b & 0xFF00U)) {
            sym |= 64U;
        }
        enc_->encodeSymbol(mByteUsed_, sym);
        int32_t diff_l = 0, diff_h = 0, corr = 0;
        if (sym & 1U) {
            diff_l = int32_t(pt.r & 0xFFU) - int32_t(last_.r & 0xFFU);
            enc_->encodeSymbol(mRgbDiff0_, uint8_t(diff_l));
        }
        if (sym & 2U) {
            diff_h = int32_t(pt.r >> 8U) - int32_t(last_.r >> 8U);
            enc_->encodeSymbol(mRgbDiff1_, uint8_t(diff_h));
        }
        if (sym & 64U) {
            if (sym & 4U) {
                corr = int32_t(pt.g & 0xFFU) - std::clamp(int32_t(last_.g & 0xFFU) + diff_l, 0, 255);
                enc_->encodeSymbol(mRgbDiff2_, uint8_t(corr));
            }
            if (sym & 16U) {
                diff_l = (diff_l + (int32_t(pt.g & 0xFFU) - int32_t(last_.g & 0xFFU))) / 2;
                corr = int32_t(pt.b & 0xFFU) - std::clamp(int32_t(last_.b & 0xFFU) + diff_l, 0, 255);
                enc_->encodeSymbol(mRgbDiff4_, uint8_t(corr));
            }
            if (sym & 8U) {
                corr = int32_t(pt.g >> 8U) - std::clamp(int32_t(last_.g >> 8U) + diff_h, 0, 255);
                enc_->encodeSymbol(mRgbDiff3_, uint8_t(corr));
            }
            if (sym & 32U) {
                diff_h = (diff_h + (int32_t(pt.g >> 8U) - int32_t(last_.g >> 8U))) / 2;
                corr = int32_t(pt.b >> 8U) - std::clamp(int32_t(last_.b >> 8U) + diff_h, 0, 255);
                enc_->encodeSymbol(mRgbDiff5_, uint8_t(corr));
            }
        }

        last_ = pt;
    }

private:
    ArithmeticEncoder *enc_ = nullptr;
    IntegerCompressor icIntensity_, icPointSourceID_, icDx_, icDy_, icZ_;
    ArithmeticModel mChangedValues_, mByteUsed_;
    ArithmeticModel mRgbDiff0_, mRgbDiff1_, mRgbDiff2_, mRgbDiff3_, mRgbDiff4_, mRgbDiff5_;
    std::vector<ArithmeticModel> mScanAngleRank_{ArithmeticModel(256), ArithmeticModel(256)};
    std::array<std::unique_ptr<ArithmeticModel>, 256> mBitByte_{};
    std::array<std::unique_ptr<ArithmeticModel>, 256> mClass_{};
    std::array<std::unique_ptr<ArithmeticModel>, 256> mUserData_{};
    LASPoint2 last_{};
    int32_t lastHeight_[8]{};
    StreamingMedian5 lastXDiff_[16]{};
    StreamingMedian5 lastYDiff_[16]{};
    uint16_t lastIntensity_[4]{};
    int32_t lastIncr_ = 0;
};

} // namespace laszip_v2

inline void exportLAZ(const std::deque<PCPoint> &points, std::fstream &file) {
    double minX, maxX, minY, maxY, minZ, maxZ;
    computeBounds(points, minX, maxX, minY, maxY, minZ, maxZ);
    const double scale = 0.001;
    const double ox = std::floor(minX), oy = std::floor(minY), oz = std::floor(minZ);
    const uint32_t count = static_cast<uint32_t>(points.size());

    constexpr uint32_t kChunkSize = 50000;
    const uint16_t vlrPayloadLen = 46; // 34 + 2 * 6
    const uint32_t offsetToPoints = 227 + 54 + vlrPayloadLen; // 327

    // 1. Write LAS 1.2 Header (point format = 2 | 0x80 = 130, 1 VLR)
    writeLASHeader(file, count, scale, ox, oy, oz, minX, maxX, minY, maxY, minZ, maxZ, offsetToPoints, 1, 2 | 0x80);

    // 2. Write LASzip VLR header (54 bytes)
    putU16LE(file, 0); // reserved
    char userId[16]{};
    std::strncpy(userId, "laszip encoded", 15);
    file.write(userId, 16);
    putU16LE(file, 22204); // record_id
    putU16LE(file, vlrPayloadLen);
    char desc[32]{};
    std::strncpy(desc, "by LiDAR-Scanner (LASzip v2)", 31);
    file.write(desc, 32);

    // 3. Write LASzip VLR payload (46 bytes)
    putU16LE(file, 2); // compressor = POINTWISE_AND_CHUNKED
    putU16LE(file, 0); // coder = ARITHMETIC
    file.put(2);       // version_major
    file.put(2);       // version_minor
    putU16LE(file, 0); // version_revision
    putU32LE(file, 0); // options
    putU32LE(file, kChunkSize);
    putI64LE(file, -1); // num_special
    putI64LE(file, -1); // num_bytes
    putU16LE(file, 2);  // num_items
    // Item 0: POINT10 (6), size 20, version 2
    putU16LE(file, 6); putU16LE(file, 20); putU16LE(file, 2);
    // Item 1: RGB12 (8), size 6, version 2
    putU16LE(file, 8); putU16LE(file, 6); putU16LE(file, 2);

    // 4. Reserve 8-byte chunk_table_start_position at offsetToPoints (327)
    const std::streampos chunkTablePtrPos = file.tellp();
    putI64LE(file, 0);

    // 5. Encode chunks
    std::vector<uint32_t> chunkByteSizes;
    laszip_v2::ArithmeticEncoder enc;
    laszip_v2::ChunkEncoder chunkEnc;
    std::vector<uint8_t> compressedBytes;
    compressedBytes.reserve(1 << 16);

    for (size_t base = 0; base < points.size(); base += kChunkSize) {
        const size_t n = std::min(size_t(kChunkSize), points.size() - base);
        const std::streampos chunkStart = file.tellp();

        const LASPoint2 first = toLASPoint(points[base], scale, ox, oy, oz);
        writeRawPoint2(file, first);

        compressedBytes.clear();
        enc.init(&compressedBytes);
        chunkEnc.init(first, enc);
        for (size_t i = 1; i < n; ++i) {
            chunkEnc.writePoint(toLASPoint(points[base + i], scale, ox, oy, oz));
        }
        enc.done();
        file.write(reinterpret_cast<const char *>(compressedBytes.data()),
                   static_cast<std::streamsize>(compressedBytes.size()));

        const std::streampos chunkEnd = file.tellp();
        chunkByteSizes.push_back(static_cast<uint32_t>(chunkEnd - chunkStart));
    }

    // 6. Write Chunk Table at end of file
    const int64_t chunkTableOffset = static_cast<int64_t>(file.tellp());
    putU32LE(file, 0); // version = 0
    putU32LE(file, static_cast<uint32_t>(chunkByteSizes.size()));
    std::vector<uint8_t> tableBytes;
    laszip_v2::ArithmeticEncoder tableEnc;
    laszip_v2::IntegerCompressor icTotals(32, 2);
    tableEnc.init(&tableBytes);
    icTotals.initCompressor();
    for (size_t i = 0; i < chunkByteSizes.size(); ++i) {
        icTotals.compress(tableEnc, i ? static_cast<int32_t>(chunkByteSizes[i - 1]) : 0,
                          static_cast<int32_t>(chunkByteSizes[i]), 1);
    }
    tableEnc.done();
    file.write(reinterpret_cast<const char *>(tableBytes.data()),
               static_cast<std::streamsize>(tableBytes.size()));

    // 7. Patch chunk_table_start_position
    file.seekp(chunkTablePtrPos);
    putI64LE(file, chunkTableOffset);
    file.flush();
}

} // namespace pc_las

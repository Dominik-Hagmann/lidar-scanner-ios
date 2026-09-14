#include "../LiDARScanner/Core/PointCloudCore.h"
#include <array>
#include <cassert>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <sstream>
#include <vector>

namespace fs = std::filesystem;
void near(float a, float b) { assert(std::abs(a-b) < 1e-5f); }

// Deliberately padded rows catch incorrect assumptions about CVPixelBuffer stride.
struct Fixture {
    std::array<float, 16> depth{};
    std::array<uint8_t, 12> confidence{};
    std::array<uint8_t, 48> luma{};
    std::array<uint8_t, 12> chroma{};
    std::array<float, 16> transform{{1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}};
    Fixture() {
        for (int y=0;y<2;++y) for (int x=0;x<4;++x) { depth[y*8+x] = 2; confidence[y*6+x] = 2; }
        luma.fill(128); chroma.fill(128);
    }
    PCFrame frame() {
        PCFrame f{};
        f.depth = depth.data(); f.depthRowBytes=32; f.width=4; f.height=2;
        f.confidence=confidence.data(); f.confidenceRowBytes=6;
        f.luma=luma.data(); f.chroma=chroma.data();
        f.lumaRowBytes=12; f.chromaRowBytes=6;
        f.imageWidth=8; f.imageHeight=4; f.chromaWidth=4; f.chromaHeight=2;
        // Chroma stride must be >= 4*2 bytes; use a separate buffer below.
        f.fx=2; f.fy=2; f.cx=1; f.cy=0.5;
        f.cameraToWorld=transform.data();
        return f;
    }
};

PCConfig config(uint32_t max=1000) { return PCConfig{0.01f, 0.2f, 5.f, max, 1, 1}; }
std::vector<PCPoint> preview(PCCloud *c) {
    std::vector<PCPoint> p(pc_stats(c).pointCount);
    const auto n = pc_copy_preview(c,p.data(),p.size()); assert(n==p.size()); return p;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    fs::path output(argv[1]); fs::create_directories(output);
    Fixture fixture;
    std::array<uint8_t, 20> chroma; chroma.fill(128);
    PCFrame f=fixture.frame(); f.chroma=chroma.data(); f.chromaRowBytes=10;
    PCCloud *c=pc_create(config()); assert(c);
    assert(pc_ingest(c,f)==8);
    auto p=preview(c); assert(p.size()==8);
    near(p[0].x,-1); near(p[0].y,0.5); near(p[0].z,-2);
    near(p[7].x,2); near(p[7].y,-0.5); near(p[7].z,-2);
    assert(p[0].r==128 && p[0].g==128 && p[0].b==128);
    assert(pc_ingest(c,f)==8 && pc_stats(c).pointCount==8); // repeated frame deduplication
    assert(pc_stats(c).acceptedSamples==16);
    std::array<PCPoint,3> sample{};
    assert(pc_copy_preview(c,sample.data(),sample.size())==3);
    near(sample[2].x,p[5].x); near(sample[2].y,p[5].y);

    char error[512]{};
    for (int format=0;format<3;++format) {
        const auto path=(output/(format==0?"test.ply":format==1?"test-ascii.ply":"test.xyz")).string();
        assert(pc_export(c,path.c_str(),format,error,sizeof(error))==1);
        assert(!fs::exists(path+".partial"));
    }
    const auto bad=(output/"missing"/"test.ply").string();
    assert(pc_export(c,bad.c_str(),0,error,sizeof(error))==0 && error[0]);
    assert(pc_export(c,(output/"invalid.ply").c_str(),8,error,sizeof(error))==0);

    // Confidence, NaN, infinity, non-positive and out-of-range depth are excluded.
    pc_reset(c,config());
    fixture.depth[0]=std::numeric_limits<float>::quiet_NaN();
    fixture.depth[1]=std::numeric_limits<float>::infinity();
    fixture.depth[2]=0; fixture.depth[3]=6;
    fixture.confidence[6]=0; fixture.confidence[7]=255;
    assert(pc_ingest(c,f)==2 && pc_stats(c).pointCount==2);

    // Use a new fixture, keep the explicitly padded chroma plane.
    fixture=Fixture(); f=fixture.frame(); f.chroma=chroma.data(); f.chromaRowBytes=10;
    pc_reset(c,config(3));
    assert(pc_ingest(c,f)==3 && pc_stats(c).pointCount==3 && pc_stats(c).atCapacity==1);
    assert(pc_ingest(c,f)==3 && pc_stats(c).pointCount==3);
    pc_reset(c,config()); assert(pc_stats(c).acceptedSamples==0);

    // Column-major rotation + translation: (a,b,-d) -> (-d,b,-a)+(3,4,5).
    fixture.transform={{0,0,-1,0, 0,1,0,0, 1,0,0,0, 3,4,5,1}};
    assert(pc_ingest(c,f)==8);
    p=preview(c); near(p[0].x,1); near(p[0].y,4.5); near(p[0].z,6);

    // Intrinsics focal lengths: halving focal length doubles off-axis distances.
    pc_reset(c,config()); fixture.transform={{1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}};
    f.fx=1; f.fy=1;
    assert(pc_ingest(c,f)==8); p=preview(c);
    near(p[0].x,-2); near(p[0].y,1); near(p[0].z,-2);

    // Pixel step works in two dimensions and respects padding.
    PCConfig coarse=config(); coarse.pixelStep=2; pc_reset(c,coarse);
    assert(pc_ingest(c,f)==2 && pc_stats(c).pointCount==2);

    // Higher-confidence measurements replace the voxel representative, lower do not.
    fixture.confidence.fill(1); fixture.luma.fill(70); pc_reset(c,config());
    assert(pc_ingest(c,f)==8); assert(preview(c)[0].r==70);
    fixture.confidence.fill(2); fixture.luma.fill(140);
    assert(pc_ingest(c,f)==8); assert(preview(c)[0].r==140);
    fixture.confidence.fill(1); fixture.luma.fill(10);
    assert(pc_ingest(c,f)==8); assert(preview(c)[0].r==140);

    // Full/video range endpoints and both documented YCbCr matrices.
    fixture.confidence.fill(2); f.videoRange=1; fixture.luma.fill(16);
    pc_reset(c,config()); pc_ingest(c,f); assert(preview(c)[0].r==0);
    fixture.luma.fill(235); pc_reset(c,config()); pc_ingest(c,f); assert(preview(c)[0].r==255);
    f.videoRange=0; fixture.luma.fill(128); chroma[0]=128; chroma[1]=180;
    f.matrix709=0; pc_reset(c,config()); pc_ingest(c,f); assert(preview(c)[0].r==201);
    f.matrix709=1; pc_reset(c,config()); pc_ingest(c,f); assert(preview(c)[0].r==210);

    // Sample image position is scaled independently of interface orientation.
    chroma.fill(128); fixture.luma.fill(0);
    fixture.luma[2*12+6]=220; pc_reset(c,config()); pc_ingest(c,f);
    assert(preview(c)[7].r==220 && preview(c)[0].r==0);

    // Negative voxel coordinates use floor, never truncation toward zero.
    PCConfig voxel=config(); voxel.voxelMeters=0.1f;
    f.width=2; f.height=1; f.fx=100; f.fy=100; f.cx=0.5; f.cy=0;
    fixture.depth[0]=1; fixture.depth[1]=1;
    pc_reset(c,voxel); assert(pc_ingest(c,f)==2 && pc_stats(c).pointCount==2);

    // Invalid buffers/calibration must fail without altering the existing scan.
    const auto before=pc_stats(c).pointCount;
    auto invalid=f; invalid.depthRowBytes=0; assert(pc_ingest(c,invalid)==-1);
    invalid=f; invalid.confidence=nullptr; assert(pc_ingest(c,invalid)==-1);
    invalid=f; invalid.fx=0; assert(pc_ingest(c,invalid)==-1);
    fixture.transform[12]=std::numeric_limits<float>::infinity(); assert(pc_ingest(c,f)==-1);
    assert(pc_stats(c).pointCount==before);
    pc_reset(c,config());
    assert(pc_export(c,(output/"empty.ply").c_str(),0,error,sizeof(error))==0);
    assert(!fs::exists(output/"empty.ply"));

    // Exercise a large automatic point cloud with genuinely distinct world voxels,
    // retain the full cloud and export it through the real writer.
    constexpr int width=256, height=128;
    constexpr uint32_t total=uint32_t(width*height*64); // 2,097,152 points
    std::vector<float> largeDepth(width*height, 2.f);
    std::vector<uint8_t> largeConfidence(width*height, 2);
    std::vector<uint8_t> largeLuma(width*height, 128);
    std::vector<uint8_t> largeChroma(width*height/2, 128);
    std::array<float,16> pose{{1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}};
    PCFrame large{};
    large.depth=largeDepth.data(); large.depthRowBytes=width*sizeof(float);
    large.width=width; large.height=height;
    large.confidence=largeConfidence.data(); large.confidenceRowBytes=width;
    large.luma=largeLuma.data(); large.chroma=largeChroma.data();
    large.lumaRowBytes=width; large.chromaRowBytes=width;
    large.imageWidth=width; large.imageHeight=height;
    large.chromaWidth=width/2; large.chromaHeight=height/2;
    large.fx=128; large.fy=128; large.cx=128; large.cy=64;
    large.cameraToWorld=pose.data();
    for (uint32_t limit : {0u, 2000009u}) {
        pc_reset(c,config(limit));
        for (int layer=0;layer<64;++layer) {
            pose[14]=float(layer)*0.0625f;
            assert(pc_ingest(c,large)>=0);
        }
        const uint32_t expected=limit==0 ? total : limit;
        assert(pc_stats(c).pointCount==expected);
        assert(pc_stats(c).atCapacity==(limit==0 ? 0 : 1));
        assert(pc_ingest(c,large)>=0 && pc_stats(c).pointCount==expected);
        const auto path=(output/(limit==0?"large-auto.ply":"large-capped.ply")).string();
        assert(pc_export(c,path.c_str(),0,error,sizeof(error))==1);
        std::array<PCPoint,3> reduced{};
        assert(pc_copy_preview(c,reduced.data(),reduced.size())==reduced.size());
    }
    pc_destroy(c);
    std::cout << "PASS: geometry, transforms, filters, padding, voxel selection, capacity, preview, colors and file errors\n";
    std::cout << "PASS: 2,097,152 points in automatic mode; explicit limit at 2,000,009; global deduplication and full exports\n";
}

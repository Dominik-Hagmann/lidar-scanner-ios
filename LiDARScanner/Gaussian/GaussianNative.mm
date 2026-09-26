#include "GaussianNative.h"
#include <exception>
#include <stdexcept>
#include <memory>
#include <cstdio>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

struct GSEngine {
    MsplatDataset dataset = nullptr;
    MsplatTrainer trainer = nullptr;
    ~GSEngine() {
        if (trainer) msplat_trainer_destroy(trainer);
        if (dataset) msplat_dataset_destroy(dataset);
        msplat_cleanup();
    }
};
static void describe(char *out, size_t size, const char *message) {
    if (out && size) std::snprintf(out, size, "%s", message);
}
#define GS_CATCH \
    catch (const std::exception &e) { describe(error, capacity, e.what()); return 0; } \
    catch (...) { describe(error, capacity, "Unknown native processing error"); return 0; }

GSEngine *gs_open(const char *directory, const char *metallib, MsplatConfig config, char *error, size_t capacity) {
    try {
        // Validate the shader library before upstream accesses its global context.
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        NSError *failure = nil;
        id<MTLLibrary> library = [device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:metallib]] error:&failure];
        if (!device || !library) throw std::runtime_error(failure ? failure.localizedDescription.UTF8String : "Metal unavailable");
        for (NSString *name in library.functionNames) {
            id<MTLFunction> function = [library newFunctionWithName:name];
            if (![device newComputePipelineStateWithFunction:function error:&failure])
                throw std::runtime_error(failure ? failure.localizedDescription.UTF8String : "A required Metal kernel is unavailable");
        }
        msplat_set_metallib_path(metallib);
        auto result = std::make_unique<GSEngine>();
        result->dataset = msplat_dataset_create(directory, config.downscaleFactor, false, 8);
        if (!result->dataset || msplat_dataset_num_train(result->dataset) < 12)
            throw std::runtime_error("At least 12 saved views are required");
        result->trainer = msplat_trainer_create(result->dataset, config);
        if (!result->trainer) throw std::runtime_error("Could not initialize training");
        return result.release();
    } catch (const std::exception &e) { describe(error, capacity, e.what()); return nullptr; }
      catch (...) { describe(error, capacity, "Could not initialize native processing"); return nullptr; }
}
int gs_step(GSEngine *engine, MsplatStats *stats, char *error, size_t capacity) {
    try { *stats = msplat_trainer_step(engine->trainer); msplat_sync(); return 1; } GS_CATCH
}
int gs_checkpoint(GSEngine *engine, const char *path, char *error, size_t capacity) {
    try { msplat_trainer_save_checkpoint(engine->trainer, path); return 1; } GS_CATCH
}
int gs_restore(GSEngine *engine, const char *path, int *iteration, char *error, size_t capacity) {
    try { *iteration = msplat_trainer_load_checkpoint(engine->trainer, path); return 1; } GS_CATCH
}
int gs_export(GSEngine *engine, const char *path, char *error, size_t capacity) {
    try { msplat_trainer_export_ply(engine->trainer, path); return 1; } GS_CATCH
}
void gs_close(GSEngine *engine) { delete engine; }

#pragma once
#include <stdint.h>
#include <stddef.h>
#include "msplat_c_api.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct GSEngine GSEngine;
/* All calls confined to a single serial worker. Exceptions never cross Swift. */
GSEngine *gs_open(const char *directory, const char *metallib, MsplatConfig config, char *error, size_t capacity);
int gs_step(GSEngine *engine, MsplatStats *stats, char *error, size_t capacity);
int gs_checkpoint(GSEngine *engine, const char *path, char *error, size_t capacity);
int gs_restore(GSEngine *engine, const char *path, int *iteration, char *error, size_t capacity);
int gs_export(GSEngine *engine, const char *path, char *error, size_t capacity);
void gs_close(GSEngine *engine);
#ifdef __cplusplus
}
#endif

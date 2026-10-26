#ifndef LLAMA_BRIDGE_H
#define LLAMA_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*LlamaTokenCallback)(const char * _Nullable token, bool is_done, void * _Nullable user_data);

bool llama_bridge_init(void);

// Load model from file (model_path must be an absolute path in app sandbox)
// mmproj_path: optional path to multimodal projector model (pass NULL if text-only)
bool llama_bridge_load_model(const char * _Nonnull model_path, const char * _Nullable mmproj_path, int n_gpu_layers, int n_ctx);

bool llama_bridge_is_loaded(void);

bool llama_bridge_has_vision(void);

const char * _Nonnull llama_bridge_get_media_marker(void);

void llama_bridge_unload(void);

// Run stream generation, with optional image buffer (JPEG/PNG/BMP data bytes)
bool llama_bridge_generate(const char * _Nonnull prompt, const void * _Nullable image_data, size_t image_size, int max_tokens, LlamaTokenCallback _Nonnull callback, void * _Nullable user_data);

void llama_bridge_stop(void);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_BRIDGE_H

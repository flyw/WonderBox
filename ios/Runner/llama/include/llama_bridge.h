#ifndef LLAMA_BRIDGE_H
#define LLAMA_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*LlamaTokenCallback)(const char * _Nullable token, bool is_done, void * _Nullable user_data);

bool llama_bridge_init(void);

// Load model from file (model_path must be an absolute path in app sandbox)
bool llama_bridge_load_model(const char * _Nonnull model_path, int n_gpu_layers, int n_ctx);

bool llama_bridge_is_loaded(void);

void llama_bridge_unload(void);

// Run stream generation
bool llama_bridge_generate(const char * _Nonnull prompt, int max_tokens, LlamaTokenCallback _Nonnull callback, void * _Nullable user_data);

void llama_bridge_stop(void);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_BRIDGE_H

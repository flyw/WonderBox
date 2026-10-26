#import "llama_bridge.h"
#include "llama.h"
#include <string>
#include <vector>
#include <atomic>
#include <mutex>
#include <cstdio>
#include <cstring>

static struct llama_model * s_model = nullptr;
static struct llama_context * s_ctx = nullptr;
static const struct llama_vocab * s_vocab = nullptr;
static std::mutex s_mutex;
static std::atomic<bool> s_stop_flag(false);

static void batch_set_tokens(llama_batch_ext * batch, const llama_token * tokens, int32_t n_tokens, llama_pos pos_0) {
    llama_batch_ext_clear(batch);
    for (int32_t i = 0; i < n_tokens; ++i) {
        const int32_t idx = llama_batch_ext_add_token(batch, 0, tokens[i]);
        const llama_pos pos = pos_0 + i;
        llama_batch_ext_set_pos(batch, idx, &pos);
    }
    llama_batch_ext_set_output_logits(batch, n_tokens - 1, true);
}

bool llama_bridge_init(void) {
    static bool inited = false;
    if (!inited) {
        llama_backend_init();
        inited = true;
    }
    return true;
}

bool llama_bridge_load_model(const char * model_path, int n_gpu_layers, int n_ctx) {
    std::lock_guard<std::mutex> lock(s_mutex);
    llama_bridge_init();

    if (s_ctx) {
        llama_free(s_ctx);
        s_ctx = nullptr;
    }
    if (s_model) {
        llama_model_free(s_model);
        s_model = nullptr;
    }

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = n_gpu_layers > 0 ? n_gpu_layers : 99; // Default offload to Metal

    s_model = llama_model_load_from_file(model_path, model_params);
    if (!s_model) {
        printf("[llama_bridge] Failed to load model from: %s\n", model_path);
        return false;
    }

    s_vocab = llama_model_get_vocab(s_model);

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = n_ctx > 0 ? n_ctx : 2048;
    ctx_params.n_batch = 512;
    ctx_params.no_perf = false;

    s_ctx = llama_init_from_model(s_model, ctx_params);
    if (!s_ctx) {
        printf("[llama_bridge] Failed to create context\n");
        llama_model_free(s_model);
        s_model = nullptr;
        return false;
    }

    printf("[llama_bridge] Model successfully loaded into Metal memory! Context size: %d\n", ctx_params.n_ctx);
    return true;
}

bool llama_bridge_is_loaded(void) {
    std::lock_guard<std::mutex> lock(s_mutex);
    return s_model != nullptr && s_ctx != nullptr;
}

void llama_bridge_unload(void) {
    std::lock_guard<std::mutex> lock(s_mutex);
    if (s_ctx) {
        llama_free(s_ctx);
        s_ctx = nullptr;
    }
    if (s_model) {
        llama_model_free(s_model);
        s_model = nullptr;
    }
    s_vocab = nullptr;
    printf("[llama_bridge] Model unloaded\n");
}

void llama_bridge_stop(void) {
    s_stop_flag.store(true);
}

bool llama_bridge_generate(const char * prompt, int max_tokens, LlamaTokenCallback callback, void * user_data) {
    std::lock_guard<std::mutex> lock(s_mutex);
    if (!s_model || !s_ctx || !s_vocab) {
        const char * err = "【错误：本地模型尚未加载或未找到模型文件】";
        callback(err, false, user_data);
        callback("", true, user_data);
        return false;
    }

    s_stop_flag.store(false);

    std::string prompt_str(prompt);
    const int n_prompt = -llama_tokenize(s_vocab, prompt_str.c_str(), prompt_str.size(), NULL, 0, true, true);
    if (n_prompt <= 0) {
        callback("", true, user_data);
        return false;
    }

    std::vector<llama_token> prompt_tokens(n_prompt);
    if (llama_tokenize(s_vocab, prompt_str.c_str(), prompt_str.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        callback("", true, user_data);
        return false;
    }

    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = false;
    llama_sampler * smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(1337));

    llama_batch_ext * batch = llama_batch_ext_init(s_ctx);
    int n_tokens = n_prompt;
    batch_set_tokens(batch, prompt_tokens.data(), n_prompt, 0);

    if (llama_model_has_encoder(s_model)) {
        if (llama_process(s_ctx, LLAMA_PROCESS_TYPE_ENCODE, batch)) {
            llama_batch_ext_free(batch);
            llama_sampler_free(smpl);
            callback("", true, user_data);
            return false;
        }

        llama_token decoder_start_token_id = llama_model_decoder_start_token(s_model);
        if (decoder_start_token_id == LLAMA_TOKEN_NULL) {
            decoder_start_token_id = llama_vocab_bos(s_vocab);
        }

        batch_set_tokens(batch, &decoder_start_token_id, 1, 0);
        n_tokens = 1;
    }

    const int n_predict = max_tokens > 0 ? max_tokens : 512;
    llama_token new_token_id;

    for (int n_pos = 0; n_pos + n_tokens < n_prompt + n_predict; ) {
        if (s_stop_flag.load()) {
            break;
        }

        if (llama_process(s_ctx, LLAMA_PROCESS_TYPE_DECODE, batch)) {
            break;
        }

        n_pos += n_tokens;

        new_token_id = llama_sampler_sample(smpl, s_ctx, -1);
        llama_sampler_accept(smpl, new_token_id);
        if (llama_vocab_is_eog(s_vocab, new_token_id)) {
            break;
        }

        char piece_buf[256];
        int piece_len = llama_token_to_piece(s_vocab, new_token_id, piece_buf, sizeof(piece_buf), 0, true);
        if (piece_len > 0) {
            std::string piece(piece_buf, piece_len);
            callback(piece.c_str(), false, user_data);
        }

        batch_set_tokens(batch, &new_token_id, 1, n_pos);
        n_tokens = 1;
    }

    callback("", true, user_data);

    llama_batch_ext_free(batch);
    llama_sampler_free(smpl);
    return true;
}

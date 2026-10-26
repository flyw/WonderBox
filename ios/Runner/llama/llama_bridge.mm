#import "llama_bridge.h"
#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include <string>
#include <vector>
#include <atomic>
#include <mutex>
#include <cstdio>
#include <cstring>

static struct llama_model * s_model = nullptr;
static struct llama_context * s_ctx = nullptr;
static const struct llama_vocab * s_vocab = nullptr;
static struct mtmd_context * s_mtmd_ctx = nullptr;
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

const char * llama_bridge_get_media_marker(void) {
    return mtmd_default_marker(); // "<__media__>"
}

bool llama_bridge_load_model(const char * model_path, const char * mmproj_path, int n_gpu_layers, int n_ctx) {
    std::lock_guard<std::mutex> lock(s_mutex);
    llama_bridge_init();

    if (s_mtmd_ctx) {
        mtmd_free(s_mtmd_ctx);
        s_mtmd_ctx = nullptr;
    }
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
    ctx_params.n_ctx = n_ctx > 0 ? n_ctx : 3072;
    ctx_params.n_batch = 512;
    ctx_params.no_perf = false;

    s_ctx = llama_init_from_model(s_model, ctx_params);
    if (!s_ctx) {
        printf("[llama_bridge] Failed to create context\n");
        llama_model_free(s_model);
        s_model = nullptr;
        return false;
    }

    if (mmproj_path && strlen(mmproj_path) > 0) {
        mtmd_context_params mparams = mtmd_context_params_default();
        mparams.use_gpu = true;
        mparams.n_threads = 4;
        s_mtmd_ctx = mtmd_init_from_file(mmproj_path, s_model, mparams);
        if (s_mtmd_ctx) {
            printf("[llama_bridge] Multimodal projector loaded successfully from %s! Support vision: %d\n",
                   mmproj_path, (int)mtmd_support_vision(s_mtmd_ctx));
        } else {
            printf("[llama_bridge] Warning: Failed to load mmproj from: %s\n", mmproj_path);
        }
    }

    printf("[llama_bridge] Model successfully loaded into Metal memory! Context size: %d, mmproj: %s\n",
           ctx_params.n_ctx, s_mtmd_ctx ? "active" : "none");
    return true;
}

bool llama_bridge_is_loaded(void) {
    std::lock_guard<std::mutex> lock(s_mutex);
    return s_model != nullptr && s_ctx != nullptr;
}

bool llama_bridge_has_vision(void) {
    std::lock_guard<std::mutex> lock(s_mutex);
    return s_mtmd_ctx != nullptr && mtmd_support_vision(s_mtmd_ctx);
}

void llama_bridge_unload(void) {
    std::lock_guard<std::mutex> lock(s_mutex);
    if (s_mtmd_ctx) {
        mtmd_free(s_mtmd_ctx);
        s_mtmd_ctx = nullptr;
    }
    if (s_ctx) {
        llama_free(s_ctx);
        s_ctx = nullptr;
    }
    if (s_model) {
        llama_model_free(s_model);
        s_model = nullptr;
    }
    s_vocab = nullptr;
    printf("[llama_bridge] Model and projector unloaded\n");
}

void llama_bridge_stop(void) {
    s_stop_flag.store(true);
}

bool llama_bridge_generate(const char * prompt, const void * image_data, size_t image_size, int max_tokens, LlamaTokenCallback callback, void * user_data) {
    std::lock_guard<std::mutex> lock(s_mutex);
    if (!s_model || !s_ctx || !s_vocab) {
        const char * err = "【错误：本地模型尚未加载或未找到模型文件】";
        callback(err, false, user_data);
        callback("", true, user_data);
        return false;
    }

    s_stop_flag.store(false);

    // Clear KV cache and memory state before starting a new prompt sequence
    llama_memory_t mem = llama_get_memory(s_ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }

    llama_pos current_pos = 0;

    // Multimodal image path
    if (s_mtmd_ctx && image_data && image_size > 0) {
        printf("[llama_bridge] Processing multimodal request with image (%zu bytes)...\n", image_size);
        auto opt = mtmd_helper_init_opt_default();
        auto wrapper = mtmd_helper_bitmap_init_from_buf(s_mtmd_ctx, (const unsigned char *)image_data, image_size, false, opt);
        mtmd_bitmap * bmp = wrapper.bitmap;
        if (!bmp) {
            printf("[llama_bridge] Warning: Failed to parse image data from buffer, falling back to text prompt\n");
        } else {
            std::string prompt_str(prompt);
            const std::string marker = mtmd_default_marker(); // "<__media__>"

            // Count occurrences of marker
            size_t count = 0;
            size_t p = 0;
            while ((p = prompt_str.find(marker, p)) != std::string::npos) {
                count++;
                p += marker.length();
            }

            // We have exactly 1 bitmap. Ensure there is exactly 1 marker in prompt_str.
            if (count > 1) {
                // Replace earlier occurrences with [历史现场画面], keeping only the last marker
                for (size_t i = 0; i < count - 1; ++i) {
                    size_t pos = prompt_str.find(marker);
                    if (pos != std::string::npos) {
                        prompt_str.replace(pos, marker.length(), "[历史现场画面]");
                    }
                }
            } else if (count == 0) {
                prompt_str = marker + "\n" + prompt_str;
            }

            mtmd_input_text input_text = {
                prompt_str.c_str(),
                prompt_str.length(),
                /*add_special*/ true,
                /*parse_special*/ true
            };

            mtmd_input_chunks * chunks = mtmd_input_chunks_init();
            const mtmd_bitmap * bmps[] = { bmp };
            int32_t t_res = mtmd_tokenize(s_mtmd_ctx, chunks, &input_text, bmps, 1);
            if (t_res != 0) {
                printf("[llama_bridge] Warning: mtmd_tokenize error %d, falling back to text prompt\n", t_res);
                mtmd_input_chunks_free(chunks);
                mtmd_bitmap_free(bmp);
                // Fall through to text-only path smoothly
            } else {
                printf("[llama_bridge] Tokenized into %zu multimodal chunks, evaluating into Metal context...\n",
                       mtmd_input_chunks_size(chunks));

                llama_pos n_past = 0;
                llama_seq_id seq_id = 0;
                int32_t n_batch = 512;
                bool logits_last = true;
                llama_pos new_n_past = 0;

                int32_t eval_res = mtmd_helper_eval_chunks(s_mtmd_ctx, s_ctx, chunks, n_past, seq_id, n_batch, logits_last, &new_n_past);
                mtmd_input_chunks_free(chunks);
                mtmd_bitmap_free(bmp);

                if (eval_res != 0) {
                    printf("[llama_bridge] Warning: mtmd_helper_eval_chunks error %d, falling back to text prompt\n", eval_res);
                    // Fall through to text-only path smoothly
                } else {
                    current_pos = new_n_past;
                    printf("[llama_bridge] Multimodal prompt evaluated successfully! Next position: %d\n", (int)current_pos);
                }
            }
        }
    }

    // Text-only path (or fallback if image processing did not set current_pos)
    if (current_pos == 0) {
        std::string prompt_str(prompt);
        // Remove any leftover media marker if running without image
        const std::string marker = mtmd_default_marker();
        size_t m_pos = 0;
        while ((m_pos = prompt_str.find(marker, m_pos)) != std::string::npos) {
            prompt_str.erase(m_pos, marker.length());
        }

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

        llama_batch_ext * prompt_batch = llama_batch_ext_init(s_ctx);
        batch_set_tokens(prompt_batch, prompt_tokens.data(), n_prompt, 0);

        if (llama_model_has_encoder(s_model)) {
            if (llama_process(s_ctx, LLAMA_PROCESS_TYPE_ENCODE, prompt_batch)) {
                llama_batch_ext_free(prompt_batch);
                callback("", true, user_data);
                return false;
            }
            llama_token decoder_start_token_id = llama_model_decoder_start_token(s_model);
            if (decoder_start_token_id == LLAMA_TOKEN_NULL) {
                decoder_start_token_id = llama_vocab_bos(s_vocab);
            }
            batch_set_tokens(prompt_batch, &decoder_start_token_id, 1, 0);
        }

        if (llama_process(s_ctx, LLAMA_PROCESS_TYPE_DECODE, prompt_batch)) {
            llama_batch_ext_free(prompt_batch);
            callback("", true, user_data);
            return false;
        }

        llama_batch_ext_free(prompt_batch);
        current_pos = n_prompt;
    }

    // Sampler setup
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = false;
    llama_sampler * smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(1337));

    llama_batch_ext * batch = llama_batch_ext_init(s_ctx);
    const int n_predict = max_tokens > 0 ? max_tokens : 512;

    for (int i = 0; i < n_predict; i++) {
        if (s_stop_flag.load()) {
            break;
        }

        llama_token new_token_id = llama_sampler_sample(smpl, s_ctx, -1);
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

        llama_batch_ext_clear(batch);
        int32_t idx = llama_batch_ext_add_token(batch, 0, new_token_id);
        llama_batch_ext_set_pos(batch, idx, &current_pos);
        llama_batch_ext_set_output_logits(batch, idx, true);
        current_pos++;

        if (llama_process(s_ctx, LLAMA_PROCESS_TYPE_DECODE, batch)) {
            printf("[llama_bridge] Failed to decode token at pos %d\n", (int)current_pos);
            break;
        }
    }

    callback("", true, user_data);

    llama_batch_ext_free(batch);
    llama_sampler_free(smpl);
    return true;
}

# Research: llama.cpp tooling available

Binary: `tools/llama.cpp/` (build b12359, CUDA 13.5)

## Relevant executables
- `llama-server.exe` — OpenAI-compatible HTTP server (`/v1/chat/completions`) with streaming + (recent) tool-calling support; ideal Slop backend
- `llama-cli.exe` / `llama-completion.exe` — CLI inference
- Vision/multimodal CLIs: `llama-llava-cli.exe`, `llama-qwen2vl-cli.exe`, `llama-minicpmv-cli.exe`, `llama-gemma3-cli.exe`, `llama-mtmd-cli.exe`, `llama-mtmd-debug.exe`
- `mtmd.dll` — multimodal (vision) support library
- `llama-tts.exe` — text-to-speech (voice interaction candidate)
- `llama-quantize.exe`, `llama-gguf-split.exe`, `llama-bench.exe` — ops

## Implications for Slop
- Backend = `llama-server` (OpenAI-compatible) → simpler client (reuse OpenAI SDK / plain REST) than Ollama-specific `/api/chat`
- Vision via mmproj projector (already have `mmproj-BF16.gguf`) + a Qwen model; mtmd library handles image inputs
- Voice interaction possible via `llama-tts` (experimental) — aligns with "conversational continuity/voice" idea
- Tool-calling availability depends on server build + model chat template; test against Qwen3.x

# Research: Ollama models for tool-calling & vision

## Actual inference stack (2026-11-22)
Ollama has **no models** installed. The user's real stack is **llama.cpp** (the user's `llama.cpp launcher`), with GGUF models:

Chat/vision candidates in `models/`:
- `Qwen3.5-9B-The-Defiant-Fable-Uncnr-Heretic-NEO-MAX-MTP-Q6_K.gguf` (8.16 GB)
- `Qwen3.8-9B-Q4_K_M.gguf` (5.38 GB)
- `Qwythos-9B-Claude-Mythos-5-1M-Q4_K_M.gguf` (5.24 GB)
- `mmproj-BF16.gguf` (0.86 GB) — **vision projector** (multimodal)
- `nomic-embed-text-v2-moe.Q4_K_M.gguf` (0.32 GB) — embeddings

## Test results (2026-11-22)
Backend: llama-server b12359, model Qwen3.5-9B (Q6_K) + mmproj-BF16.gguf.

- Tool-calling: PASS — model emitted `tool_calls` (finish_reason: tool_calls) for a `get_time` function. OpenAI-compatible format works.
- Vision: PASS — model read text from a rendered PNG ("HELLO SLOP" → "HELLO SLO", truncation due to image crop). Uses OpenAI `image_url` content parts.
- Speed: ~36 tok/s generation, ~469 tok/s prompt (GPU). Good for streaming UX.

Implications for Slop:
- Backend = llama-server (OpenAI-compatible) confirmed.
- Primary model candidate: Qwen3.5-9B + mmproj (covers both chat/tool-calling AND vision in one model).
- Remaining comparative tests: Qwen3.8-9B and Qwythos-9B for tool-calling (optional; Qwen3.5 is sufficient).

## Open questions
- Which installed Ollama models support tool-calling? (none installed yet)
- Which support vision (multimodal)?
- Performance on this machine (GPU/CPU, VRAM) for streaming chat + vision.

## Candidates to evaluate
Tool-calling capable (Ollama): qwen2.5, qwen3, llama3.1/3.2, mistral-nemo, command-r, etc.
Vision capable: qwen2.5-vl, qwen3-vl, gemma3, llava, llava-phi3, minicpm-v, moondream.

## Test plan
1. `ollama list` → record installed models.
2. For each candidate: send a chat request with a tool definition; check if model emits tool_calls.
3. For vision: send an image; check coherent description.
4. Measure first-token latency and tokens/sec for streaming UX.

## Decision (open)
Pick one default chat model with tool-calling, one vision model (can be same if multimodal). Keep configurable.

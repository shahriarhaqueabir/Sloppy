# Sloppy — Companion Product v1 Design

**Date:** 2026-11-23
**Status:** Approved by the user; amended the same day after a structured review of routes, disclosure, UI destinations, and security. Implementation plan written and awaiting approval.
**Scope:** First consumer product slice — install, onboarding, two brain routes, expanded chat with four quiet destinations.
**Constraint:** No runtime implementation until the amended implementation plan is approved. No commits by the agent; the user owns all commits. No subagents.

## Objective

Make Sloppy a product an ordinary Windows user can install and use without a terminal, an API key, or knowledge of AI tooling. Success is a clean machine going from "no Sloppy" to "companion talking in my chosen voice" with one double-click and a short onboarding flow, plus an explicit opt-in path that lets a user turn the same interface into a workspace companion backed by OpenCode.

Success is measured by: time-to-first-conversation, first-token feel, memory footprint on an 8 GB machine, zero support questions about setup, and — for the opt-in route — whether the user can always see exactly where a message went and what it was allowed to do.

## Locked decisions

These came from the approved brainstorming dialogue and constrain this design. Rows marked "amended" were refined after the structured review.

| Decision | Choice |
| --- | --- |
| First product | Self-contained digital companion, roleplay/conversation primary |
| Default strategy | **A — local-first, OpenCode on demand.** Tier 1 is the first-launch default; Tier 2 is an explicit per-user choice. |
| Tier 1 (default) | Bundled local model, no OpenCode, no account, no network. Badge: `Local · bundled · <model>` |
| Tier 2 (opt-in) | OpenCode is the **harness**, not the provider. It may route to a local provider (Ollama, LM Studio, vLLM, custom loopback OpenAI-compatible endpoint) or a remote provider. Badge names the real route. |
| Tier 3 (opt-in within Tier 2) | Paid provider, e.g. an OpenCode Go subscription with its own Console API key. An option, never Sloppy's reliability guarantee. |
| No automatic failover | **Deferred.** A model switch changes behaviour and privacy, and a retry can repeat an uncertain tool action. If added later, disclose the switch, update the badge, and never blindly retry an uncertain operation. |
| Free vs paid | Not permanent categories. Availability, caps, and billing change; the UI shows provider/model facts and verified terms links, not "free forever" labels. |
| Model class | CPU-capable, 8 GB RAM minimum, no GPU required |
| Install surface | Signed per-user `.exe` installer **and** one-line bootstrap (same payload) |
| Brain selection | `Brain` destination: local vs remote inference, then provider, model, and agent; the effective model is shown before the first message |
| Agent vs model | An agent is instructions + permissions; a model performs inference. An agent may carry a model preference, so the UI resolves and displays the model that will actually answer. |
| Approval UI | `Allow once` / `Reject` only. No `Allow always` in the product surface. |
| Config location | Per-user `%LOCALAPPDATA%\Sloppy\`, portable, no personal absolute paths |
| Architecture | Existing signal/state machine unchanged; provider adapter seam with a controlled OpenCode route |
| CLI adapters | OpenCode harness adapter is a first-class Tier 2 option. No other CLI adapters in v1. |
| Version coupling | Pin the supported OpenCode version for Tier 2 and add API-surface compatibility tests. OpenCode auto-updates, so "works with any version" is not a claim we make. |

## Non-goals

- No tool use, file access, shell, web, or application launch in Tier 1.
- No CLI adapters other than the OpenCode harness in v1.
- No account, login, telemetry, or cloud service in Tier 1. Tier 3 necessarily involves a provider account; credentials stay with OpenCode, never in Sloppy config.
- No automatic brain failover.
- No claim that a selected agent alone isolates the machine (see Capability profiles and security).
- No MSI/MSIX/Store packaging beyond the single per-user `.exe` bootstrapper.
- No changes to CI/CD and no remote configuration.
- No modification of the proven signal resolver, motion engine, face renderer, or live verifier's existing assertions.

## Product shape

Sloppy v1 is an always-available desktop companion. It sits in the system tray with a small animated pea, reacts visually to its own internal state, and holds a conversation in the user's chosen voice. Tier 1 works with no network connection.

The visual state system is a **first-class product feature**, not decoration. Local CPU inference has a 5–40 second first-token latency on low-end hardware. The instant amber reaction, particle burst, and streamed-token feedback are what make that latency feel like a living companion thinking rather than a frozen app.

### Expanded interface

The conversation is the main surface. Four quiet destinations sit around it; the old developer command chips (`startslop`, `stopslop`, `slopstatus`, `verify`, `review`, `kickoff`, `sign out`) move under **Settings → Advanced / developer** rather than being pasted into the input box.

| Destination | Scope — and nothing else |
| --- | --- |
| **Settings** | Startup behaviour, data location, reset/delete conversation, clear Sloppy data, About and version, Advanced / developer. Each destructive action states exactly what it affects. |
| **Customize** | Name, colours, personality, persona text. This describes *how Sloppy behaves*, never what tools it may use. Security permissions are not edited here. |
| **Brain** | Local vs remote inference, then provider, model, and agent. Shows the resolved effective model and the route before the first message. |
| **Privacy** | The actual data route for the active setup, with links to the applicable provider's terms and privacy policy. |

A header badge is always visible and names the **actual route**, not the tier label:

- `Local · bundled · Qwen3 4B Q4_K_M`
- `Local · Ollama · qwen3:8b`
- `Remote · OpenCode Go · Beam Free`

`Tier 2 · OpenCode` alone is incomplete and must not be used as a badge: OpenCode is the harness, while the model provider may be local or remote. OpenCode supports session-level model switching (`POST /api/session/{sessionID}/model`) and lists models from what is enabled and available in that location, so the badge must be recomputed from the effective configuration rather than cached from onboarding.

## Route taxonomy and data path

The product distinguishes the **harness** from the **model provider**. State precisely, in this order:

1. **Tier 1 — bundled local.** Sloppy sends the message to the bundled `llama-server.exe` on loopback. No OpenCode, no account, no network. Nothing leaves this PC *except* what the user separately enables through a tool-capable route.
2. **Tier 2 — OpenCode harness, local provider.** Sloppy sends the message to a local OpenCode service. OpenCode sends the prompt and relevant context to a local provider (Ollama / LM Studio / vLLM / custom loopback endpoint). Model traffic stays on the machine; "nothing leaves this PC" is true for the model request only.
3. **Tier 2 — OpenCode harness, remote provider.** Sloppy sends the message to OpenCode on this PC. OpenCode sends the prompt and relevant context to the selected remote model provider. That provider's terms, privacy policy, and data regulations apply to that hop.
4. **Tier 3 — paid provider.** Same path as 3 with a subscribed provider. Credentials are connected in OpenCode; Sloppy stores no key.

Context that can be sent on an OpenCode route includes: the user's message, selected agent instructions, persona text passed as system prompt, relevant conversation context, files the user allowed, tool requests and their results. Which of those can happen is governed by the effective permission rules and hard-deny policies of the controlled OpenCode configuration — not by the agent's name alone.

Deleting an OpenCode session also deletes its child sessions (verified in OpenCode `packages/core/src/session.ts:404-418` and its `Session.remove` test). That is a statement about OpenCode's local session store; it does **not** imply that a remote provider deleted its copy of a prompt or transcript. The UI must not say "deleted everywhere."

## Disclosure and consent

Shown in `Brain` before the first message on any OpenCode route, and always reachable from `Privacy`:

> Sloppy draws the pea and holds the conversation. Thinking is done by OpenCode, an open-source (MIT) agent harness that has been heavily exercised in development. In this setup your message goes first to OpenCode on this PC; OpenCode then sends the prompt, the selected agent's instructions, and any context, files, or tool results you have allowed to the selected model provider. If that provider is remote, its policies and data regulations apply to that hop, not Sloppy's.
>
> The route above shows exactly which provider and model will answer. Read that provider's documentation and privacy terms before sending anything sensitive. Agent availability, caps, and billing change; we do not promise a model is free or permanent.
>
> [Change provider / model / agent] · [Add a paid provider — account and billing handled by OpenCode] · [Stay local — Tier 1 companion, no OpenCode route]

Rules for this copy:

- Do **not** state a blanket retention period. OpenCode documents per-model differences (for example Beam Free 30 days, Gemini 4 Argon up to 55 days, several models 0 days, and some endpoints marked "Not ZDR"). Show the verified fact for the selected provider/model and link to its source.
- Do **not** describe "one-click sign-in" as available. OpenCode Go currently requires a Console subscription, an API key, and `/connect` in the TUI. Treat a one-click integration as a goal to verify, not an assumption.
- Do **not** call agents "free" or "paid" as permanent categories.

## Capability profiles and security

The trust boundary flips when an OpenCode route is enabled. Granting shell, file, web, or app-launch access makes this a general agent acting with the user's authority, not a pet. Prompt injection from a web page or a file becomes a real path.

Verified OpenCode facts that shape the design:

- Permission rules merge in order: lower-priority configuration first, global rules next, agent rules last; **the last matching rule wins** (OpenCode `/permissions`).
- The default base policy already contains `* → allow`; `external_directory` also defaults to allow. A deny-by-default posture must be configured explicitly.
- A [policy](/policies) hard-deny runs **after** rules and saved approvals, turns `allow` or `ask` into `deny`, and never grants access.
- Saved approvals are durable, project-scoped `allow` rules; they never override a configured `deny`, but they are appended after agent rules and can therefore override an agent `ask`.
- Global config is lower precedence than project config, so "never inherit the global config" cannot be achieved by the selected agent alone.

Therefore:

1. Sloppy must launch or connect to a **controlled OpenCode configuration** and **verify the effective permissions through the live API before accepting prompts**. Fail closed if verification is inconclusive. Do not promise isolation based only on the selected agent.
2. Capability profiles — **Companion** (no tools), **Workspace** (chosen read-only folders), **Power** (shell / app launch / web with explicit warnings) — must correspond to enforceable, tested rules, not just UI presets.
3. Approval cards offer `Allow once` and `Reject` only. No `Allow always` in the product. Verify against the shipped OpenCode version that hard-deny still takes precedence over saved approvals.
4. Hard denies for `service.json`, `.ssh/*`, `.env*`, `.aws/*`, gcloud credentials, and webfetch to loopback, metadata addresses, or `file://`.
5. Check which powerful HTTP routes Sloppy can reach are covered by tool permissions: `POST /api/shell`, `POST /api/session/{id}/shell`, `GET /api/fs/read/*`, `POST /api/experimental/fs/write`, `GET /api/credential`, `POST /api/experimental/mcp/{server}`, `POST /api/debug/heap-dump`. The existing route review marks this **unverified**; do not assume these routes pass through tool permissions. Keep the loopback service password like an SSH key, never in argv, URLs, or logs.
6. `Stop` is **not** a security control. Interrupt may stop the model stream without killing a spawned shell job, PTY, or subagent. Verify live and report the result before release; fallbacks include `/api/experimental/job/{id}/cancel`, `/api/shell/{id}`, and PTY routes.
7. Separate three actions in Settings: **clear conversation** (UI transcript), **delete OpenCode session** (local session plus children), **clear Sloppy local data** (config/persona). Explain each scope before the user confirms.
8. Cap input text and rendered delta/tool-output sizes; exact-match session IDs on events; no raw payloads in bubbles or logs; delete sessions on close/reset.

## Distribution and install

### Primary path — single signed `.exe`

A WiX bootstrapper produces one installer executable. Per-user installation into `%LOCALAPPDATA%\Programs\Sloppy\` so **no UAC elevation is required**. The installer:

- creates a Start menu entry and a tray icon;
- enables autostart by default, toggleable from Settings and the tray menu;
- bundles the llama.cpp runtime, the GGUF model, and the Sloppy scripts;
- registers a clean uninstall that removes the install directory and the per-user config directory;
- reports version and progress in plain language.

A code-signing certificate is required. Acquiring one is a user-owned prerequisite, not an implementation task.

### Secondary path — one-line bootstrap

A one-line PowerShell bootstrap hosted at the project's release URL downloads and runs the same installer in silent mode with progress output. Intended for technical users; it is never presented to the non-technical audience as the primary path. The exact URL is a release-time value supplied by the user, not a design decision.

### System requirements

Windows 10 or 11 x64, 8 GB RAM, no GPU. The installer checks available RAM and warns (but does not hard-block) below 6 GB.

### Trade-off accepted

Bundling makes the download roughly 3 GB. Download-on-first-run produces a smaller installer but damages the "works immediately" experience for the target audience, so bundling remains the default. An optional in-app model download is an approved alternative if installer size blocks adoption; it does not change the architecture.

## First-run onboarding

On first launch the app opens onboarding; the pea is already visible and animated behind it. Four screens, each one decision and a live preview:

1. **Name** — companion name; user's name optional and used only for personalisation.
2. **Base color** — six swatches applied live to the pea's decorative identity accent. Semantic signal colors (blue / amber / green / red) are fixed by the state machine and are never overridden by this choice.
3. **Personality** — four presets (Calm, Playful, Curious, Professional) plus an optional free-text persona box. This is behaviour, never permissions.
4. **Brain** — "Built-in (works offline)" is the recommended default. "Use OpenCode" is opt-in and immediately explains the data route; a paid provider is offered as a further opt-in. No provider is described as permanently free.

Onboarding is re-openable from Settings and the tray as "Edit personality" and "Change brain". It is not a one-way gate. The first message on any remote route requires the disclosure acknowledgement; the badge always shows the resolved route.

## Portable configuration and security

All user state lives in `%LOCALAPPDATA%\Sloppy\`:

- `config.json` — name, color, personality selection, route choice, provider/model/agent selection, capability profile, autostart preference, config version;
- `persona.md` — the custom persona text used as the system prompt;
- no provider credentials, no OpenCode service password.

Settings writes its autostart value to `config.json` and updates the autostart entry; the installer's default applies only when no config file exists. The only registry write in the product is that single per-user autostart entry. No machine-specific absolute paths, no secrets stored in the repo.

The repository config was scrubbed during showcase preparation: `.opencode/opencode.jsonc` carries no broad `external_directory` grant and uses a portable template persona path (`~/.config/opencode/personality.md`). `Test-SlopOpenCodeConfig` in `src/Slop.OpenCode.ps1` fails closed on any reintroduced external grant, and `tests/slop-opencode-check.ps1` was updated to match. The shipped Tier 1 product does not require OpenCode at all; Tier 2 uses a generated, controlled configuration, never the developer's global config.

Config migration uses an explicit `version` field: unknown keys are ignored, known keys are validated, and the previous file is backed up before any upgrade write.

## Architecture and data flow

The existing signal/state machine is untouched. Adapters feed the same queue the OpenCode bridge feeds today:

```
Send
  → route resolution (badge = harness + provider + effective model)
  → adapter
  → SSE deltas
  → StreamQueue
  → Set-SlopSignalEvent
  → Get-SlopSignal (priority + newest wins)
  → Set-SlopVisualFromSignal
  → brush / glyph / face / OpenPulse → pixels
```

Adapters and routes:

- **Built-in** — launches bundled `llama-server.exe` with the bundled GGUF, polls `/health`, then streams `/v1/chat/completions`.
- **Custom endpoint** — same protocol against a user-supplied local OpenAI-compatible base URL and model name.
- **OpenCode harness** — reuses the proven session/event/permission bridge. It pins an agent, opens `/api/event` with the exact allowlisted types before prompting, posts the prompt, and maps `permission.asked` to in-chat approval cards. Session-level model switching is used when the selected agent carries a model preference; the displayed badge follows the effective model.

Suggested new files: `src/Slop.Config.ps1`, `src/Slop.LocalModel.ps1`, `src/Slop.Provider.ps1`, `src/Slop.Route.ps1`, `src/Slop.OpenCodeProfile.ps1`, `src/Slop.Disclosure.ps1`, `src/Slop.Surfaces.ps1`, `src/Slop.Adapter.OpenAi.ps1`, `src/Slop.Adapter.OpenCode.ps1`, and WPF panels implemented in the existing XAML style. Existing motion/frame/face/lifecycle logic is unchanged; `src/Slop.ps1` receives wiring only.

Adapters map to existing signals: request start → `thinking`; first token → `working`; deltas → streamed text; terminal success → `success`; failure → `error`; user stop → `cancelled`.

## Model lifecycle and performance

- Model: Qwen3 4B at Q4_K_M (approximately 2.5 GB file, 3.7 GB RAM at 4k context). Qwen3 is documented as strong at roleplay, creative writing, and multi-turn conversation, which matches the companion premise.
- Runtime: existing `llama.cpp` build documented in `docs/research/llama-cpp-tooling.md`; `llama-server.exe` already provides OpenAI-compatible streaming.
- Launch flags: 4k context, `--cache-ram 0`, conservative thread count, modest response length.
- Lifecycle: starts with the app and stays warm. A tray "Sleep model" action releases the ~3.7 GB when the user needs memory back; the next message wakes it with a visible "waking up" state.
- Latency masking: amber signal and particle burst land on the same frame as Send; tokens render as they arrive; no request ever waits for a complete reply before the UI reacts.

Qwen3-4B-GGUF redistribution was verified during planning: the model card ships an Apache License 2.0 file, and the Q4_K_M quant is approximately 2.5 GB. If a later build changes the quant or terms, substitute an Apache-2.0-licensed roleplay-capable model of similar size; this substitution does not change the architecture.

## Error handling

- A pre-first-message health check catches missing runtime, port conflict, and corrupt GGUF, then shows plain-language repair guidance rather than a stack trace.
- An OpenCode route that cannot verify effective permissions, cannot find the pinned version, or returns an unknown event shape fails closed with a plain-language message and never silently falls back to another brain.
- Out-of-memory conditions are caught and explained with a suggestion to close other applications or sleep the model; the app does not crash.
- Cancellation reuses the token-aware `ReadLineAsync(CancellationToken)` path already proven in `src/Slop.Lifecycle.ps1`. No new cancellation implementation. Stop's side-effect limit is disclosed, not hidden.
- Terminal event handling reuses the existing normalization: `succeeded`, `failed`, `interrupted`, and `idle` all finalize the stream.
- Config migration backs up before writing and degrades gracefully on an unreadable file by starting onboarding again.

## Verification

Before this work is called complete:

1. All existing Pester tests green via `tests/Slop.Tests.ps1` (record the exact count).
2. Tour check green: 38/38 tests, 16 anchors matching.
3. Adapter contract suite against a fake OpenAI-compatible SSE server: deltas, terminal events, cancellation, malformed frames.
4. Route suite: taxonomy, badge string for bundled / local-provider / remote-provider, agent model preference resolution, recomputation on model switch.
5. Controlled-config suite: capability profiles generate the intended rules, hard-deny statements present, effective-permission verification fails closed on unexpected grants, no `Allow always` saved by the product.
6. Disclosure suite: correct provider terms link, no blanket retention claim, no "free forever" wording, deletion copy distinguishes local session from provider copy.
7. Config migration suite: version upgrade, unknown keys, corrupt file recovery.
8. Live verifier extended with onboarding, a real bundled-model reply, a badged local-provider route, and a remote route guarded by disclosure, retaining guaranteed teardown.
9. Live Stop test: token stream freezes **and** any spawned job/PTY/subagent is accounted for; report the result, do not claim Stop is a security control if unverified.
10. Measured peak RSS below 4.5 GB at 4k context on an 8 GB reference machine; record command and output.
11. Installer silent install, autostart toggle, tray controls, and clean uninstall checked manually on a clean Windows VM.
12. Credential, token, and personal-path scrub of all tracked files before any public push.
13. OpenCode version pin and API-surface compatibility test for the event/agent/model/permission routes used by Tier 2.

No push, PR, deploy, or CI/CD change is part of this work.

## Risks and constraints

- **8 GB conflict:** a 4B CPU model has 5–40 s first-token latency. Mitigated but not eliminated by the visual state system. Approved fallback: smaller default model with the 4B as an in-app download.
- **Trust boundary:** a tool-capable route is a general agent, not a pet. Mitigated by controlled config, effective-permission verification, enforceable profiles, hard denies, and honest disclosure; never eliminated.
- **Third-party coupling:** OpenCode's permission model, event names, and provider catalog change. Pin the version and test the surface; do not claim universal compatibility.
- **Provider terms:** retention and training terms differ by provider and model and can change. Show verified, linked facts only.
- **Signing certificate:** required for the `.exe` path and not obtainable by the agent.
- **Model licence:** Qwen3-4B-GGUF is Apache-2.0 (verified from the model card); attribution must ship with the bundled model.
- **Git history:** the scrubbed working tree is clean, but older commits still contain personal paths. Publish from a fresh history-free snapshot, never by pushing this repository as-is.
- **No subagents**, local commits only, no CI changes.

## Public release gate

The showcase artifacts are staged but not pushed. Personal paths, the personal persona name and the handle were scrubbed from all tracked text and staged; image assets were checked for embedded metadata. Six older commits still contain personal repository paths, so this repository must not be pushed as-is. A clean, history-free snapshot of the 91 tracked showcase files (agent memory excluded) is prepared under the local temp directory at `sloppy-public-v1-20261124/` with no `.git` directory. The user creates the public repo, copies those files in, and makes the first commit. The only remaining identity string is the intentional MIT `Copyright (c) 2026 shahr` attribution in `LICENSE` and the quoted copy in the showcase plan. The agent must not push; the user performs all remote operations manually.

## Open prerequisites

These are user-owned and do not block writing an implementation plan:

- Code-signing certificate and release host URL for the installer.
- Clean Windows VM for manual installer verification.
- Final Qwen3 attribution text and quant filename from the selected release build.
- For Tier 3: the user's chosen paid provider account and credentials, connected in OpenCode by the user.
- Verified terms/privacy URLs for every provider shipped in the Brain picker.

## Transition

The spec and the amended implementation plan are the source of truth. No implementation begins before the amended plan is approved. Work proceeds in the reviewed order: route semantics → controlled configuration and effective permissions → local inference and badge → Brain picker → disclosure → Settings/Customize → optional paid provider; automatic failover is deferred.

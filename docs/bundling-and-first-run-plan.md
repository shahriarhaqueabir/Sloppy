# Sloppy Bundling & First-Run Plan (Scaffold)

> Draft scaffold for packaging Sloppy. This is a planning artifact, not a shipped installer spec. Verify against current code, tests, and runtime contracts before implementation.

## Goal

Ship Sloppy so a fresh Windows user can install it and get **Tier 1 ready to go**. On first launch, **Sloppy comes alive**: it greets the user, introduces itself, explains what it can do now, and walks the user through a **user-driven systems check / flight test** before handing over the reins.

Tier 2 is not a first-run fork. It is a **deliberate later upgrade**, started only when the user feels ready. When they choose it, Sloppy stages Tier 2 carefully: onboarding, system/config preflight, guided setup, user-driven flight test, and a new introduction covering the additional capabilities unlocked by Tier 2.

The installer/first-run flow must check prerequisites, explain what is needed, install or guide installation of required components, and verify readiness before the user is asked to rely on Sloppy.

## Current Size Reality

| Component | Approx. size | Needed at runtime? | Packaging decision |
|---|---:|---|---|
| `.git/` + `.git/lfs` | ~4.36 GB | No | **Never ship** in installer. |
| `runtime/models/gemma-4-E2B_q4_0-it.gguf` | ~3.19 GB | Tier 1 local text | **Download on demand** (default Tier 1 component). |
| `runtime/models/gemma-4-E2B-it-mmproj.gguf` | ~0.94 GB | Future multimodal image/audio | **Optional download, feature-gated**; do not bundle until multimodal is live-verified. |
| `runtime/llama-b12676-bin-win-cuda-13.5-x64/` | ~0.27 GB | Tier 1 local runtime | **Download selected backend only**; trim unused CLI tools. |
| `assets/Sloppy.mp4` | ~29 MB | No | Release/web asset, **not installer payload**. |
| `src/`, required `.opencode` fallback, runtime assets | <1 MB | Yes | **Bundle**. |
| `tests/`, `docs/`, `.tours/`, dev tools | small | No | **Exclude** from end-user installer. |

**Key point:** the real payload is dominated by model weights. A one-click *experience* is possible; a one-click *fully offline Tier 1 installer* will still be multi-GB.

## Recommended Product Flow

**Recommendation: Tier 1 is the starting point and default ready-to-go experience. Tier 2 is an opt-in upgrade unlocked after the user is comfortable with Tier 1.**

| Phase | User experience | What Sloppy does | Downloads/setup |
|---|---|---|---|
| **Install / bootstrap** | Simple install, clear progress, no technical decisions required unless needed | Installs Sloppy shell, checks system, prepares Tier 1 component manager | Thin installer + signed manifest; Tier 1 components staged/downloaded as needed. |
| **Tier 1 first launch** | Sloppy comes alive, greets the user, introduces itself | Explains what Sloppy is, what it can do now, privacy/local-first boundaries, and what it needs | Confirms Tier 1 local brain is installed and healthy. |
| **Tier 1 guided flight test** | User-driven “Test all systems for go” | Runs checks one by one with plain-language status: runtime, model, local health, chat response, motion/signal, permissions/safety basics | Downloads/repairs missing Tier 1 components only when user approves. |
| **Tier 1 handoff** | User gets the reins | Sloppy confirms readiness, suggests safe first tasks, and keeps help available | No forced Tier 2 prompt; just a calm “When you’re ready, I can connect to OpenCode for more capabilities.” |
| **Tier 2 opt-in upgrade** | User chooses “Upgrade to Tier 2” when ready | Sloppy re-introduces itself with new capabilities, explains risks/tradeoffs, and starts staged onboarding | OpenCode detection/install, config/profile verification, provider/model setup guidance. |
| **Tier 2 guided flight test** | User-driven verification before full use | Checks OpenCode service, config/profile, permissions, provider/model, prompt round-trip, approval flow | Only Tier 2 components/config actions selected by user. |
| **Tier 2 handoff** | User gets the reins with expanded capabilities | Sloppy explains what’s now possible, what still stays local, and what can leave machine depending on provider | Both tiers verified independently; clear active-route indicator. |

### Why this flow

- **Tier 1 first:** delivers the Sloppy promise immediately - local, alive, trustworthy, ready to go.
- **No early fork:** avoids asking fresh users to choose between local brain and OpenCode before they understand Sloppy.
- **User-driven tests:** builds confidence. Sloppy never claims “ready” without checks the user can see.
- **Tier 2 as upgrade:** respects readiness. Power features arrive after the user has a stable baseline.
- **Calm onboarding:** Sloppy teaches, verifies, and hands over control gradually.

## Tier 1: Ready-To-Go Onboarding (Default Path)

Tier 1 is the shipped starting point. The user should never be dropped into an empty shell.

### 1. Bootstrap install
- Thin signed installer installs Sloppy app shell and component manager.
- Preflight checks run before large downloads: Windows x64, disk, write access, CPU baseline, GPU/driver detection, network/offline source.
- Sloppy shows a plain-language plan: what will be installed, total size, where files go, and what stays local.

### 2. Sloppy comes alive
- First launch opens with Sloppy present, calm, and local.
- Sloppy greets the user and gives a short intro:
  - **Who I am:** your desktop companion for AI work.
  - **What I can do now (Tier 1):** local chat with bundled Gemma, visible state/motion, local-first privacy, basic controls.
  - **What I can’t do yet:** no remote provider/OpenCode agent capabilities until Tier 2 is set up; no multimodal claims unless verified.
  - **How I stay safe:** clear boundaries, visible status, fail-closed checks.

### 3. User-driven “Test all systems for go”
- Sloppy offers a guided verification checklist. The user initiates each check; Sloppy explains it before running it.
- Suggested checks:
  - **App shell:** UI/assets/config writable.
  - **Runtime:** selected llama backend present, compatible, launches.
  - **Model:** Gemma Q4 present, checksum ok, loads.
  - **Local brain:** health probe passes; tiny test prompt returns.
  - **Signals/UI:** color/motion/status indicators respond correctly.
  - **Safety baseline:** local-only mode, disclosure/permissions/status visible.
- Each check reports `Pass / Needs action / Skipped` with repair/retry.

### 4. Tier 1 handoff
- Sloppy summarizes what is ready, what is optional, and what is deferred.
- Sloppy suggests a first easy task and a first verification task the user can do themselves.
- Sloppy offers help chips: “Show me around”, “Run checks again”, “Manage components”, “When I’m ready, upgrade to Tier 2”.
- Only after checks pass (or user explicitly accepts a limited mode) does Sloppy hand over the reins.

## Tier 2: Opt-In Upgrade (Staged, User-Driven)

Tier 2 begins only when the user clicks **Upgrade to Tier 2**. It is not required for first use.

### 1. Tier 2 intro and readiness gate
- Sloppy explains what Tier 2 adds: OpenCode agent harness, provider/model options, tool/permission workflow, richer coding workflows.
- Sloppy explains tradeoffs: remote providers may send data off-machine depending on configuration; permissions and config matter.
- User confirms: “I’m ready to set up Tier 2”.

### 2. Tier 2 preflight and staged setup
- **Detect:** existing OpenCode install/service/config/provider.
- **Plan:** show what is missing, what will be installed/changed, and what will not be touched.
- **Install/Configure:** OpenCode install/update if needed; verify/create Sloppy zero-trust fallback config only when no active config exists; never overwrite active user config.
- **Connect:** guided provider/model/agent selection; credentials handled by user/provider flow, never stored in logs.
- **Permissions:** explain approval cards, allow-once/reject, and fail-closed behavior.

### 3. Tier 2 user-driven flight test
- Sloppy runs a guided Tier 2 checklist:
  - **OpenCode service reachable** (`/api/info` or equivalent).
  - **Config/profile valid** and Sloppy permission profile verified.
  - **Agent/model selected** and compatible.
  - **Prompt round-trip** completes.
  - **Permission card flow** appears and records user decision correctly.
  - **Route/status** clearly shows Tier 2/OpenCode active.
- Failures are actionable: retry, repair, rollback to Tier 1, or keep Tier 1 active.

### 4. Tier 2 handoff
- Sloppy gives a new intro: “Here’s what’s now possible.”
- Sloppy explains the active mode: Tier 1 local, Tier 2 OpenCode, or both available.
- Sloppy suggests a small Tier 2 test task, then a real task, with checks still available.
- The user gets the reins only after successful verification or explicit informed acceptance of limited capability.

## Preflight & Prerequisite Matrix

The installer/first-run must **check, report, and act** on required items. It should install what is safe/automatable, and give clear guided steps for what is not. Checks are **visible to the user** and can be rerun at any time.

| Check | Tier 1 Local | Tier 2 Upgrade | Action |
|---|---|---|---|
| Windows 10/11 x64 supported build | Required | Required | Block with clear message if unsupported. |
| Disk space | Required (app + runtime + model; extra headroom) | Required (app + OpenCode) | Show required/free space; block download if insufficient. |
| PowerShell 7.6+ / app host runtime | Required | Required | Bundle app host or install pinned pwsh runtime; do not depend on system pwsh. |
| .NET Desktop/WPF runtime needed by host | Required | Required | Bundle or install via trusted bootstrapper. |
| Visual C++ Redistributable (if runtime needs it) | Required if needed by selected llama build | Usually not | Detect/install with explicit consent/admin prompt when needed. |
| CPU arch/AVX capabilities | Required | N/A | Select compatible llama backend; fail clearly if unsupported. |
| NVIDIA GPU + driver + CUDA compatibility | Optional, for CUDA backend | N/A | Detect; pick CUDA pack only when compatible, else CPU/Vulkan fallback. **Do not auto-install GPU drivers silently**; give guided steps. |
| RAM/VRAM/context budget | Required sanity check | N/A | Warn/block based on selected model/context; default 8k; explain 16k/32k impact. |
| Network access for downloads | Required if components missing | Required if components missing | Allow offline installer/cache mode for pre-bundled/full packs. |
| Write access to install/data dirs | Required | Required | Default `%LOCALAPPDATA%\Programs\Sloppy`; repair permissions. |
| Model/runtime integrity | Required | N/A for local model unless Both | SHA256 verify, atomic install, versioned manifest, repair button. |
| Local brain smoke test | Required before handoff | N/A unless Both | Run small local prompt/health check; user sees result. |
| OpenCode installed/service reachable | N/A | Required for Tier 2 use | Detect existing install; offer supported install/update; verify service/API. |
| OpenCode config/profile | N/A | Required for safe Tier 2 use | Prefer existing config; install minimal zero-trust fallback only if none; never overwrite active config. |
| Provider credentials/model config | N/A | User responsibility | Guided setup; never bundle secrets; never log credentials. |
| Permission/approval flow | Baseline visible | Required verification | Demonstrate Allow/Allow once/Reject behavior in a safe test before handoff. |
| Microphone permission/device | Optional, feature-gated | Optional, feature-gated | Prompt on first use; do not claim mic readiness until verified. |

## Componentized Packaging Model

### Thin installer (ships)

- Signed installer/bootstrapper + updater.
- Sloppy app shell: `src/`, required runtime assets/icons, minimal `.opencode` fallback, license/notice.
- Bundled pinned host runtime (preferred) or pwsh bootstrap strategy.
- Component manifest, checksums, signatures, compatibility rules.
- Component manager UI/CLI for install/verify/repair/remove.

### Downloadable components (client-side)

| Component | Default | Size class | Notes |
|---|---|---:|---|
| `llama-runtime-cpu-x64` | Auto-select fallback | small/medium | Trim to server-required files only. |
| `llama-runtime-cuda-win-x64` | Auto-select when compatible | medium | Trim to server-required files; verify CUDA/driver compatibility. |
| `llama-runtime-vulkan-win-x64` | Optional/future | medium | Consider as broader GPU fallback if validated. |
| `model-gemma4-e2b-q4` | Tier 1 default | ~3.19 GB | Resumable download, SHA256, license/terms notice, atomic install. |
| `model-gemma4-e2b-mmproj` | Optional, feature-gated | ~0.94 GB | Only when multimodal is wired, verified, and user opts in. |
| `opencode` | Tier 2/Both | varies | Detect existing first; install supported version; verify service/profile. |
| `vcpp-redist` | As needed | small | Trusted Microsoft redistributable. |

## Install/Download Behavior

- **Resumable downloads** with SHA256 verification and signed manifest.
- **Atomic install**: download to temp/staging, verify, then move into versioned component dir.
- **Versioned components**: allow rollback/repair; record installed manifest in `%LOCALAPPDATA%\Programs\Sloppy\state\components.json`.
- **No silent risky installs**: GPU drivers, provider credentials, remote provider setup are guided, not silently forced.
- **Least privilege**: per-user install default; admin only for components that require it.
- **Offline mode**: support full offline bundle or pre-seeded component cache for enterprise/airgapped installs.

## Runtime Layout (target)

```text
%LOCALAPPDATA%\Programs\Sloppy\
  app\                # Sloppy code/assets/host
  runtime\
    llama\<backend>\  # selected llama runtime
  models\
    gemma4-e2b\       # model + optional mmproj
  config\             # user config
  state\              # component manifest, install state, logs
  cache\              # downloads/temp
```

Keep OpenCode config ownership with OpenCode/user. Sloppy may read/verify and install a fallback config only when no active config exists.

## Verification / Repair / Handoff

Sloppy should not “dump” the user into the app. Readiness is a guided, user-visible gate.

### Tier 1 “Go / No-Go” checklist
- App shell/config writable.
- Runtime selected and compatible.
- Model present, verified, and loadable.
- Local health probe passes.
- Test prompt completes locally.
- UI state/motion/status indicators respond.
- User can rerun checks, repair, or continue in explicitly limited mode.

**Handoff rule:** Sloppy gets the reins only after Tier 1 Go checks pass, or the user explicitly accepts a limited mode with clear warnings.

### Tier 2 “Go / No-Go” checklist
- OpenCode installed/reachable.
- Active config/profile verified; zero-trust fallback only if no active config.
- Provider/model/agent selected.
- Test prompt round-trip completes.
- Permission card/approval decision works in a safe test.
- Active route/capability boundary clearly shown.

**Handoff rule:** Tier 2 capabilities are enabled only after Tier 2 Go checks pass. If Tier 2 fails, Sloppy falls back to Tier 1 and explains why.

### Repair behavior
- Every failed check has: plain-language cause, suggested fix, “Retry”, “Repair”, and “Learn more”.
- Component repairs are atomic and versioned.
- Sloppy never silently changes user-owned OpenCode config, credentials, or driver installs.

## Security / Trust

- Sign installer, executables, manifests, and update metadata.
- Pin download sources and verify checksums/signatures.
- No credentials in logs; preserve existing fail-closed OpenCode password behavior.
- Clear consent before mic capture, remote provider use, or large downloads.
- Publish SBOM/release manifest for runtime/model components.

## Onboarding Copy / Behavior Principles

- **Alive, not noisy:** Sloppy greets and guides, but does not overwhelm or block unnecessarily.
- **User-driven:** user initiates checks and upgrades; Sloppy recommends next steps.
- **Plain language first:** show technical details on demand.
- **Honest boundaries:** clearly state local vs remote, ready vs deferred, verified vs unverified.
- **No fake green lights:** a check passes only when executed and verified.
- **Reversible:** user can rerun checks, repair, skip optional steps, stay on Tier 1, or roll back from Tier 2 setup.
- **Teach the interface:** during onboarding, Sloppy points out status dot, route badge, approval cards, settings, and repair/manage components.

## Open Decisions

1. **Host strategy:** bundle pinned pwsh 7.6+ vs compile a small .NET/WPF launcher. Recommendation: **bundle pinned host/runtime** for least rewrite risk first.
2. **Default Tier 1 backend:** CUDA auto-detect with CPU fallback, or CPU-first for maximum compatibility. Recommendation: **auto-detect + explicit user override**.
3. **MMproj timing:** exclude until multimodal request/UI is live-verified. Recommendation: **exclude from default Tier 1 download now**.
4. **OpenCode distribution:** detect/use existing, winget/bootstrap install, or bundle portable OpenCode. Recommendation: **detect existing, offer supported install path**, don’t hide it.
5. **Offline installer SKU:** separate “full offline Tier 1” installer for advanced users.
6. **Update cadence:** app, runtime, model, and OpenCode components update independently.

## Immediate Next Implementation Steps

1. Define `component-manifest.json` schema (id, version, os/arch, size, sha256, url, dependsOn, requiresAdmin, featureFlags).
2. Build preflight checker module (PowerShell/headless testable) with structured pass/warn/fail results.
3. Build Tier 1 first-run onboarding state machine: greeting, intro, systems-check, handoff.
4. Add a “Test all systems for go” UI flow with per-check evidence and repair actions.
5. Build Tier 2 upgrade flow as a separate staged wizard: detect, install/configure, verify, capability intro, handoff.
6. Trim llama runtime to minimal server-required files per backend; keep mmproj feature-gated until verified end-to-end.

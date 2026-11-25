# Release Readiness / Desired State

- **Repo:** `public/Sloppy`
- **Owner:** `TBD`
- **Status:** `draft`
- **Last verified:** `2026-11-25` (recon only; no runtime verification)
- **Target platforms:** `TBD`
- **Distribution modes:** `source checkout | release build` (decide per repo)

## 0) Recon snapshot (auto-scaffolded)

> Groundwork only. Verify before treating as fact.

- **Path:** `E:\Projects\repos\public\Sloppy`
- **Branch:** `feat/gemma4-e2b-tier1`
- **Dirty files:** `13` (do not include accidental WIP in release snapshot)
- **Remote:** `https://github.com/shahriarhaqueabir/Sloppy.git`
- **Detected markers:** `(none detected)`
- **Workflows:** `(none detected)`
- **License files:** `LICENSE`
- **Has docs/tests/src:** `yes/yes/yes`
- **Top dirs:** `.opencode,.ruff_cache,.tours,assets,docs,runtime,src,tests,tools`
- **Package scripts (if any):** `(none)`
- **README lead:** `<p align="center"> /   <img src="assets/Sloppy.gif" alt="Sloppy demo - animated desktop companion reacting to agent state" width="400"> / </p> / # Sloppy / **A tiny desktop companion that makes your local coding agent visible - and easier to trust.** / Sloppy sits on your desktop as an animated pea. It changes colour, shape and motion with what your agent is actually doing: thinking, working, waiting on a tool, stalled, asking permission, or finishing a reply. When OpenCode asks for approval, the decision appears in the chat as **Allow / Allow once / Reject** instead of hiding in a log.`
- **Recon note:** Has existing `docs/bundling-and-first-run-plan.md` and `docs/architecture.md`. Dirty feature branch - do not include WIP in snapshot.

## 1) User promise

- **Source checkout:** `git lfs pull`; start OpenCode service; `pwsh -STA -NoProfile -File src/Slop.ps1` or `pwsh -NoProfile -File tools/slop-control.ps1 -Action Start`
- **Release build:** TBD - no installer/release artifact yet. Target: signed thin installer or release zip + first-run desired-state provisioner.
- **First-run experience:** `TBD - detect -> diff -> provision missing/drifted -> verify -> handoff`
- **Non-goals:** `TBD - what this release does not provision/support`

## 2) Desired-state manifest

| Component | Required | Version/Constraint | Source of truth | Install/Provision (idempotent) | Verify | Notes/Rollback |
|---|---:|---|---|---|---|---|
| OS/runtime | TBD | TBD | README/docs/script | Detect; install or guide; never silently destructive | command/check |  |
| Toolchain/package manager | TBD | TBD | (none detected) | idempotent install | `TBD` |  |
| App dependencies | TBD | lockfile/manifest | repo manifest | install only when missing/drifted | `TBD` |  |
| External services/CLIs | TBD | TBD | docs/scripts | preserve user config; install fallback only if empty | health check |  |
| Models/assets/binaries | TBD | hash/size/version | manifest/LFS/release asset | download/verify only missing/drifted | hash + smoke |  |
| Config/secrets | yes | no secrets committed | env/config docs | create example/default only when missing; never overwrite | secret scan |  |
| Network/ports/permissions | TBD | TBD | docs/code | document; request minimal permissions | smoke |  |

**Recon provisioning hints:** OpenCode CLI/service, bundled runtime/model presence+hash, optional CUDA/GPU, config fallback only when empty, /api/info auth, llama health, smoke chat, stop/cancel

## 3) Provision flow (XaaS-style)

**Flow:** `detect -> diff -> provision missing/drifted -> verify -> handoff`

- **Detect:** `TBD - script/check that inspects current machine/repo state`
- **Diff:** missing, wrong version, unhealthy, or drifted from desired state.
- **Provision:** only missing/drifted items; safe to rerun; user-visible actions.
- **Verify:** required checks pass before user handoff.
- **Handoff:** user-driven "Test all systems / Go" or explicit ready state.

### Verification checklist

| Check | Required | Command/Method | Pass criteria | Status |
|---|---:|---|---|---|
| Bootstrap/install | yes | `TBD` | completes cleanly on fresh env | TBD |
| App starts | yes | `TBD` | process/window/service healthy | TBD |
| Core smoke flow | yes | `TBD` | primary user flow works | TBD |
| Existing tests/build | if present | `Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path tests/Slop.Tests.ps1`; `pwsh -File tools/verify-motion.ps1` (live, requires UI); `pwsh -File tools/verify-geometry.ps1` | exit 0 / expected pass count | TBD |
| Cleanup/stop/cancel | if applicable | `TBD` | no orphan process/resource leak | TBD |

## 4) Clean snapshot / release contents

### Include (candidate)
- `README*`, `LICENSE*`, user docs, required source/runtime assets, supported install/run scripts, tests/verification scripts you support.

### Exclude (candidate)
- `docs/superpowers/**` (internal plans/specs/reports), `docs/bundling-and-first-run-plan.md` (promote or exclude), `docs/security/opencode-route-review.md` (internal review), `.tours/` optional, `.memory/`, `.ruff_cache/`, `testResults.xml`, `.git/`, LFS cache/temp
- Add repo-specific excludes after review.

### Packaging notes
- **Source checkout artifact:** `TBD`
- **Release artifact:** `TBD`
- **Integrity:** `TBD - SHA256/signature/provenance`
- **Size/bandwidth:** `TBD - call out large runtimes/models/assets`

## 5) Security / config hygiene

- [ ] No credentials/tokens/PII/personal paths in tracked release files.
- [ ] Existing user config preserved; defaults installed only when missing.
- [ ] Download URLs, hashes, and permissions explicit.
- [ ] Telemetry/network behavior documented (or explicitly none).
- [ ] Logs do not leak secrets.

## 6) Licensing / redistribution

| Component | License/Terms | Bundled/Downloaded | Redistribution OK | Action |
|---|---|---|---:|---|
| Repo code | LICENSE | n/a | TBD | verify |
| Third-party deps/runtime | TBD | TBD | TBD | inventory |
| Models/assets/fonts/binaries | TBD | TBD | TBD | verify before release |

**Recon note:** Verify Gemma 4 E2B QAT Q4_0 redistribution terms; llama.cpp MIT; LLVM OpenMP notice present; CUDA runtime redistribution terms UNVERIFIED.

## 7) Open decisions / blockers

- [ ] Confirm source-checkout vs release-build user promise.
- [ ] Define desired-state manifest and idempotent provision checks.
- [ ] Run verification commands and record evidence.
- [ ] Confirm clean snapshot include/exclude list.
- [ ] Complete licensing/redistribution review.

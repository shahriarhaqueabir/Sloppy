# Sloppy (Public) Findings & PSloppy Alignment Plan

- **Date:** 2026-11-25
- **Scope:** Focused on `E:\Projects\repos\public\Sloppy/` with alignment planning for `E:\Projects\repos\private\PSloppy/`
- **Status:** Recon/findings only. No Sloppy code changes made during this pass. No commits/pushes made.

## Executive summary

Public Sloppy is the more release-shaped repo: it has a LICENSE, LFS-tracked Tier 1 runtime/model artifacts, bundling/onboarding plan, showcase docs, and a richer Tier 1/provider/OpenCode compatibility surface. PSloppy is the private/dev counterpart: similar face+OpenCode architecture, but it currently lacks public-release packaging artifacts (no LICENSE detected by recon, no runtime/model LFS bundle, no bundling plan, fewer provider/surface modules, fewer superpowers plan/report artifacts).

The right move is **not** to merge them blindly. Treat **public Sloppy as the release/showcase candidate** and **PSloppy as private/dev lineage**. Align by extracting/shared conventions and deliberate porting, while keeping private-only material, credentials, and internal notes out of public.

## Grounded findings - public Sloppy

| Area | Finding | Evidence | Confidence |
|---|---|---|---|
| Repo state | Feature branch is dirty/diverged and has uncommitted WIP; not a clean release snapshot. | `git status --short` shows 13 modified tracked files on `feat/gemma4-e2b-tier1`; branch is ahead/behind origin/main in prior recon. | High |
| Runtime shape | PowerShell/WPF desktop app, local-first, OpenCode bridge, no installer yet. | `README.md`, `src/Slop.ps1`, `tools/slop-control.ps1` | High |
| Tier 1 bundle | Bundled llama.cpp b12676 win-cuda-13.5-x64 + Gemma 4 E2B QAT Q4_0 GGUF/mmproj tracked via Git LFS; model files ~4.04 GB total in `runtime/models`. | `.gitattributes`, `git lfs ls-files --size`, `runtime/models/*`, `README.md`, `docs/architecture.md` | High |
| Desired-state groundwork exists | Bundling/first-run plan already defines Tier 1 ready-to-go, Tier 2 deliberate opt-in, user-driven flight tests, detect/diff/provision/verify mindset. | `docs/bundling-and-first-run-plan.md` | High |
| Process control | `tools/slop-control.ps1` resolves password from env/service config, preserves active user OpenCode config and installs minimal fallback only when empty, checks `/api/info` auth, starts/stops Sloppy. | `tools/slop-control.ps1` | High |
| Docs/PR hygiene | Docs-only PR #1 is open/mergeable/clean on `docs/refresh-sloppy-20261125`; pushed after ruleset fix. MP4 demo removed and GIF kept in local feature commit `f0078ea` (local, not pushed). | `gh pr view 1 --repo shahriarhaqueabir/Sloppy ...`, local git log/status | High |
| Verification | Prior known full Pester aggregate: 543/543 before recent uncommitted Gemma/audio WIP (historical). During this session, dirty worktree Pester run returned **543/543 passed, 0 failed, 0 skipped**. Live smoke not run. | Session test run; no `tools/verify-motion.ps1` live run in this pass | High for Pester, gap for live smoke |
| Release blockers | LICENSE still `Copyright (c) 2026 shahr` (decision needed). `docs/superpowers/**` tracked despite ignore pattern; internal plans/review docs present. No installer/release artifact. History PII/sanitization decisions remain. | `LICENSE`, `git ls-files docs/superpowers`, `.gitignore`, docs contents | High |
| Snapshot risk | Dirty feature branch contains unrelated WIP and mixed concerns; clean release/snapshot must be built from an explicit manifest, not by copying the worktree blindly. | `git status`, branch divergence, WIP files | High |

## Grounded findings - PSloppy (alignment target)

| Area | Finding | Evidence | Confidence |
|---|---|---|---|
| Repo state | Private repo, dirty `main`, ahead/behind origin/main; has untracked `security-scan-results.json` (risky, do not package/commit). | `git status --short`, `git branch -vv`, file listing | High |
| Identity | Similar Sloppy face/bridge app, but README/branding still PSloppy-oriented and less release-polished for public consumption. | `README.md` | High |
| License/release metadata | No LICENSE file detected by recon. No LFS runtime/model bundle, no `.gitattributes` for GGUF/runtime, no `docs/bundling-and-first-run-plan.md`, no `docs/SHOWCASE.md`. | recon, file checks | High |
| Feature delta vs public | Public has extra modules absent in PSloppy: `Slop.Adapter.OpenAi.ps1`, `Slop.Adapter.OpenCode.ps1`, `Slop.Disclosure.ps1`, `Slop.LocalModel.ps1`, `Slop.Onboarding.ps1`, `Slop.OpenCodeCompat.ps1`, `Slop.OpenCodeProfile.ps1`, `Slop.Provider.ps1`, `Slop.Route.ps1`, `Slop.Surfaces.ps1` and matching tests; plus bundling/showcase/product-v1 docs. | file diff by path | High |
| Private/dev artifacts | PSloppy contains `.memory/*`, `.opencode/opencode.jsonc.muted`, `.worktrees/`, `private/`, `notesfront*`, untracked security scan artifact - all inappropriate for public snapshot. | file listing, `.gitignore` | High |
| Control script parity | Both have `tools/slop-control.ps1` and `tests/slop-control-check.ps1`, but implementations differ (public has richer fallback-config/auth/sync behavior; PSloppy older/simpler). Needs deliberate diff before porting. | `Select-String`/file presence | Medium-High |
| Docs/superpowers | PSloppy tracks fewer superpowers docs (18) than public (25) and lacks public product-v1/showcase/bundling artifacts. Both repos currently have `docs/superpowers/**` ignored in `.gitignore` while also tracked in git - policy decision required. | `git ls-files docs/superpowers`, `.gitignore` | High |

## Public Sloppy vs PSloppy - alignment matrix

| Topic | Public Sloppy | PSloppy | Recommendation |
|---|---|---|---|
| Release role | Public showcase/release candidate | Private/dev lineage | Keep roles explicit; do not treat PSloppy as release source of truth. |
| License | Present but needs attribution decision (`shahr` vs `shahriar`) | Missing | Decide public identity; add LICENSE to PSloppy only if/when intended for release. |
| Tier 1 bundle | Runtime/models via LFS, bundling plan | No bundled runtime/model LFS evidence | Port only deliberate, licensed, size-aware packaging strategy. |
| Provider/model surface | Has local model/provider/route/adapters/disclosure/onboarding/surfaces | Missing these modules | Port by capability slices with tests; avoid blind copy. |
| OpenCode config policy | Preserve active user config; minimal fallback only when empty | Similar intent but implementation older | Align on public Sloppy behavior after diffing tests/contracts. |
| Docs for release | README, SHOWCASE, architecture, bundling plan, verification report | README/architecture/decisions; no bundling/showcase | Promote selected docs into shared template; keep internal docs out of user snapshot. |
| Internal/sensitive artifacts | `docs/superpowers/**` tracked; some internal review docs | `.memory`, `.worktrees`, `private`, security-scan-results.json, notesfront | Define strict snapshot exclude manifest per repo. |
| Verification | 543/543 Pester in dirty worktree; live smoke pending | Pester exists but not run in this pass | Before any port, run equivalent verification in target repo and record evidence. |

## Recommended alignment plan (PSloppy <-> public Sloppy)

### A. Define the contract (before code porting)

1. **Declare source of truth per concern**:
   - Public release/docs/packaging: `public/Sloppy`
   - Private experiments/sensitive local workflows: `private/PSloppy` (or private branches/worktrees)
   - Shared behavior contracts: tests + small, explicit docs/manifests
2. **Create a capability matrix** (module-by-module): `same`, `public-only`, `private-only`, `diverged`, `port-candidate`, `do-not-port`.
3. **Decide identity/public naming**: Sloppy vs PSloppy branding, LICENSE author, repo description, and what "official" means.

### B. Build a clean release boundary

1. **Source checkout manifest**: files needed to run from git clone (`src`, `tools`, required docs, `.opencode` fallback config if safe, LFS pointers).
2. **Release artifact manifest**: user download/build + first-run provisioner; may exclude dev docs/tests/tours or package them separately.
3. **Never-package list** for both repos: `.git/`, `.memory/`, `.superpowers/`, `private/`, secrets/env, `security-scan-results.json`, personal notes, worktrees, caches, build junk, internal superpowers plans/specs/reports unless intentionally published.
4. **Public docs allowlist** for Sloppy: `README.md`, `LICENSE`, `docs/SHOWCASE.md`, `docs/architecture.md` (sanitized), selected user-facing setup/troubleshooting; treat `docs/superpowers/**` as internal unless explicitly curated.

### C. Port in slices, not wholesale

Port order suggestion (each slice = diff + tests + verify + doc):

1. **Control/config safety** - `slop-control.ps1`, OpenCode config fallback, auth precheck, no-overwrite-user-config rule.
2. **Provider/route/compat** - `Slop.Route`, `Slop.Provider`, adapters, OpenCode compat/profile, with contract tests.
3. **Local model/Tier 1** - runtime/model manifest, hash verification, first-run preflight; only after licensing/redistribution decision.
4. **Disclosure/onboarding/surfaces** - user-facing UX flow; verify no private/personal defaults.
5. **Docs/packaging** - bundling plan promoted to release-readiness/installer spec; exclude internal planning docs from release snapshot.

### D. Verification gates per port

- Run Pester aggregate in target repo (record exact pass/fail counts).
- Run repo-specific smoke checks (headless first; live UI only when needed and available).
- Run secret/PII scan on candidate snapshot (not just git diff).
- Confirm no user-config overwrite, no silent destructive actions, no orphan processes.

## Public Sloppy - recommended next work (paused, planning only)

> You asked to pause Sloppy work; items below are queued, not executed.

1. **Merge PR #1** after review, then sync `feat/gemma4-e2b-tier1` with updated `origin/main` and reconcile README/tour/superpowers conflicts carefully.
2. **Split dirty work** into explicit-path commits: Gemma/audio/tour, Face/OpenCode WIP, `.gitignore`, bundling/release docs, docs-only cleanup. No mixed commit.
3. **Re-run verification** on clean split state: Pester aggregate, `tools/verify-geometry.ps1`, and live `tools/verify-motion.ps1` only when claiming UI behavior.
4. **Release decisions**: LICENSE attribution, `docs/superpowers/**` publish policy, LFS/release artifact strategy, model/runtime redistribution terms, history-sanitization acceptance.
5. **Build clean snapshot manifest**: source snapshot vs user release; generate from allowlist, never from raw worktree copy.

## "Rest of work as recommended" - non-Sloppy repos (safe status/actions)

I did **not** merge PRs automatically because merges are remote-visible actions and several are `UNSTABLE`/have repo policy implications. Current PR status:

| Repo | PR | State | Mergeable | Merge state | Recommendation |
|---|---:|---|---|---|---|
| APIsimulator | #1 | OPEN | MERGEABLE | CLEAN | Safe to merge after quick review |
| APLTE | #1 | OPEN | MERGEABLE | UNSTABLE | Review checks first; merge if docs-only and checks acceptable |
| JournalFriends | #3 | OPEN | MERGEABLE | UNSTABLE | Review checks first (Dependabot/security signal appeared earlier) |
| Klarecht | #47 | OPEN | MERGEABLE | UNSTABLE | Review checks first |
| PSloppy | #1 | OPEN | MERGEABLE | CLEAN | Paused per "pause Sloppy" (PSloppy alignment-related) - merge only when you explicitly include it |
| Sloppy | #1 | OPEN | MERGEABLE | CLEAN | Paused - merge during Sloppy sync/split pass |

## Deliverables created in this pass

- `E:\Projects\repos\RELEASE-READINESS-INDEX.md` - workspace index of recon scaffolds.
- `docs/release-readiness.md` created in every repo under `E:\Projects\repos\public` and `E:\Projects\repos\private` (11 repos) as untracked drafts.
- This document: `E:\Projects\repos\public\Sloppy\docs\sloppy-public-psloppy-alignment.md`.

## Caveats

- Recon is filesystem/git/README/CLI metadata based; no deep runtime audit of every repo.
- Pester 543/543 was run on the current dirty public Sloppy worktree earlier in session; it is evidence, not a clean-release gate.
- No history rewrite, no force push, no merge, no code edits to Sloppy/PSloppy app code.
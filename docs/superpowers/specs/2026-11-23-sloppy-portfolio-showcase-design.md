# Sloppy — Portfolio Showcase Design

**Date:** 2026-11-23
**Status:** Approved for spec review (design approved by user 2026-11-23)
**Branch:** `main` at `ffee52f` or later
**Scope:** documentation, packaging, and public release only — no runtime behavior changes

## Objective

Turn the existing Sloppy codebase into a public portfolio artifact that an AI/agent
engineering hiring manager or technical peer can understand in 60 seconds. The
showcase must make the agent-systems engineering legible, not merely display an
animated companion.

Success is measured by clarity and evidence, not downloads or revenue.

## Locked decisions

These came from the brainstorming session and constrain this design:

| Decision | Choice |
| --- | --- |
| Six-month goal | Career / portfolio showcase |
| Target audience | AI / agent engineering |
| Scope | Publish what exists first; no new product features |
| Repository visibility | Public |
| Monetization | None in this phase; deferred to roadmap |
| New runtime features | None — installer, remote bridge, and provider adapters are explicitly out of scope |

## Non-goals

- No MSI, WiX installer, one-line bootstrap, or auto-update.
- No Telegram/Discord/Messenger bridge or any relay service.
- No Claude Code, cloud API, or local-LLM adapter.
- No settings/control panel implementation (the existing spec stays a spec).
- No changes to `src/`, `tests/`, or any verification script except the new capture helper described below.
- No deployment, push to a remote, or CI/CD configuration until the user confirms the target repository.

## Positioning

Front-page claim:

> A desktop companion that makes an agent's state, permissions, and decisions visible.

The companion is the hook. The engineering is the thesis. In every showcase artifact,
lead with these four capabilities:

1. **Signal state machine** — priority, sticky vs transient events, "lower number wins,
   newest breaks ties." This is decision visibility, not decoration.
2. **Approval flow** — in-chat allow/reject, generation guards, tag-carried event data,
   and no closure over PowerShell function locals.
3. **Broker boundary** — OpenCode is the single intelligence broker; per-provider
   security profiles and human-in-the-loop writes are already specified.
4. **Cancellation and event normalization** — token-aware SSE reads, terminal-event
   handling, no orphaned streams.

Deliberately de-emphasized in the narrative: spring constants, particle geometry,
shortcut chips, palette details. They remain in the code and tour as supporting depth.

## Design

### 1. Public repository hygiene

The repository currently has **no git remote**. Publish to a user-confirmed GitHub
repository only after the following scrub.

- Add `LICENSE` (MIT recommended; confirm with user before writing).
- Update `.gitignore`:
  - add `/testResults.xml`;
  - replace `/assets/` with `/assets/*` plus negations for `!/assets/demo.gif` and
    `!/assets/hero.png`, so the user's existing `assets/sloppy.png` and
    `assets/sloppy.ico` remain ignored and untouched.
- Resolve the untracked, read-only `docs/visual-signal-system.md`: either refresh it
  against merged source and commit, or leave it untracked and exclude it from the
  showcase. Do not silently delete user-owned files.
- Scan tracked text for credentials, personal absolute paths, and session-specific
  identifiers before pushing. A preliminary scan of `.opencode/opencode.jsonc` found
  no password/token/secret/key fields; re-run the scan after all edits.
- `notesfront.md`, `notesfront2.md`, and `src/Slop.md` are already ignored personal
  scratch notes — keep them ignored.

### 2. Hero demo artifact

Create `assets/demo.gif`: a 12–15 second silent loop that shows the complete signal
story in this order:

1. idle pea, blue;
2. expand to chat frame;
3. Send → amber "thinking" signal and working particles;
4. streamed reply;
5. green success signal;
6. drag the pea;
7. collapse back to idle.

Create `assets/hero.png` from a single representative frame (expanded frame, amber or
green signal) for the GitHub social preview.

Capture approach:

- Add `tools/capture-demo.ps1`, a thin wrapper that launches the app exactly as
  `tools/verify-motion.ps1` does and grabs screen-region frames with
  `System.Drawing.CopyFromScreen` at ~15 fps into a temp directory.
- It must use a `finally` block to terminate the app and any child wrapper process.
  An orphaned topmost app holds inherited stdout and hangs piped callers.
- Encode frames to GIF and MP4. Neither `ffmpeg` nor ImageMagick is installed on this
  machine. The chosen path is a **portable ffmpeg binary fetched into the approved
  temp directory on demand** (not a system-level install); this requires explicit user
  confirmation before any download.
- Fallback if no download is permitted: commit a four-panel still strip
  (`assets/demo-frames.png`: idle / thinking / success / expanded) generated from the
  same captured frames, and leave the motion video to be recorded manually by the
  user with Game Bar or OBS. The README leads with whichever artifact exists.

The capture helper is verification tooling, not runtime code, and is the only new
script in this design.

### 3. README rewrite

Replace the current developer-note README with a front page in this order:

1. `assets/demo.gif` at the top (or the fallback still strip).
2. The one-line positioning claim.
3. "What this is / what it isn't" — a WPF frontend to a local OpenCode service over
   loopback HTTP + SSE, not a model and not a standalone chatbot.
4. "Why it exists" — three bullets on agent decision visibility, safety boundary, and
   cancellation correctness.
5. Quick start with the honest current command:
   `pwsh -STA -File src/Slop.ps1`, plus the PowerShell 7.6 / STA / local OpenCode
   requirements. Do not imply a one-line installer exists.
6. Architecture map: links to `docs/architecture.md`, the 18-step CodeTour, and the
   provider-security and settings specs.
7. Proof: 441 passing Pester tests, the live verifier, the geometry verifier, and the
   tour anchor guard, with the exact commands to run them.
8. A compact signal table (kind / color / priority / lifetime) so a reader can see the
   state model at a glance.
9. Roadmap — one line each for the one-line installer, MSI, remote bridge, and
   multi-provider adapters, clearly marked as not yet built.
10. License.

### 4. SHOWCASE.md

Add `docs/SHOWCASE.md`: a single-page narrative intended to be sent directly to a
human reviewer. Structure:

- **Problem** — coding agents are opaque; state, permissions, and decisions are
  invisible unless you read logs.
- **Approach** — make the agent's state a first-class resolved signal and render it.
- **Three hard problems** — (a) live SSE cancellation, (b) permission boundary and
  in-chat approvals, (c) event normalization across provider terminal events. Each
  with the concrete file and the failure mode it prevents.
- **Evidence** — links to the tour, tests, verifiers, and performance baseline.
- **Diagram** — a small Mermaid flow: `event → resolved signal → visual property`.

Keep it under one printed page. No marketing adjectives that cannot be backed by a
link to code or a test.

### 5. Data and artifact flow

```
live verifier drives app
        ↓
capture-demo.ps1 grabs frames (temp)
        ↓
portable ffmpeg  →  assets/demo.gif + assets/demo.mp4
                 →  assets/hero.png (single frame)
        ↓
README + SHOWCASE.md reference the artifacts
        ↓
scrub → local commit → user-confirmed remote → push
```

### 6. Error handling and risks

- **Downloading ffmpeg** touches the network and adds a binary to temp. Explicit
  confirmation required; no system-wide install, no PATH changes.
- **Orphaned app process** from capture: `finally` teardown plus a post-run orphan
  check, matching the existing live verifier lessons.
- **Publishing private material**: scrub before push, never after. If the scan finds
  anything ambiguous, stop and ask rather than redacting blindly.
- **Stale docs**: `docs/visual-signal-system.md` is untracked and may drift. Resolve
  explicitly; do not let a stale file become the first thing a reviewer finds.
- **Assets ignored by `.gitignore`**: verify with `git check-ignore -v` after editing
  that the demo artifacts are trackable and the user's icons are still ignored.

## Verification plan

Before this work is called complete:

1. `pwsh -NoProfile -File <agent-home>/scripts/verify.ps1` — all gates pass.
2. Tour check — 38/38, all 16 source anchors matching.
3. Confirm `assets/demo.gif` (or fallback strip) and `assets/hero.png` exist and are
   non-empty, and that `git check-ignore` reports them as trackable.
4. Re-run the credential/path scrub after all edits.
5. `git status --short` — report verbatim; confirm no runtime source changed.
6. `git diff --stat` — confirm only documentation, packaging, and the capture helper.

No push, PR, deploy, or CI/CD change is part of this work.

## Open questions

- Target GitHub repository name/URL for the remote.
- Confirm MIT license.
- Confirm permission to fetch a portable ffmpeg binary into temp.
- Decide whether `docs/visual-signal-system.md` is refreshed or left out.
- Confirm whether to commit `demo.mp4` in addition to the GIF (larger file, better X posts).

## Transition

After this spec is reviewed and approved, the next step is the `writing-plans` skill to
produce a step-by-step implementation plan. No implementation begins before that plan
is approved.


# Sloppy Portfolio Showcase Implementation Plan

> **For agentic workers:** Execute with `executing-plans`. No subagents (user cost constraint). No commits — user owns all commits.

**Goal:** Prepare the public portfolio showcase artifacts locally: README, SHOWCASE narrative, license, ignore rules, and a demo capture helper.

**Architecture:** Documentation and packaging only. Runtime source (`src/`) and existing verification scripts are untouched. The only new script is a capture helper under `tools/`. Nothing is pushed, and no remote is configured.

**Tech Stack:** Markdown, PowerShell 7.6, System.Drawing for still frames, optional portable ffmpeg (requires separate confirmation).

**Source spec:** `docs/superpowers/specs/2026-11-23-sloppy-portfolio-showcase-design.md`

---

## File structure

| File | Responsibility |
| --- | --- |
| `README.md` | Public front page: demo, positioning, quick start, architecture, proof, roadmap |
| `docs/SHOWCASE.md` | One-page reviewer narrative with hard-problem evidence |
| `LICENSE` | MIT license text |
| `.gitignore` | Ignore test artifacts; allow only demo assets out of `assets/` |
| `tools/capture-demo.ps1` | Capture real app frames and assemble the still-strip fallback |

Unchanged and deliberately untouched: `docs/visual-signal-system.md` (user-owned untracked), `testResults.xml`, `assets/sloppy.png`, `assets/sloppy.ico`, all of `src/` and `tests/`.

---

### Task 1: Repo hygiene files

**Files:**
- Modify: `.gitignore`
- Create: `LICENSE`

- [ ] **Step 1: Update `.gitignore`**

Replace the final two lines:

```
# User-owned visual assets (tracked outside this repo)
/assets/
```

with:

```
# Test artifacts
/testResults.xml

# User-owned visual assets: ignore by default, allow only showcase artifacts
/assets/*
!/assets/demo.gif
!/assets/demo.mp4
!/assets/demo-frames.png
!/assets/hero.png
```

- [ ] **Step 2: Verify ignore behavior**

Run:
```powershell
git check-ignore -v assets/sloppy.png assets/sloppy.ico testResults.xml
git check-ignore -v assets/demo-frames.png assets/hero.png
```
Expected: first command reports the user's icons and `testResults.xml` as ignored; second command reports nothing (showcase assets are trackable).

- [ ] **Step 3: Add MIT `LICENSE`**

Write the standard MIT text with copyright line:
```
Copyright (c) 2026 shahr
```

- [ ] **Step 4: Confirm no runtime files changed**

Run `git status --short`. Expected: only the files named in this plan appear as new/modified.

---

### Task 2: Demo capture helper and still strip

**Files:**
- Create: `tools/capture-demo.ps1`
- Create (generated): `assets/demo-frames.png`, `assets/hero.png`

- [ ] **Step 1: Write `tools/capture-demo.ps1`**

Contract:
- Load `UIAutomationClient`, `UIAutomationTypes`, `System.Drawing`, `System.Windows.Forms`.
- Reuse the proven launch/teardown shape from `tools/verify-motion.ps1`: launch the app with `pwsh -STA -File src/Slop.ps1`, capture DPI once at the initial 484x330 rect, and terminate the app plus child wrapper in a `finally` block.
- Grab frames with `[System.Drawing.Graphics]::CopyFromScreen` from the window's UIA bounding rectangle.
- Capture four beats: idle compact, expanded chat, thinking (amber dot observed), success (green dot observed).
- Assemble the four bitmaps into a 2x2 PNG at `assets/demo-frames.png` with a small caption strip beneath each panel, using `System.Drawing` only.
- Copy the expanded frame to `assets/hero.png`.
- Never overwrite an existing user asset; fail with a clear message if `assets/sloppy.png` or `assets/sloppy.ico` would be touched.
- Do not download or install anything.

- [ ] **Step 2: Run the capture helper**

Run: `pwsh -NoProfile -File tools/capture-demo.ps1`

Expected: exit 0, both PNGs exist and are non-empty, no orphan app process (check with `Get-Process pwsh`).

- [ ] **Step 3: If capture cannot run in this environment**

Do not invent a fake demo. Leave `assets/demo-frames.png` absent, note the blocker verbatim in the final report, and have the README reference `assets/sloppy.png` only if it is made trackable — otherwise omit the hero image entirely and keep the text front page.

---

### Task 3: README front page

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace README content**

Required order and content:

1. If `assets/demo.gif` or `assets/demo-frames.png` exists, embed it at the top with `![Sloppy in action](assets/demo-frames.png)`. Otherwise start with the heading.
2. `# S.L.O.P. — Screen-aware Local OpenCode Pal`
3. One-line claim: *A desktop companion that makes an agent's state, permissions, and decisions visible.*
4. **What this is** — WPF/PowerShell 7.6 desktop frontend; talks to a local OpenCode service over loopback HTTP + SSE; owns UI, motion, and the permission surface. **What it isn't** — a model, a standalone chatbot, or a cloud service.
5. **Why** — three bullets: decision visibility via a resolved signal state machine; a human-in-the-loop permission boundary; cancellation that actually reaches the SSE reader.
6. **Quick start** — exact current command `pwsh -STA -File src/Slop.ps1`, with PowerShell 7.6 STA and a running local OpenCode service as prerequisites. Explicitly state there is no installer yet.
7. **How it works** — links to `docs/architecture.md`, `.tours/architect-slop-architecture.tour`, `docs/superpowers/specs/2026-11-23-sloppy-provider-security-architecture.md`, and `docs/superpowers/specs/2026-11-23-sloppy-settings-control-panel.md`.
8. **Proof** — 441 passing Pester tests; commands for the full aggregate and `tools/verify-motion.ps1`.
9. **Signal model** — compact table: approval (thinking, 0, sticky), critical (error, 1, sticky), stalled (thinking, 2, sticky), warning (thinking, 3, 6s), thinking/working/tool (4), success (success, 1, 1.5s), error (error, 1, 2s), cancelled (idle, 6, 1.5s), idle/chat-open (7). Note: lower number wins; newest breaks ties.
10. **Roadmap** — one-line each: one-line installer, MSI, Telegram bridge, multi-provider adapters. Mark all as not built.
11. **License** — MIT.

- [ ] **Step 2: Check claims against source**

Run `git diff -- README.md` and verify every command and count in the README matches the repository. No aspirational language about unbuilt features.

---

### Task 4: Showcase narrative

**Files:**
- Create: `docs/SHOWCASE.md`

- [ ] **Step 1: Write the one-page narrative**

Required structure:
- **Problem** — coding agents hide state, permissions, and decisions in logs.
- **Approach** — resolve every event into one signal; render that signal as color, shape, particles, and pulse.
- **Three hard problems** — (a) live SSE cancellation reaching the reader via `ReadLineAsync(CancellationToken)`; (b) approval boundary with generation guards and tag-carried event data in `src/Slop.ps1`; (c) terminal-event normalization in `src/Slop.OpenCode.ps1` / `Slop.ps1`. Each names the concrete failure mode it prevents.
- **Evidence** — links to the CodeTour, Pester aggregate, live verifier, geometry verifier, and `docs/performance/baseline-2026-11-23.md`.
- **Diagram** — Mermaid flow: `event -> Set-SlopSignalEvent -> Get-SlopSignal -> Set-SlopVisualFromSignal -> brush/face/pulse`.
- Keep under one printed page; no unbacked adjectives.

- [ ] **Step 2: Validate links**

Check every relative path named in `docs/SHOWCASE.md` exists with `Test-Path`.

---

### Task 5: Local verification report

- [ ] **Step 1:** Run the verify ritual and record the output.
- [ ] **Step 2:** Run the tour check and confirm 38/38.
- [ ] **Step 3:** Run the credential/path scrub again and report the result.
- [ ] **Step 4:** Run `git status --short` and `git diff --stat`; report verbatim.
- [ ] **Step 5:** Confirm no commit was made: `git log --oneline -1` must still be `553b15b` (or whatever the user has made it by then).

---

## Self-review

- Every spec section maps to a task: hygiene → Task 1, demo → Task 2, README → Task 3, SHOWCASE → Task 4, verification → Task 5.
- No placeholders: all file paths and required content are explicit.
- Names are consistent: `demo-frames.png` and `hero.png` in Task 2 match Task 3 references and `.gitignore` exceptions.
- The only external dependency (portable ffmpeg) is excluded from this plan; the still-strip fallback is the local path.

# Slop Frame Budget — Design

Status: approved 2026-11-23. Scope: render cadence, per-tick allocations, collapsed-state work, and maximized window geometry. No changes to the OpenCode bridge, permissions, lifecycle, or product visual language.

## Goal

Reduce idle CPU use without changing the signal table, control dots, shortcut chips, System Sense semantics, or the organic membrane identity. The measured cost is WPF re-rendering driven by the 33 ms motion tick, not PowerShell math: per-tick compute is 0.31–0.55 ms while the live process uses 12–49% of one core at rest.

## Evidence

See `docs/performance/baseline-2026-11-23.md`. Headless per-tick cost and live CPU samples were captured before any edit. Live sampling is noisy (+-8 points), so the post-change harness reports medians of multiple samples.

## Decisions

- Stay on WPF. WinUI 3 composition animations and a C# geometry renderer are out of scope.
- Keep the layered transparent window. The large state becomes work-area-sized, not opaque.
- Keep all assertion counts and existing test filenames; add new suites to the Pester aggregator.

## 1. Adaptive cadence

Two pure functions in `src/Slop.Motion.ps1` (headless-testable):

- `Test-SlopMotionActive -State $m [-WindowMoving]`: true when the signal stream is active, a transient signal hold is pending, mood is not `idle`, the hop phase is not `idle`, the Open spring is in transit, any shape weight is in transit, or the window moved since the last tick.
  - Deliberately excludes `Puff` and `Lean` spring error: their targets oscillate at idle, so spring error would report active forever.
  - Deliberately excludes `ChatOpen`: expanded-but-idle must still drop rate.
- `Get-SlopMotionIntervalMs -State $m [-WindowMoving] [-Large]`: calls `Test-SlopMotionActive`, then returns `33` when active, `100` when idle and large, `66` otherwise.

The tick handler in `src/Slop.ps1` computes the window-position delta, calls `Get-SlopMotionIntervalMs`, and assigns `DispatcherTimer.Interval` only when the target changes. Physics remains at fixed 1/120 s substeps; the accumulator already tolerates variable `dt` (clamped at 0.25 s).

## 2. Reuse transforms

`Initialize-MotionVisuals` caches the transforms already created for `PeaCanvas` and `GroundShadow` as `$script:PeaTranslate` and `$script:ShadowScaleTransform`. Names must not collide with any XAML `x:Name`. `Apply-SlopMotion` updates `X`, `Y`, `ScaleX`, `ScaleY` in place; the per-tick `[TranslateTransform]::new()` and `[ScaleTransform]::new()` calls are removed. `Get-ShapeTransform` already reuses its children and stays unchanged.

## 3. Skip invisible work

In `Apply-SlopMotion`, gate the membrane `Update()` call and both `Geometry.Parse` calls on `SlopFrame.IsClosed`. When closed, `BodyPath`/`HeadHighlight` stay collapsed, `Frame` stays collapsed, and `PeaCanvas` stays visible. Existing `RestoreCompact`, mood selection, and `Move()` behavior stay in place. `Expand()` sets `openT = 1`, which immediately clears `IsClosed`, so no extra state is needed to resume.

## 4. Work-area large state

`SettingsDot` currently toggles `WindowState` between `Normal` and `Maximized`. It will instead:

- store the current Left/Top/Width/Height,
- size the window to `SystemParameters.WorkArea` (DIPs, never covers the taskbar),
- set `$script:PseudoMaximized = $true`,
- restore the stored rect and clear the flag on the second click.

The `WindowState -ne 'Maximized'` guards in `Expand-Chat` and `Collapse-Chat` become `-and -not $script:PseudoMaximized` so expand/collapse cannot resize a large window. Tray hide/show preserves the large geometry and flag. Transparency, `Topmost`, face layer sizing, and clip rebuild are unchanged.

The timer passes `-Large:$script:PseudoMaximized`, giving large idle a 100 ms tick.

## 5. Measurement harness

Add `tools/profile-slop.ps1`:

- headless per-tick micro-benchmark (warmup, N iterations, four scenarios),
- live CPU sampling via `Process.TotalProcessorTime` with a warmup sample and three measured samples per mode (compact idle, expanded idle, work-area-large idle), reporting the median percentage of one core,
- reuse of `~/.config/opencode/service.json` for `OPENCODE_PASSWORD`,
- unconditional teardown in `finally` (the app is topmost and an orphan holds inherited stdout),
- optional JSON output so before/after runs are comparable.

`docs/performance/baseline-2026-11-23.md` holds the pre-change numbers. Rerun the same harness after the change and record deltas in the implementation commit.

## 6. Tests

- New `tests/slop-motion-cadence-check.ps1`, registered in `tests/Slop.Tests.ps1`: idle closed/open/large, active streaming, Open spring in transit, weight in transit, non-idle phase, transient hold, window moving, and the key regression that idle breathing targets do not force 33 ms.
- `tests/slop-shell-check.ps1` source invariants: no per-tick transform allocation in `Apply-SlopMotion`, `IsClosed` guard present, cadence helper used by the timer, no `WindowState = 'Maximized'` toggle.
- Full `verify.ps1` gate and `tools/verify-motion.ps1` live pass, including maximize/restore and the existing work-area assertion.

## Risks

- `SystemParameters.WorkArea` is in DIPs while UIA bounding rectangles are physical pixels. At 125% scaling this should still satisfy the verifier's `Screen.PrimaryScreen.WorkingArea` comparison, but it must be checked live.
- Changing a running `DispatcherTimer.Interval` resets its countdown; the 0.25 s `dt` clamp prevents a physics spike.
- Time-based face drift keeps its speed at lower rates but moves in larger steps. The 15 fps idle / 10 fps large tradeoff was explicitly accepted.
- Pseudo-maximize changes `WindowState` semantics; all three existing `Maximized` references were located and are covered above.

## Out of scope

- WinUI 3 / compositor animations.
- Opaque work-area window.
- C# geometry renderer or compiled assembly caching.
- `@opencode/sdk` migration.
- Changing signal colors, shapes, control dots, shortcut chips, or System Sense opt-in/off/read-only/local-only/cached/never-acts behavior.

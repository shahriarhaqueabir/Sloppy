# Slop Signal and Particle Integrity — Design

Status: approved 2026-11-23; revised 2026-11-23 after the concurrent event-system rewrite landed in the working tree. Scope: the eight reported defects, of which two (stalled amber, approval persistence) are already fixed in source and need only regression coverage, plus two approved visual improvements (state-tinted frame highlight and a golden-angle spiral pattern). No changes to the OpenCode bridge, permission protocol, request lifecycle, System Sense, frame-budget cadence, or the canonical signal palette.

## Goal

Make what Sloppy *shows* match what its state says. The event-driven signal model now in the working tree fixes the stalled and approval defects; the remaining gaps are that the face maps only colour/shape instead of the effective signal's kind, particles live in a full-window topmost canvas instead of the body, reduced motion still drifts, OpenPulse is stepped but never rendered, and wander is unbounded. Fix the wiring, not the visual language.

## Evidence

All eight findings were traced to source before any edit:

| # | Defect | Current root cause / state |
|---|---|---|
| 1 | Particles cover the whole window | `src/Slop.ps1:1139-1143` sizes the face layer to the window and adds it last to `Stage`; `src/Slop.Face.ps1:50-52,86-89` maps positions across `Width-48`/`Height-48`. |
| 2 | Stalled stayed green | Already fixed in the working tree: `Get-SlopSignal` resolves the stalled base to `thinking`/`rect` at priority 2. `tests/slop-motion-check.ps1` now asserts amber. Only regression coverage remains. |
| 3 | Approval amber was overwritten | Already fixed in the working tree: `Add-SlopApprovalCard` and the event switch use a sticky `permission:$Generation:$RequestId` event (priority 0), cleared by id on Allow/Reject and by `Reject-SlopPendingApprovals`. Only regression coverage remains. |
| 4 | Transient states do not fully drive particles | The face tick at `src/Slop.ps1:1213-1219` maps only colour/shape, missing the effective `Kind` (success speed, thinking-kind spiral). The cache is refreshed each tick by `Update-SlopMotionState` → `Update-SlopSignal` → `Get-SlopSignal`, so this is a mapping gap, not staleness. |
| 5 | Reduced motion still moves | Springs snap in `Update-SlopMotionState`, but `src/Slop.ps1:433` still writes a sine into `PeaTranslate.X` and line 1216 defaults face speed to 0.3. |
| 6 | OpenPulse is dead | Targeted and stepped in `src/Slop.Motion.ps1`; no renderer reads it. |
| 7 | Particles escape their region | `Update-SlopFaceLayer` adds drift without clamping and the canvas has no `Clip`. |
| 8 | Idle wander has no screen bound | The wander branch at `src/Slop.ps1:1184-1187` writes `window.Left` unbounded. |

Correction to the initial report: `BodyPath.Stroke` **is** already in `$script:ColorBrushes` and animates through `Animate-BrushTo`; `docs/visual-signal-system.md` independently verifies this. The genuinely static piece is `HeadHighlight.Stroke`; both its XAML initial value and its animation are addressed in section 6.

Rebase note (2026-11-23, during execution): the working tree moved after this spec was committed. The current baseline is **362 passed / 7 failed** — the seven stale tour anchors only. A concurrent source edit fixed the stale success expectation and applied the production hardening from section 1 (deterministic legacy id, derived-field refresh, sticky-event cadence). That contract is now: approval 0 sticky, critical 1 sticky, success 1 transient 1.5 s, error 1 transient 2 s, stalled base 2, warning 3 transient 6 s, working/tool/thinking 4, cancelled 6, idle/chat-open 7. The earlier success-5 / sticky-error description is obsolete; section 1 below is now regression-coverage only.

## Signal foundation (do not rewrite)

The event model is the foundation; do not reintroduce two-field overlays or move call sites back to `Set-SlopSignal`.

- `Set-SlopBaseCondition` sets `Streaming`, `ChatOpen`, `Stalled`, and `BaseState` only. It never clears events.
- `Get-SlopSignal` builds a base candidate (`idle`/`circle` or `chat-open`/`square` at priority 7, `working`/`triangle` at 4, `stalled` → `thinking`/`rect` at 2), then picks the lowest-priority live event, newest wins ties. It returns `Id`, `Kind`, `Color`, `Shape`, `Priority`, `Status`, `Source` and refreshes `HoldRemaining`, `State`, `Status`, `Source`, `Priority` on `$State.Signal`.
- `Set-SlopSignalEvent` defines the rebased priority classes: approval 0 (sticky), critical 1 (sticky), success 1 (transient 1.5 s), error 1 (transient 2 s), stalled base 2, warning 3 (transient 6 s), thinking/working/tool 4, cancelled 6, idle/chat-open 7. `docs/visual-signal-system.md` is a read-only design reference; where it disagrees, the source is authoritative.
- `Clear-SlopSignal`, `Clear-SlopSignalEvent -Id`, and `Clear-SlopSignalEvents -Prefix` are the three explicit lifetime controls.
- `Sync-SlopSignal` compares `AppliedColor`, `AppliedShape`, `AppliedState`, and `AppliedStatus`, so status-only changes render too. Keep this.
- All app call sites already use `Set-SlopSignalEvent` with explicit ids (`request:`, `permission:`, `sense:`). `Set-SlopSignal` is now a test-only compatibility adapter.

## Decisions

- Approach A: repair in place. No new visual module, no C# geometry or membrane-physics changes.
- Treat the event-driven signal wiring as already owned and already hardened in the working tree; add regression coverage instead of rewriting it.
- `Get-SlopSignal` is the single effective-signal authority for mood, colour, pattern, and face behavior.
- Reduced motion means zero pea translation and zero particle drift — visible state stays static, colour/shape/status remain.
- OpenPulse is rendered on the existing body outline; the membrane stays untouched.
- Keep the 12-particle count and existing pattern names; `spiral` is additive.
- Keep the existing 2-second error and 1.5-second success durations. Cyan/teal active tokens and sticky critical alerts in `docs/visual-signal-system.md` are future work, not part of this slice.
- Preserve the user's uncommitted source edits and all untracked docs. The tour file currently matches an older working-tree snapshot; source edits will stale its anchors again, so refresh them in the same pass and leave the refresh uncommitted with the source edits.

## 1. Correct the stale test and cover the event model

No production edit remains in this section. The concurrent source edit already gave the legacy `Set-SlopSignal` adapter the deterministic `legacy:$kind` id with a derived-field refresh, and `Test-SlopMotionActive` now counts sticky and priority-≤3 events so a waiting approval keeps the 33 ms cadence. Add assertions that lock this in rather than rewriting it.

In `tests/slop-motion-check.ps1` and `tests/slop-motion-cadence-check.ps1`:

- Assert stalled resolves to `thinking`/`rect`, that a sticky approval event outranks a stalled base and an error event, that it survives repeated `Set-SlopBaseCondition -Streaming $true` ticks, and that it clears by exact id on reply and by `permission:` prefix on cancel.
- Assert `success` priority 1 outranks a stalled base (2) and live work (4) and expires to the underlying base in 1.5 s; `error` is priority 1 transient for 2 s. Sticky `critical` remains until explicitly cleared.
- Assert derived fields (`HoldRemaining`, `State`, `Status`, `Source`, `Priority`) are current immediately after an event mutation, so the 33 ms cadence check stays green.
- Keep `Sync-SlopSignal` state/status comparison coverage.

No new event kinds, priorities, or app call-site rewiring are in scope.

## 2. Effective-signal-driven face behavior

Make the authority explicit at `src/Slop.ps1:1213-1219` with `$sig = Get-SlopSignal -State $script:Motion` (the cache is already refreshed each tick, so this is a clarity/robustness change) and expand the mapping to the **effective** result:

- `idle` and `cancelled` → speed 0.3, not frozen;
- `working` (kinds `working`/`tool`) → speed 1.5;
- `thinking` kinds (`approval`, `stalled`, `warning`, `thinking`) → frozen, speed 0;
- `error` / `critical` → frozen, speed 0;
- `success` → `0.3 + 1.7 * $script:Motion.MoodPulse.Value`, not frozen, giving fast-then-settle.

Use the effective `Kind` to force `spiral` for the thinking classes (section 3). No new signal fields are needed for face behavior.

## 3. Particle region, clipping, and the spiral

`src/Slop.Face.ps1`:

- Add `spiral` to the `Update-SlopFaceLayer` `ValidateSet` and switch. Formula per dot `i` of `n`: golden angle `a = i * 2.39996323`, radius `r = 0.34 * sqrt((i + 0.5) / n)`, position `(0.5 + r*cos(a + rot), 0.5 + r*sin(a + rot))` with `rot = Time * 0.12 * Speed`. Twelve dots, no new dependency.
- Add an `-Inset` parameter (default `3.0`) and clamp every computed `nx`/`ny` into `[0, 1]` before scaling. Inset plus clamp keeps even the largest dot inside the region.
- Keep `New-SlopFaceLayer` hit-test-invisible; give the caller ownership of `Clip` so compact and expanded can use different geometries. Its pastel palette stays unchanged.

`src/Slop.ps1`:

- Add `Update-SlopFaceRegion` which sets the face layer's size, `Canvas.Left/Top`, `Clip`, and a `$script:FaceRegion` hashtable of `{ Width; Height }` used by the motion tick.
  - Compact: a 48×48 region centred on the 26×26 `PeaCanvas`, clipped by a rounded rectangle (`RadiusX/Y=10`). Position derives from `Canvas.GetLeft/Top($PeaCanvas)` so it follows `Update-PeaAnchor`.
  - Expanded: full window at origin, `Clip = $BodyPath.Data` (window-space geometry from the membrane), so particles follow the organic body edge.
- Insert the face layer **before** `Frame` in `Stage.Children` at init, so it renders behind chat, header controls, and buttons. Keep `IsHitTestVisible=$false`.
- Call `Update-SlopFaceRegion` from init, `SizeChanged`, the pseudo-maximize toggle, `Expand-Chat`, `Collapse-Chat`, and tray show/hide — every path that changes mode or window size. Avoid adding the layer to `Stage` twice.
- Pass `$script:FaceRegion.Width/Height` and `-Inset 3.0` to `Update-SlopFaceLayer` each tick.

Pattern selection: keep `Motion.FaceExpression` from idle actions, but map `peek` to `spiral`, and force `spiral` for the thinking kinds above. Success/error keep the frozen behavior from section 2. `spiral` therefore appears both during idle variety and while thinking, as approved.

## 4. Reduced motion

- `Apply-SlopMotion` writes `PeaTranslate.X = 0.0` when `$script:ReducedMotion`; otherwise the existing sine at line 434.
- The motion tick passes `-Frozen:$script:ReducedMotion` and `-Speed 0` to `Update-SlopFaceLayer` when reduced; spring snapping and `Membrane.SetMotionScale(0)` stay as today.
- Shell assertion: the reduced-motion branch must not contain a nonzero face speed or an unguarded sine assignment.

## 5. OpenPulse rendering

In `Apply-SlopMotion`, consume the already-stepped spring without touching `SlopFrame`:

- `BodyPath.StrokeThickness = 3.0 + 6.0 * $m.OpenPulse.Value`.
- At the existing highlight assignment (`src/Slop.ps1:475`), `HeadHighlight.Opacity = [Math]::Min(1.0, 0.55 + 0.10 * $m.OpenPulse.Value)`. That is the only place the highlight opacity is set, so no other path fights it.

Idle drives the value to 0, restoring thickness 3 and opacity 0.55. Streaming gives a subtle ripple; success gives a decaying pulse from `MoodPulse`. No C# change, no geometry invariant change.

## 6. Frame stroke and highlight colour

- Keep `BodyPath.Stroke` in `$script:ColorBrushes`; add a comment at its XAML initial value tying `#CC3B82F6` to `$SlopColors.idle` so the initial state is explicitly palette-matched.
- Change `HeadHighlight.Stroke` XAML initial value from `#55FFFFFF` to the same alpha in the idle palette (`#553B82F6`).
- In `Initialize-MotionVisuals`, replace the highlight brush with a `SolidColorBrush` created as `[System.Windows.Media.Color]::FromArgb(0x55, r, g, b)` from `$SlopColors.idle`, and keep a single `$script:HighlightBrush` reference. It is deliberately **not** in `$script:ColorBrushes`, because its alpha differs from the body stroke.
- In `Set-SlopVisualFromSignal`, animate `$script:HighlightBrush` to `[System.Windows.Media.Color]::FromArgb(0x55, $new.R, $new.G, $new.B)` using the existing `Animate-BrushTo` helper (160 ms cubic ease). The opacity animation in section 5 is independent of this colour animation. Result: blue at rest, amber thinking/stalled/approval, green working/success, red error.

## 7. Wander bounds

- Cache `$script:WorkArea = [System.Windows.SystemParameters]::WorkArea` at init and refresh it on `SizeChanged`.
- In the wander branch, clamp the new `window.Left` into `[work.X, work.Right - window.Width]` (with a guard when the window is wider than the work area). Top is unchanged.
- Shell assertion: the wander assignment must reference the clamped value and `$script:WorkArea`.

## 8. Tests and verification

- Bring the current 362/7 baseline to green by refreshing all seven stale tour anchors after the source edits. The stale success-overlay expectation was already corrected in the working tree.
- Extend `tests/slop-face-check.ps1`: all five patterns finite and inside the region, explicit out-of-range drift clamps, compact-sized region keeps every dot inside 48×48, `Frozen` holds positions constant across two times, spiral is rotationally distinct from ring.
- Extend `tests/slop-motion-check.ps1` and `tests/slop-motion-cadence-check.ps1` per section 1.
- Extend `tests/slop-shell-check.ps1` (or add a focused suite registered in `tests/Slop.Tests.ps1`) for: effective-signal read in the face tick, reduced-motion zeroing, OpenPulse render mapping, face layer inserted before `Frame`, wander clamp, highlight in the palette animation, no GUID legacy event ids.
- Re-run `tests/slop-tour-check.ps1` after every source edit and refresh anchors to the final working tree; keep that refresh uncommitted with the user's `Slop.ps1` edits.
- Gates: `verify.ps1`, full Pester aggregate (expect at least 369 passing, 0 failed), geometry 18/18, and `tools/verify-motion.ps1` live pass. Reconcile the tracked `docs/architecture.md` where wording is stale; treat the untracked `docs/visual-signal-system.md` as a read-only design reference and do not modify or commit it.

## Risks

- Event priority is global: approval 0 outranks error 1 and stalled 2. That is intentional and matches `docs/visual-signal-system.md`; card and frame must agree.
- The deterministic legacy id changes repeated non-held `Set-SlopSignal` calls from accumulate to replace. No app call site uses it now and no current test relies on accumulation, but the suite must still verify the change is behavior-preserving.
- Clipping to `BodyPath.Data` ties particle bounds to the membrane's window-space geometry; if `Data` is null while collapsed, fall back to the compact region rather than setting a null clip.
- `HeadHighlight.Opacity` is written at one site today; if expand/collapse gains another writer later, the pulse modulation must be composed with it.
- Changing the stalled colour from green to amber alters live pixel probes; the verifier already recognises amber for thinking, so no visual invariant regresses, but the live run must be repeated.
- Source line shifts will stale CodeTour anchors and inline references again; they must be refreshed in the same pass.

## Out of scope

- New cyan/teal active tokens, System Sense severity/acknowledgement cards, sticky critical alerts, and cancel-event presentation from `docs/visual-signal-system.md`.
- New graphics library, rose curves, or Lissajous patterns beyond the approved spiral.
- C# `SlopFrame` pulse API or membrane physics changes.
- Changing the 12-dot count, canonical palette RGB values, or the request/permission protocol.
- Committing the user's uncommitted source edits, untracked docs, `testResults.xml`, or pushing/PR work.

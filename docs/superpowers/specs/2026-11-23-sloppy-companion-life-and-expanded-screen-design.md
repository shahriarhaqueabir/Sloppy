# Sloppy — Companion Life, System Sense, and Expanded Screen — Design

Status: approved in chat 2026-11-23. Scope: Sloppy presentation, idle behaviour, and opt-in local system sensing. No changes to the OpenCode bridge, approval/lifecycle semantics, or the compact pea signal colour table.

## Goal

Make Sloppy feel continuously alive (Tamagotchi + Clippy + companion) without turning it into a heavy monitor or a fake news feed. Three concrete outcomes:

1. The blob is almost always moving or changing expression; idle pauses are short.
2. Thought bubbles come only from the machine itself — opt-in, local, passive system observations.
3. The expanded screen is readable at any size (including maximized) and has a richer but still simple chat surface.

Chosen engine approach: **in-process, throttled .NET reads inside the existing motion timer**. No background jobs, no new processes, no admin requirement, no network calls.

## Non-goals / safety boundaries

- No data leaves the machine. No HTTP calls from System Sense.
- No auto-remediation: Sloppy only reports, never kills processes or changes settings.
- No admin requirement: checks that deny access are silently skipped.
- No random facts, jokes, tips, or news in bubbles. Those were removed in this slice.
- No full window-climbing parkour (Phase B, deferred).
- No change to the canonical signal table: idle/chat-open blue, working/success green, stalled/approval amber, error red.

## 1. System Sense (opt-in)

- Default **off**. Toggled from the tray menu (`System Sense: Off` / `System Sense: On`).
- State persisted to `%APPDATA%\Slop\settings.json` as a single boolean; missing/unreadable file means off.
- Evaluation cadence: 60 seconds, driven from the motion timer by an accumulated delta (not a second DispatcherTimer). First evaluation runs 60s after enabling, not immediately.
- Read-only signals, all from cheap .NET APIs:
  - CPU utilisation % (PerformanceCounter or equivalent; first sample may be 0, ignore warm-up).
  - RAM used % and disk-free % (ComputerInfo / DriveInfo).
  - TCP listener count and established-connection count vs a rolling baseline.
  - Process count vs a rolling baseline.
  - Failed logins: Security log event 4625 within the last 5 minutes, best-effort; any access-denied or missing-log condition is swallowed.
- Alerts fire only on crossings/deltas: RAM > 85%, disk-free < 10%, CPU > 90% across two consecutive samples, new listening port, connection count +30% vs baseline, process count +25% vs baseline, any failed login.
- Cooldown: same alert kind suppressed for 5 minutes; at most one bubble per evaluation.
- Every check is wrapped so a single failure never stops the motion loop.
- When disabled, no checks run and no Sense bubbles are produced.

## 2. Thought bubbles

- Content: exclusively System Sense alert strings. With Sense off, no thought bubbles are created.
- Sizing: `TextBlock.TextWrapping = Wrap`, MaxWidth ~190px compact / ~320px expanded, `Padding = 12,8,12,8`, FontSize **8** compact / **10** expanded.
- Position is clamped to the window bounds so text is never cut off; in expanded state the bubble is parked above the chat tile instead of over the pea.
- Existing 6-second fade-in/hold/fade-out lifecycle is retained.
- Bubbles are decorative and `IsHitTestVisible = False`.

## 3. Always-alive motion

- Idle gap after any action reduced from 3–8s to **1–3s**.
- Phase rotation gains `blink`, `tilt`, `bounce`, `peek`, `yawn` alongside the existing `anticipate`/`airborne`/`land`/`sit`/`stretch`/`wander`.
- A continuous low-amplitude sway and breathing target is applied in `Update-SlopMotionState` before the phase switch so all phases retain micro-motion.
- Face layer gains named expression patterns (scattered / ring / cluster / line), rotated on phase change. Drift speed still follows the signal state: idle slow, working fast, stalled medium, error/approval frozen.
- Reduced-motion continues to snap springs and suppress fidgets; System Sense still works but produces no animated bubble entrance.

## 4. Expanded screen and full-screen fix

- On first expand, use **760×540** (or the last user-resized size); minimum stays 484×330. Manual resizes are remembered for the next expand. Maximize remains supported. "Compact" below means the collapsed pea window.
- Root cause of the full-screen bug: `Frame.Clip` is a fixed `RectangleGeometry Rect="4,4,440,286"` and `ChatScroll` has a fixed `MaxHeight="235"`, so the content stays clipped to the original 484×330 box when the window grows.
- Fix:
  - Rebuild `Frame.Clip` from `Frame.ActualWidth/ActualHeight` in the `SizeChanged` handler.
  - Remove `ChatScroll.MaxHeight`; the middle row takes `*`, the input row stays `Auto`.
  - Re-anchor pea, ground shadow, and face layer on every resize.
  - Update `ResizeGrip` bounds naturally via `Canvas.Right/Bottom` (already correct).
- Bubbles: role colour + emoji prefix (👤 user / 🧠 assistant / ⚙️ system / ⚠️ alert), 12px padding, 10px vertical gaps, wrapping, monospace font for lines that look like commands.
- Shortcuts strip built from existing profile helpers: `startslop`, `stopslop`, `slopstatus`, `verify`, `review`, `kickoff`, `sign out`. Clicking a chip **inserts** the command into the input box; it never executes automatically.

## Components and data flow

| Unit | File | Responsibility |
|---|---|---|
| Sense collector | `src/Slop.Sense.ps1` (new) | Reads signals, compares baselines, returns alert strings. Pure functions, no UI. |
| Settings | `src/Slop.Sense.ps1` | Reads/writes the single opt-in boolean in `%APPDATA%\Slop\settings.json`. |
| Motion phases | `src/Slop.Motion.ps1` | New phases, short idle gaps, continuous sway/breathing. |
| Face expressions | `src/Slop.Face.ps1` | Pattern switching driven by a supplied phase name. |
| Shell wiring | `src/Slop.ps1` | Tray toggle, throttled evaluation, bubble creation, XAML, dynamic clip, chips. |

Flow: motion tick → accumulate 60s → if Sense on, call collector → zero or one alert string → `Add-SlopThoughtBubble` → existing fade/remove loop.

## Error handling

- Collector functions return `$null` on any failure and never throw into the UI thread.
- Settings read/write failures degrade to "off" and are ignored.
- Threshold comparisons are guarded against missing counters and divide-by-zero.

## Tests

- `tests/slop-sense-check.ps1` (new): threshold boundaries, baseline deltas, dedup cooldown, settings fallback, disabled-mode no-op.
- `tests/slop-motion-check.ps1`: new phases reachable; idle gap range 1–3s; reduced-motion still snaps.
- `tests/slop-face-check.ps1`: all four expression patterns produce 12 dots.
- `tests/slop-shell-check.ps1`: dynamic clip assignment present; no fixed `MaxHeight` on `ChatScroll`; Sense toggle wired to tray; shortcut chips present.
- Live: `tools/verify-motion.ps1` after starting via `startslop`, including a maximize pass to confirm the input row is visible and content is not clipped.

## Out of scope

- Background jobs / external sensing processes.
- Network egress, telemetry, or cloud enrichment.
- Windows event-log forensics beyond the single best-effort 4625 check.
- Full Shimeji-style window parkour.
- Semantic face meaning (pixels remain decorative).

# S.L.O.P. Two-Axis Visual Language Design

Status: approved on 2026-11-22; implementation not started.
Goal: make color and shape Slop's primary, glanceable communication channel. Detailed conversation remains in the chat frame opened by clicking the pea.

## Decision

Color and shape are **independent axes**, not fixed pairs:

- **Color = outcome / feeling.** Blue neutral, amber working, green success, red problem.
- **Shape = engagement mode.** Circle resting, triangle processing, square engaged/holding, rectangle waiting/blocked.

Only the existing four colors (`#3B82F6`, `#F59E0B`, `#22C55E`, `#EF4444`) and four shapes (circle, square, triangle, rect) are used. No face, eyes, mouth, or new palette entries.

## Signal table

| Condition | Color | Shape | Duration |
|---|---|---|---|
| Idle / ready, chat closed | Blue | Circle | persistent |
| Thinking / streaming (tokens flowing) | Amber | Triangle | while request active |
| Stalled: request active, no token for > 3 s | Amber | Rectangle | until next token or request end |
| Success: response finished normally | Green | Square | 1.5 s, then return to base |
| Error / cancel | Red | Rectangle | 2.0 s, then return to base |
| Chat open, no pending request | Blue | Square | while expanded and idle |
| Chat open + streaming | Amber | Triangle | while request active |

Notes:
- "Stalled" changes **only** shape; color stays amber. "Chat open" changes **only** shape; color stays blue. This is what makes the axes independent.
- Success/error are transient overlays. A new request always wins over an active overlay.
- After any overlay expires, the blob returns to the base signal derived from current streaming/chat-open state.
- Random idle shape morphing is removed. Idle remains lively through hop, squash/stretch, lean, breathing, and shadow coupling from the motion overlay.

## Current implementation anchors (`src/Slop.ps1`)

- Shapes declared lines 79-94; `script:Shapes` line 148 currently ordered square, circle, tri, rect.
- `Set-SlopMood` lines 152-165 sets all shape fills, status dot, frame border, and motion mood.
- `Expand-Chat` / `Collapse-Chat` lines ~232-247.
- `Start-Stream` sets amber; drain timer sets red on error and green on done (lines ~345-430).
- Idle morph is now spring-driven inside `src/Slop.Motion.ps1` via `Update-SlopMotionState` and `Weights[4]`.
- Header status dot: `x:Name="StatusDot"` line 42.

## Architecture

### 1. Signal model (`src/Slop.Motion.ps1`)

Add a pure, WPF-free signal state with:

- `BaseColor` / `BaseShape` — derived from app condition (idle, streaming, stalled, chat open).
- `TransientColor` / `TransientShape` / `HoldRemaining` — success/error overlay with countdown.
- `Set-SlopSignal -State -Color -Shape [-HoldSeconds]` — sets base or transient explicitly.
- `Get-SlopSignal -State` — returns effective color/shape (transient wins while `HoldRemaining > 0`).
- `Update-SlopSignal -State -Dt` — decrements hold; when it reaches zero, clears the transient.
- `Set-SlopBaseCondition -State -Streaming -ChatOpen -Stalled` — single resolver that applies the base row of the signal table, so call sites never hard-code pairs.
- Canonical shape indices: `circle = 0`, `square = 1`, `triangle = 2`, `rect = 3`. `src/Slop.ps1` must order `script:Shapes` to match, so shape weights and the signal table use the same index space.

### 2. Trigger wiring (`src/Slop.ps1`)

- Send / start of stream: `Streaming=$true`, `Stalled=$false`.
- Each dequeued token: reset the stall stopwatch and `Stalled=$false`.
- Drain-timer tick detects no token for 3 s while streaming: `Stalled=$true`.
- Done with text: transient success (green square, 1.5 s).
- Error or cancel: transient error (red rectangle, 2.0 s).
- Expand: `ChatOpen=$true`. Collapse: `ChatOpen=$false`. Streaming outranks chat-open in the resolver.
- The resolver is called from one place after any condition change; no scattered color/shape assignments remain.

### 3. Rendering

- Shape changes use the existing spring weights: the new shape is targeted, and the transition happens during a hop (squat → apex swap → land/settle). No hard `Visibility` cut.
- During the crossfade, multiply each shape's render scale by its effective opacity (`shapeScale = squash × puff × opacity`), so the outgoing shape shrinks as it fades and the incoming shape grows as it appears. At rest opacity is 1, so the settled silhouette is unchanged.
- Color changes animate existing `SolidColorBrush.Color` values on the four shapes, status dot, and frame border over ~160 ms with `ColorAnimation` / `CubicEase`. Brushes must be per-element instances so the animation does not alias.
- An 8 px shape glyph is added to the chat header beside `StatusDot`, using the same four geometries and current effective color. While the pea is hidden, this keeps both axes visible. It is not a face and adds no new color.
- All existing motion springs, drag, pin/Esc/close, streaming, history trim, backend URL, and mode prompts remain unchanged.

## Error handling

- If the backend is unreachable, the existing error path emits red rectangle; no history entry is added.
- Cancel is treated as error (red rectangle) for 2 s, then returns to base.
- A new send during a transient overlay immediately replaces it with amber triangle.
- `Dispatcher.UnhandledException` guard remains in place.

## Verification

1. Headless checks in `tests/slop-motion-check.ps1` extended with:
   - every signal-table row resolves to the expected color/shape pair;
   - transient overlay wins, then expires and returns to base;
   - new request clears an active overlay;
   - chat-open changes shape only; stalled changes shape only.
2. Live WPF verification (`tools/verify-motion.ps1`) extended to sample header/shape pixels for each reachable pair and confirm:
   - idle blue circle, send → amber triangle, done → green square then blue circle, error → red rectangle, chat open → blue square;
   - click → stream → Esc → drag still pass;
   - app stdout/stderr empty.
3. Parser check, `verify.ps1`, and `review.ps1`.

## Acceptance criteria

- [ ] Every row in the signal table is implemented and headless-tested.
- [ ] No random idle shape changes remain.
- [ ] Color and shape can change independently (chat-open and stalled cases).
- [ ] Success/error overlays are transient and are pre-empted by a new request.
- [ ] Header glyph mirrors the active shape/color while the pea is hidden.
- [ ] Live verification passes with clean logs and no regressions to chat/drag/Esc.

## Out of scope

- New colors, new shapes, faces, eyes, blinking, look direction.
- Voice, UIA/vision screen context, allowlisted tool delegation.
- Changing the chat layout, backend protocol, or mode prompts.
- Priority-based multi-signal resolver (approach C from brainstorming).

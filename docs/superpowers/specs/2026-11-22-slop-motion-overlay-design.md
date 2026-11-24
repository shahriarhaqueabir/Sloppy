# S.L.O.P. Motion Overlay Design

Status: approved for spec write-up on 2026-11-22; implementation not started.
Scope: make idle pea, state feedback, and chat frame/streaming feel more lively and fluid.
Hard constraint: **do not change the way Slop looks.** Same shapes, colors, size, no face, no new elements.

## Source material

- `notesfront.md` — spring-driven slime silhouette on a 32x36 pixel grid: squash/stretch, jelly wobble, anticipation-squat hop, landing impact, ground shadow coupling, idle micro-wander, poke reaction.
- `notesfront2.md` — four geometric shapes as distance fields; shape morph via spring-blended weights; "squat → swap mid-air → land and settle"; goo corner rounding; moods `Idle / Thinking / Alert / Happy`.

We borrow the **timing, physics, and scheduling** from both notes. We do **not** port either pixel rasterizer.

## Current implementation anchors (`src/Slop.ps1`)

- Shapes: `ShapeSquare` / `ShapeCircle` / `ShapeTri` / `ShapeRect`, all `Fill="#3B82F6"`, lines 79-93.
- Highlight/glint rects, lines 95-96 (must stay unchanged).
- Ground shadow ellipse, line 99 (must stay, only its timing/opacity may be driven).
- `Get-ShapeScale`, `Morph-Shape`, lines 158-181 — current hard swap + 220 ms scale pop.
- `Expand-Chat` / collapse, lines 185-201 — current 220 ms opacity fade.
- Stream-drain `DispatcherTimer`, line 349; color set on thinking/error/success, lines 359/366.
- Idle morph timer, lines 398-402.
- `Set-ShapeColor`, lines 150-154.

## Design

### 1. Architecture — one dispatcher-owned motion engine

- Add a single `MotionEngine` (PowerShell script object + one `DispatcherTimer`) that is the only writer of transform/opacity on the animated elements.
- Tick at ~30 fps presentation; integrate physics with fixed 1/120 s substeps accumulated from the tick delta, capped (e.g. 4 substeps) so background-tab stalls do not explode the springs.
- Engine state: springs for `squash` (ScaleX/ScaleY inverse pair), `lean` (rotation), `puff` (uniform scale), `jiggle` (secondary wobble), `hopY` (vertical offset + velocity), and four `shapeWeights[4]` plus a `goo` scalar.
- All writes happen on the dispatcher thread. No `Start-ThreadJob` touching UI. Fonts/layout/colors/static geometry are never modified.
- One shared easing helper replaces the ad-hoc `DoubleAnimation` calls so open/close, bubbles, and morph use consistent curves.

### 2. Idle pea

- Breathing: slow sine driving tiny `squash`/`puff` around scale 1.0; amplitude small enough that the silhouette stays pea-sized and the bbox test in the verification script still passes.
- Micro-wander: low-amplitude horizontal offset with a slow randomized target; no large translation.
- Hops: randomized interval (a few seconds). Sequence = anticipation squat → launch → airborne → landing squash → jelly settle, using damped springs. Ground shadow ellipse tightens/darkens slightly on landing and relaxes as the pea settles — same ellipse, same color.
- Idle morph: reuse the hop. At the apex, blend `shapeWeights` from the outgoing shape to a random incoming shape over the airborne window; land and settle with the new shape. Outgoing/incoming shapes overlap briefly with normalized opacity so the change flows instead of cutting. No hard `Visibility` swap.
- Guardrail: `notesfront2.md` distance-field blending and goo are approximated only through opacity/scale/rotation on the existing 4 shapes. No distance-field rasterizer is introduced.

### 3. State feedback (no new visuals)

- Thinking/streaming (existing amber `#F59E0B`): faster, smaller wobble plus slight lean oscillation while the response is in flight.
- Error (existing red `#EF4444`): one short damped shake/settle pulse.
- Success/finish (existing green `#22C55E`): one gentle overshoot-and-settle pulse.
- Idle blue `#3B82F6` remains the default. No palette morphs, no blinking, no eyes/mouth, no look direction. Highlight/glint rects stay fixed.

### 4. Chat frame and streaming

- Expand/collapse: eased scale+opacity with slight overshoot on open and a quicker settle on close, replacing the plain 220 ms fade. Must not reintroduce the `Expand-Chat` flash or `Frame.Background` mutation that were removed in the last review pass.
- Bubbles: small staggered opacity + translateY entrance for each new user/assistant bubble; colors and layout unchanged.
- Streaming text: keep the existing `ConcurrentQueue` + drain timer and text color; only reduce perceived jerkiness (e.g. consistent per-drain cadence and subtle opacity ramp on newly appended text). No reflow tricks that change layout.

### 5. Guardrails (explicit non-goals)

- Same 4 shapes and same silhouette proportions; same blue `#3B82F6`; same highlight rects; same ground shadow element; same frame/chat layout and colors.
- No eyes, mouth, blink, look direction, or face — Slop stays faceless.
- No 32x36 / 36x40 `WriteableBitmap` port, no `SlopSim` C# sim, no distance fields in the WPF app.
- No new visual elements added to the XAML; only transforms, opacity, and scheduling change.
- No changes to backend URL/model/request, mode prompts, pin/Esc/close behavior, drag, or cleanup logic.
- Reduced-motion: if the OS reports `SystemParametersInfo(SPI_GETCLIENTAREAANIMATION)` false, snap to final values with no spring motion. (Optional if cheap; otherwise document as deferred.)

### 6. Verification plan

1. PowerShell parser check: 0 errors.
2. Live launch with `pwsh -STA -NoProfile` (focus-checked input only — no leaking keys into other apps).
3. Idle bbox/blue-pixel sampling over several seconds proves motion variance while blue pixel count and silhouette stay in the pea region.
4. Capture a frame during a hop to confirm shadow coupling; confirm no new colors appear (green/red/amber only as existing state colors).
5. Click-expand, pin, send a message, confirm streaming still increments incrementally with `errorRed=0`, Esc collapses, drag moves the window — all matching the last passing physical-verification run.
6. Confirm app stdout/stderr empty.
7. Review gate on the diff. No Pester suite exists; adding one is a separate follow-up, not part of this change.

## Acceptance criteria

- [ ] Single motion engine drives all four surfaces (idle, states, frame, stream) from one tick with fixed substeps.
- [ ] Idle shows breathing, micro-wander, and hop-morph with squat/apex-swap/land-settle.
- [ ] Morph crossfades overlapping shapes instead of hard visibility swap.
- [ ] Thinking/error/success have subtle spring pulses using only existing colors.
- [ ] Frame open/close eases without the old flash; bubbles enter with a small stagger; streaming cadence is smoother.
- [ ] Pixel samples show no new colors, no face, unchanged size and silhouette set.
- [ ] Full live interaction verification passes with clean logs.

## Out of scope / follow-ups

- Pester test suite for the motion engine.
- Porting the pixel-sim renderer (notesfront v1/v2) — explicitly rejected to preserve current look.
- Voice, modes beyond the existing three prompts, screen context, UIA/vision features.

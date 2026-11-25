# Sloppy — Organic Conversational Interface Design

Status: approved on 2026-11-23; implementation not started.
Goal: make the expanded chat surface part of Sloppy's body instead of a conventional window. Sloppy does not *have* a chat window — it opens itself up to let you interact with it.

## Design principle

Sloppy is a small, living slime creature. Clicking it must feel like the creature opening its own body to communicate, not like launching a separate application or chatbot panel. Sloppy's identity survives every state transition.

This is a visual-shell and motion change only. It does not alter the OpenCode bridge, permissions, persona, or service control shipped in `4a30702`.

## Decisions

1. **Full restyle, not a prototype beside the shipping UI.** The existing expanded frame is replaced.
2. **Head: tiny, wide, low shelf** at the upper-left. No bump, no face, no eyes, no mouth, no emoji. One faint highlight along the shelf.
3. **Conversation fills ~85%** of the body. Input pocket spans the bottom. The left ~20% is character space, not a reserved empty column.
4. **Three faint embedded dots** near the head: settings, pin, close. Revealed on hover. Send, mic and attach stay in the input pocket.
5. **Keep the compact-pea signal table** (circle / square / triangle / rect plus transient success and error) and the exact-RGB verifier. No new states, colors or shapes.
6. **`slopsettings` PowerShell command** is recorded design intent for tweaking Slop configs and files. It is out of scope for this slice.

## Shape

### Compact (rest)

Unchanged from today: the pea with its two-axis signal language (color = outcome, shape = engagement). This preserves the exact-RGB verifier in `tools/verify-motion.ps1`.

### Expanded

- Head is a wide, low rise at the **upper-left** of the silhouette — a gentle rise and fall, never a rounded nub.
- One faint highlight traces the head shelf. No face, eyes or mouth.
- Body stretches outward and downward into a soft, asymmetrical blob. Silhouette is a `PathGeometry` with animated control points, not a rounded rectangle.
- Borders are hairlines at low opacity. Material is soft translucent slime with restrained internal lighting; avoid glow, heavy gradients and stacked shadows.
- Conversation pocket is a stable translucent region clipped by the blob outline. Content reads as embedded in the slime, not floating in a generic panel.
- Input pocket sits at the bottom, wide, with recognizable send / mic / attach affordances that read as embedded objects.
- Attachments appear as small held objects; active operations get small contextual marks; approval cards appear as embedded compartments with clear conventional controls.

### Current implementation anchors (`src/Slop.ps1`)

- Expanded frame: `<Border x:Name="Frame" ... CornerRadius="20" ...>` at line 55; drag handle line 64; `ShapeGlyph` line 65; `StatusDot` line 72; `ChatScroll` line 85; input row line 88; `InputBox` line 96.
- Element lookups lines 148-155; drag/close handlers line 178-179.
- Frame opacity/scale driven per tick at lines 305-309.
- `Expand-Chat` line 325; `Collapse-Chat` line 364.
- Click-to-expand line 438; stream scroll-follow lines 791-793; `ReducedMotion` state line 842.

## Behavior

### Opening

1. Pea reacts to the click with a quick squash.
2. Body stretches outward and downward.
3. Head shelf stays anchored at the upper-left throughout.
4. Conversation and input fade in naturally.
5. Silhouette settles with a short jelly overshoot, then goes still.

### Closing

1. Text and controls retract / fade first.
2. Body contracts inward.
3. Head shelf folds back into the compact pea.
4. Idle breathing resumes. Slightly faster than opening.

Reversed by Escape (`src/Slop.ps1` line 416) and the close control.

### In-conversation reactions

| State | Body | Head shelf |
|---|---|---|
| Listening | Slow, attentive breath | Slight forward lean |
| Thinking | Gentle wobble | Tilt |
| Streaming | Subtle pulse through the body | Steady, small nod |
| Success | Brief bounce / expand | Lift |
| Error | Short controlled stiffness | Tightens |

Reactions are body-only. No face, no facial expressions, no emoji.

### Hard usability rule

The outer silhouette deforms; the inner content does not.

- Text, scrolling, code, tables and approval cards live in a stable internal layout that is **clipped** by the blob outline.
- The chat UI is never rebuilt per animation frame — only the silhouette geometry and the container transform update.
- Long conversations scroll; large responses can expand the available workspace. The expanded interface is resizable without losing its organic silhouette.
- Keyboard navigation and accessibility are preserved.
- Respect Windows display scaling and `ReducedMotion`: reduce to a simple fade with no geometry deformation.
- Window dragging, pinning and dismissal remain intuitive.

## Architecture

### 1. Organic silhouette (`src/Slop.Motion.ps1` or a new `src/Slop.Silhouette.ps1`)

- Represent the blob as a closed `PathGeometry` with named control points for the head shelf, left flank, bottom and right flank.
- Expose a normalized `Open` progress value (0 = pea, 1 = expanded) driven by a spring, plus a separate `React` impulse for click squash, thinking wobble, success bounce and error stiffness.
- Interpolate control points from the compact outline to the expanded outline using `Open`. Add the reaction impulse as a small offset on top.
- Keep the path generation WPF-free where practical so it can be unit-tested like `src/Slop.Motion.ps1` springs.

### 2. Stable content layer (`src/Slop.ps1`)

- Keep the existing `Grid` rows (drag / conversation / input) as the internal layout; do not deform their transforms.
- Replace the `Border` frame with a geometry-clipped container: apply the silhouette path as `Clip` (or `OpacityMask`) on a wrapper that hosts the unchanged content grid.
- Reuse the existing `ChatScroll`, `InputBox`, `StatusDot` and approval-card rendering. No token/markup/permission changes.
- Add three faint dots near the head for settings / pin / close, revealed on hover, wired to the existing close handler and future settings command. Send/mic/attach remain in the input pocket.

### 3. Motion integration

- `New-SlopMotionState` (line 65) gains springs for `Open`, head/body reaction and optional resize; existing `FrameScale` / `FrameAlpha` (lines 73-74) are replaced or repurposed.
- `Set-SlopFrameTarget` (line 121) becomes the open/closed target driver.
- `Update-SlopMotionState` (line 241) steps the new springs and computes the silhouette path; `-ReducedMotion` (line 257) short-circuits to a fade.
- `Expand-Chat` / `Collapse-Chat` (lines 325 / 364) keep their call sites but now drive geometry instead of a scale transform.
- Signal wiring in `Set-SlopBaseCondition` (line 136) is untouched: the compact pea's color/shape table continues to drive mood and the verifier.

### 4. Settings command (future slice)

Design intent only: a `slopsettings` PowerShell command to tweak Slop configs and files, invoked from the settings dot. It must validate before applying and keep security enforcement outside user-configurable UI. This slice does not implement it.

## Verification

- Existing headless suites must stay green: `pwsh -NoProfile -File tests/slop-opencode-check.ps1` and the motion/lifecycle suites under `tests/`.
- `tools/verify-motion.ps1` exact-RGB samples must still pass unchanged — the compact pea and four shapes are untouched.
- Full gate: `pwsh -NoProfile -File <agent-home>/scripts/verify.ps1`.
- Live verification against the real app: capture the compact state, the open transition, a streamed response, and the close transition; confirm text stays stable while the body deforms, scrolling works, Escape collapses, and reduced-motion flattens to a fade.
- Confirm no orphaned `Slop.ps1` process after verification.

## Risks and trade-offs

- **Clip + text clarity:** clipping a live `ScrollViewer` to an animated path can cause edge artifacts. Mitigate by keeping the clip geometry simpler than the visual outline or inseting the content region from the silhouette edge.
- **Per-frame cost:** rebuilding a `PathGeometry` every tick is cheap for a handful of points but must not trigger layout of the inner grid. Keep content transforms static.
- **Verifier coupling:** exact-RGB sampling assumes the compact pea pixels are stable. The expanded body must not alter compact-state rendering or the samples fail.
- **Settings spec conflict:** `docs/superpowers/specs/2026-11-23-sloppy-settings-control-panel.md` proposes random pixel patterns and preset facial expressions. Those items conflict with the no-face direction and are superseded wherever they touch appearance. Permissions and system sections remain valid.

## Out of scope

- OpenCode bridge, permission model, persona text, service control or session handling.
- New signal states, colors, shapes, face, eyes, mouth or emoji.
- Implementing `slopsettings`.
- Rewriting the exact-RGB verifier.
- Voice input/output and speaking animations (the guide mentions them conditionally; voice is not part of this slice).


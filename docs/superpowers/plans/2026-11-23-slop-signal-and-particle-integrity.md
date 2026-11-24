# Slop Signal and Particle Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Inline execution only** — the standing constraint is no subagents.

**Goal:** Make Sloppy's visible signal, particle region, reduced-motion behavior, frame pulse, and wander match the approved design, on top of the event-driven signal model already in the working tree.

**Architecture:** Repair in place across four modules. `src/Slop.Motion.ps1` keeps ownership of the event model; `src/Slop.Face.ps1` gains a clipped, region-aware particle field with a golden-angle spiral; `src/Slop.ps1` wires the effective signal into face speed/pattern, renders the existing `OpenPulse` spring onto WPF stroke properties, and bounds wander. No new visual facade, no C# changes.

**Tech Stack:** PowerShell 7.6, WPF (`PresentationFramework`, `PresentationCore`, `WindowsBase`), Pester 6, embedded C# `SlopSpring`/`SlopFrame` in `src/Slop.Frame.ps1`, CodeTour JSON.

---

## Working agreement (read before touching anything)

- Work **in place on `main`**. Do not create a worktree, push, open a PR, or change CI/CD.
- The working tree already contains the user's uncommitted edits in `src/Slop.ps1`, `src/Slop.Motion.ps1`, `tests/slop-motion-check.ps1`, `docs/architecture.md`, and `.tours/architect-slop-architecture.tour`. **Never overwrite or discard them.** Apply only the targeted replacements below.
- **Commit policy:** do not stage or commit any file that was already modified at plan start (`src/Slop.ps1`, `src/Slop.Motion.ps1`, `tests/slop-motion-check.ps1`, `docs/architecture.md`, `.tours/architect-slop-architecture.tour`). Commit only files that are clean at baseline (`src/Slop.Face.ps1`, `tests/slop-face-check.ps1`, `tests/slop-shell-check.ps1`, `tests/slop-motion-cadence-check.ps1`) and the new spec/plan docs already committed. Tasks that touch only protected files end with a verification step and **no commit**; this is intentional, not an omission. At the end, report the exact uncommitted file list and ask before committing it.
- Do **not** touch or commit `.memory/topics/companion-life-and-system-sense.md`, `docs/superpowers/plans/2026-11-23-sloppy-gui-refinement.md`, `docs/superpowers/specs/2026-11-23-sloppy-gui-refinement-design.md`, `docs/visual-signal-system.md`, or `testResults.xml`. `docs/visual-signal-system.md` is a read-only design reference.
- Preserve the existing 12-dot count, canonical palette RGB values, signal priority classes, control dots, shortcut chips, and System Sense behavior.
- Every source edit shifts line anchors. Run `tests/slop-tour-check.ps1` after each source edit; the final tour refresh (Task 9) stays uncommitted with the user's source edits.
- Pester `-CI` exit code equals failure count. Always read the `Tests Passed/Failed` line, not just the exit code or `verify.ps1`'s summary.

Baseline at plan time: `361 passed / 8 failed`. Rebase note (2026-11-23, during execution): concurrent source edits fixed the stale signal expectation and applied Task 1's production hardening, so the live baseline is now `362 passed / 7 failed` — seven stale tour anchors only. All line numbers below were re-anchored to that working tree; search by symbol when a source edit shifts them again.

Current contract (authoritative): approval 0 sticky, critical 1 sticky, success 1 transient 1.5 s, error 1 transient 2 s, stalled base 2, warning 3 transient 6 s, working/tool/thinking 4, cancelled 6, idle/chat-open 7. Re-anchored `src/Slop.ps1` symbols: `Update-PeaAnchor` 241, `Get-SlopPeaOrigin` 251, `$SettingsDot.Add_Click` block ends 303, `Expand-Chat` expand call 510, `Collapse-Chat` collapse call 550, tray restore 562 / double-click 582 / hide 583, face init 1139-1143, wander 1184-1187, face tick 1213-1219. Re-anchored tour steps: 5→356, 11→844, 12→752, 13→516, 15→498, 16→1151, 17→412.

## File structure

| File | Responsibility in this plan |
|---|---|
| `src/Slop.Motion.ps1` | Event model hardening already landed in the working tree; no source edit remains in Task 1. No new signal kinds. |
| `src/Slop.Face.ps1` | Particle geometry only: `spiral` pattern, `-Inset`, normalized clamping. No WPF window ownership. |
| `src/Slop.ps1` | Shell wiring: region/clip/z-order, effective face mapping, reduced motion, `OpenPulse` render, highlight colour, wander clamp. |
| `tests/slop-motion-check.ps1` | Stale overlay expectation already corrected in the working tree; add approval/event precedence coverage. (Protected file — do not commit.) |
| `tests/slop-motion-cadence-check.ps1` | Sticky-approval cadence coverage. |
| `tests/slop-face-check.ps1` | Spiral, inset, clamp, compact region, frozen behavior. |
| `tests/slop-shell-check.ps1` | Static invariants for wiring in `src/Slop.ps1`. |
| `.tours/architect-slop-architecture.tour` | Anchors refreshed last; left uncommitted. |
| `docs/architecture.md` | Stale wording reconciled last; left uncommitted with the user's edits. |

---

### Task 1: Add regression coverage for the current signal contract

**Files:**
- Modify: `tests/slop-motion-check.ps1:104-108` (protected — no commit)
- Modify: `tests/slop-motion-cadence-check.ps1:48-50`
- Test: `tests/slop-motion-check.ps1`, `tests/slop-motion-cadence-check.ps1`

The concurrent source edit already applied the production half of this task:
`Set-SlopSignal` uses the deterministic `legacy:$kind` id and refreshes derived
fields, `Test-SlopMotionActive` counts sticky/high-priority events, and the stale
success-overlay expectation is fixed. The current contract is: approval 0 sticky,
critical 1 sticky, success 1 transient 1.5 s, error 1 transient 2 s, stalled base
2, warning 3 transient 6 s, working/tool/thinking 4, cancelled 6, idle/chat-open
7. Do **not** reintroduce the old success-5 / sticky-error rules.

- [ ] **Step 1: Append current-contract assertions to the motion check**

Append after line 108 of `tests/slop-motion-check.ps1` (before the existing
`# 9. a new request pre-empts an active overlay` block):

```powershell
# 8b. success (priority 1) deliberately outranks a stalled base (priority 2)
Set-SlopBaseCondition -State $m -Streaming $true -ChatOpen $false -Stalled $true
Set-SlopSignal -State $m -Color 'success' -Shape 'square' -HoldSeconds 1.0
Assert-Signal 'success' 'square' 'success outranks stalled attention'
$null = Clear-SlopSignal -State $m

# 8c. sticky approval (0) outranks transient priority-1 events, clears by id/prefix
Set-SlopSignalEvent -State $m -Id 'permission:7:p7' -Kind approval -Status 'Approval needed'
Set-SlopSignalEvent -State $m -Id 'request:7:success' -Kind success -Status 'Done'
Assert-Signal 'thinking' 'rect' 'sticky approval outranks success'
$null = Clear-SlopSignalEvent -State $m -Id 'permission:7:p7'
Assert-Signal 'success' 'square' 'approval clear reveals success'
$null = Clear-SlopSignal -State $m

Set-SlopSignalEvent -State $m -Id 'permission:8:p8' -Kind approval -Status 'Approval needed'
Set-SlopSignalEvent -State $m -Id 'request:8:error' -Kind error -Status 'Request failed'
Assert-Signal 'thinking' 'rect' 'sticky approval outranks error'
$null = Clear-SlopSignalEvents -State $m -Prefix 'permission:'
Assert-Signal 'error' 'rect' 'approval prefix clear reveals error'
$null = Clear-SlopSignal -State $m

# 8d. derived fields refresh immediately after an event mutation
$derived = New-SlopMotionState
Set-SlopSignalEvent -State $derived -Id 'request:9:phase' -Kind working -DurationSeconds 2.0
Assert-True ($derived.Signal.State -eq 'working' -and $derived.Signal.Color -eq 'working' -and
    $derived.Signal.Priority -eq 4 -and $derived.Signal.HoldRemaining -eq 2.0 -and
    $derived.Signal.Source -eq 'event') 'derived signal fields refresh immediately'

# 8e. status-only changes sync once; sticky approval survives base churn
$sync = New-SlopMotionState
Set-SlopSignalEvent -State $sync -Id 'sense:1' -Kind warning -Status 'CPU high'
$changed = Sync-SlopSignal -State $sync
Assert-True ($null -ne $changed -and $changed.Status -eq 'CPU high') 'status-only signal change syncs'
Assert-True ($null -eq (Sync-SlopSignal -State $sync)) 'unchanged signal does not re-sync'

$sticky = New-SlopMotionState
Set-SlopSignalEvent -State $sticky -Id 'permission:10:p10' -Kind approval -Status 'Approval needed'
for ($i=0; $i -lt 25; $i++) {
    Set-SlopBaseCondition -State $sticky -Streaming $true -ChatOpen $true -Stalled $false
}
$e = Get-SlopSignal -State $sticky
Assert-True ($e.Kind -eq 'approval' -and $e.Color -eq 'thinking') 'sticky approval survives base churn'
$null = Clear-SlopSignalEvents -State $sticky -Prefix 'permission:'
$e = Get-SlopSignal -State $sticky
Assert-True ($e.Kind -eq 'working') 'approval prefix clear restores the working base'

# 8f. the legacy adapter must not mint random ids
$adapterSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Motion.ps1') -Raw
Assert-True ($adapterSrc -match '\$id = "legacy:\$kind"') 'legacy adapter uses a deterministic id'
```

- [ ] **Step 2: Verify the motion check is green**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-motion-check.ps1' -CI -Output Detailed"
```

Expected: `Tests Failed: 0`. No production file is edited in this task.

- [ ] **Step 3: Add the sticky-approval cadence assertion**

In `tests/slop-motion-cadence-check.ps1`, after line 50, insert:

```powershell

$approval = New-SlopMotionState
Set-SlopSignalEvent -State $approval -Id 'permission:1:p1' -Kind approval -Status 'Approval needed'
Check-Cadence 'sticky approval uses 30 fps' 33 $approval
```

- [ ] **Step 4: Verify both suites**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output Detailed"
```

Expected: `Tests Failed: 7` — the seven stale tour anchors only.

**No commit** — `tests/slop-motion-check.ps1` is protected; `tests/slop-motion-cadence-check.ps1` may be committed later with the other clean test files.

---

### Task 2: Drive the face from the effective signal

**Files:**
- Modify: `src/Slop.ps1:1213-1219` (protected — no commit)
- Modify: `tests/slop-shell-check.ps1:87` (clean at baseline)
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Add static assertions first**

In `tests/slop-shell-check.ps1`, first replace line 87 (it asserts the wiring
this task deliberately removes) with:

```powershell
Assert-True ($src -match '\$pattern = \$script:Motion\.FaceExpression') 'face tick chooses a pattern before drawing'
```

Then insert these assertions after it:

```powershell
Assert-True ($src -match '\$sig = Get-SlopSignal -State \$script:Motion') 'face tick resolves the effective signal explicitly'
Assert-True ($src -match '\$sig\.Kind -in @\(''approval'',''stalled''') 'thinking kinds drive the frozen face state'
Assert-True ($src -match '0\.3 \+ 1\.7 \* \$script:Motion\.MoodPulse\.Value') 'success face speed follows the mood pulse'
Assert-True ($src -notmatch 'Update-SlopFaceLayer[^\r\n]*-Pattern \$script:Motion\.FaceExpression') 'face pattern is chosen, not passed straight from the idle action'
```

- [ ] **Step 2: Run the shell check to see it fail**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output Detailed"
```

Expected: 4 new failures naming the assertions above.

- [ ] **Step 3: Replace the face mapping block**

In `src/Slop.ps1`, replace lines 1213-1219 with:

```powershell
    # face layer drift speed from the EFFECTIVE signal, not the raw base fields.
    # The cache is refreshed each tick by Update-SlopMotionState ->
    # Update-SlopSignal -> Get-SlopSignal; calling it here makes that authority
    # explicit and keeps this block correct if the tick order ever changes.
    $sig = Get-SlopSignal -State $script:Motion
    $frozen = $sig.Kind -in @('approval','stalled','warning','thinking','error','critical')
    $speed = switch -Exact ($sig.Kind) {
        'working' { 1.5 }
        'tool'    { 1.5 }
        'success' { 0.3 + 1.7 * $script:Motion.MoodPulse.Value }
        default   { 0.3 }
    }
    if ($frozen) { $speed = 0.0 }
    $pattern = $script:Motion.FaceExpression
    if ($pattern -eq 'peek' -or $sig.Kind -in @('approval','stalled','warning','thinking')) {
        $pattern = 'spiral'
    }
    Update-SlopFaceLayer -Target $script:FaceLayer -Time ([DateTime]::UtcNow.Ticks / 1e7) -Speed $speed -Width $window.Width -Height $window.Height -Frozen:$frozen -Pattern $pattern
```

- [ ] **Step 4: Verify**

Run the same shell-check command. Expected: all shell checks pass; the aggregate still reports 7 tour failures.

**No commit** — `src/Slop.ps1` is protected.

---

### Task 3: Spiral pattern, inset, and clamping in the face module

**Files:**
- Modify: `src/Slop.Face.ps1:39-91` (clean at baseline)
- Modify: `src/Slop.Motion.ps1:435` (protected — no commit)
- Modify: `tests/slop-face-check.ps1:15-22` (clean at baseline)
- Test: `tests/slop-face-check.ps1`

- [ ] **Step 1: Write failing face tests**

Replace lines 15-22 of `tests/slop-face-check.ps1` with:

```powershell
foreach ($pattern in @('scattered','ring','cluster','line','spiral')) {
    Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Inset 3.0 -Pattern $pattern
    $xs = @($face.Children | ForEach-Object { [System.Windows.Controls.Canvas]::GetLeft($_) })
    $ys = @($face.Children | ForEach-Object { [System.Windows.Controls.Canvas]::GetTop($_) })
    Assert-True (($xs | Where-Object { [double]::IsNaN($_) }).Count -eq 0) "$pattern X positions are finite"
    Assert-True (($ys | Where-Object { [double]::IsNaN($_) }).Count -eq 0) "$pattern Y positions are finite"
    Assert-True (($xs | Measure-Object -Minimum).Minimum -ge 0) "$pattern stays inside the region on the left"
    Assert-True (($ys | Measure-Object -Minimum).Minimum -ge 0) "$pattern stays inside the region on the top"
    Assert-True (($xs | Measure-Object -Maximum).Maximum -le 484) "$pattern stays inside the region on the right"
    Assert-True (($ys | Measure-Object -Maximum).Maximum -le 330) "$pattern stays inside the region on the bottom"
}

# Explicit out-of-range drift is clamped, including in a compact 48x48 region.
Initialize-SlopFaceDots -Seed 42
$script:FaceDots[0].X = 5.0
$script:FaceDots[0].Y = -5.0
Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 48 -Height 48 -Inset 3.0 -Pattern 'scattered'
$first = $face.Children[0]
$firstLeft = [System.Windows.Controls.Canvas]::GetLeft($first)
$firstTop  = [System.Windows.Controls.Canvas]::GetTop($first)
Assert-True ($firstLeft -ge 0 -and ($firstLeft + $first.Width) -le 48) 'out-of-range X drift is clamped into 48x48'
Assert-True ($firstTop -ge 0 -and ($firstTop + $first.Height) -le 48) 'out-of-range Y drift is clamped into 48x48'

# Frozen means byte-for-byte identical positions across different times.
Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Frozen $true -Pattern 'spiral'
$frozenA = @($face.Children | ForEach-Object { '{0:F4},{1:F4}' -f [System.Windows.Controls.Canvas]::GetLeft($_), [System.Windows.Controls.Canvas]::GetTop($_) }) -join '|'
Update-SlopFaceLayer -Target $face -Time 9.0 -Speed 1.0 -Width 484 -Height 330 -Frozen $true -Pattern 'spiral'
$frozenB = @($face.Children | ForEach-Object { '{0:F4},{1:F4}' -f [System.Windows.Controls.Canvas]::GetLeft($_), [System.Windows.Controls.Canvas]::GetTop($_) }) -join '|'
Assert-True ($frozenA -eq $frozenB) 'frozen spiral holds positions constant across time'
Assert-True ($face.Children.Count -eq 12) 'frozen pattern keeps 12 dots'

# Spiral is rotationally distinct from ring.
Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Pattern 'ring'
$ringA = @($face.Children | ForEach-Object { '{0:F4},{1:F4}' -f [System.Windows.Controls.Canvas]::GetLeft($_), [System.Windows.Controls.Canvas]::GetTop($_) }) -join '|'
Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Pattern 'spiral'
$spiralA = @($face.Children | ForEach-Object { '{0:F4},{1:F4}' -f [System.Windows.Controls.Canvas]::GetLeft($_), [System.Windows.Controls.Canvas]::GetTop($_) }) -join '|'
Assert-True ($ringA -ne $spiralA) 'spiral pattern is distinct from ring'
```

- [ ] **Step 2: Run the face check and verify it fails**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-face-check.ps1' -CI -Output Detailed"
```

Expected: failures for the invalid `spiral` pattern, the `-Inset` parameter, and the out-of-range clamp.

- [ ] **Step 3: Implement spiral, inset, and clamping**

In `src/Slop.Face.ps1`, replace lines 39-91 with:

```powershell
function Update-SlopFaceLayer {
    param(
        [Parameter(Mandatory)]$Target,
        [double]$Time = 0.0,
        [double]$Speed = 1.0,
        [double]$Width = 100.0,
        [double]$Height = 100.0,
        [bool]$Frozen = $false,
        [ValidateSet('scattered','ring','cluster','line','spiral')][string]$Pattern = 'scattered',
        [double]$Inset = 3.0
    )
    if (-not $script:FaceDots) { Initialize-SlopFaceDots }
    # Frozen must stop pattern rotation too, not just per-dot drift. Gating the
    # phase once here keeps ring and spiral byte-for-byte static when asked.
    $phaseTime = if ($Frozen) { 0.0 } else { $Time }
    # The region is already the pea/body rectangle, so only a tiny inset is
    # needed for the dot radius. Positions are normalized and clamped below.
    $w = [Math]::Max(10.0, $Width - 2 * $Inset)
    $h = [Math]::Max(10.0, $Height - 2 * $Inset)
    $count = [double]$script:FaceDots.Count
    for ($i = 0; $i -lt $script:FaceDots.Count; $i++) {
        $d = $script:FaceDots[$i]
        $el = $Target.Children[$i]
        $nx = $d.X
        $ny = $d.Y
        if ($Frozen) {
            $driftX = 0.0
            $driftY = 0.0
        }
        else {
            $driftX = 0.08 * [Math]::Sin($Time * $d.Freq * $Speed + $d.Phase)
            $driftY = 0.06 * [Math]::Cos($Time * $d.Freq * 0.7 * $Speed + $d.Phase)
        }
        switch ($Pattern) {
            'ring' {
                $a = (6.2831853 * $i / $count) + $phaseTime * 0.15 * $Speed
                $nx = 0.5 + 0.30 * [Math]::Cos($a)
                $ny = 0.5 + 0.26 * [Math]::Sin($a)
            }
            'spiral' {
                # Golden-angle phyllotaxis: even coverage, no lattice artifacts.
                $a = $i * 2.39996323 + $phaseTime * 0.12 * $Speed
                $r = 0.34 * [Math]::Sqrt(($i + 0.5) / $count)
                $nx = 0.5 + $r * [Math]::Cos($a)
                $ny = 0.5 + $r * [Math]::Sin($a)
            }
            'cluster' {
                $nx = 0.5 + ($d.X - 0.5) * 0.28 + $driftX * 0.3
                $ny = 0.5 + ($d.Y - 0.5) * 0.28 + $driftY * 0.3
            }
            'line' {
                $nx = if ($count -gt 1) { 0.16 + 0.68 * ($i / ($count - 1)) } else { 0.5 }
                $ny = 0.46 + $driftY * 0.4
            }
            default {
                $nx = $d.X + $driftX
                $ny = $d.Y + $driftY
            }
        }
        # Clamp in normalized space so no drift or hand-edited dot can escape.
        $nx = [Math]::Min(1.0, [Math]::Max(0.0, $nx))
        $ny = [Math]::Min(1.0, [Math]::Max(0.0, $ny))
        $px = $Inset + $nx * $w
        $py = $Inset + $ny * $h
        [System.Windows.Controls.Canvas]::SetLeft($el, $px - $el.Width / 2)
        [System.Windows.Controls.Canvas]::SetTop($el, $py - $el.Height / 2)
    }
}
```

- [ ] **Step 4: Map the idle `peek` action to the spiral**

In `src/Slop.Motion.ps1`, replace line 435:

```powershell
                    'peek'       { $State.Lean.Target = -5.0; $State.FaceExpression = 'line' }
```

with:

```powershell
                    'peek'       { $State.Lean.Target = -5.0; $State.FaceExpression = 'spiral' }
```

- [ ] **Step 5: Verify and commit the clean files**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-face-check.ps1' -CI -Output Detailed"
```

Expected: all face checks pass. Then commit only the clean files:

```powershell
git add -- src/Slop.Face.ps1 tests/slop-face-check.ps1
git commit -m "feat(slop): clip particle field and add golden-angle spiral"
```

Do not stage `src/Slop.Motion.ps1` — it is protected.

---

### Task 4: Region, clip, and z-order for the particle layer

**Files:**
- Modify: `src/Slop.ps1:241-279`, `:282-303`, `:498-514`, `:544-553`, `:555-584`, `:1139-1143`, `:1213-1219` (protected — no commit)
- Modify: `tests/slop-shell-check.ps1:87+`
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Add static assertions**

In `tests/slop-shell-check.ps1`, after the assertions from Task 2, insert:

```powershell
Assert-True ($src -match 'function Update-SlopFaceRegion') 'face region has a dedicated layout function'
Assert-True ($src -match '\$Stage\.Children\.Insert\(\$idx, \$layer\)') 'face layer is inserted before the Frame in z-order'
Assert-True ($src -match 'System\.Windows\.Rect\]::new\(0\.0, 0\.0, \$w, \$h\), 10\.0, 10\.0') 'compact face region uses a rounded clip'
Assert-True ($src -match '\$layer\.Clip = \$BodyPath\.Data') 'expanded face region clips to the membrane path'
Assert-True ($src -match '\$script:FaceRegion\.Width') 'motion tick uses the computed face region size'
Assert-True ($src -match '-Inset 3\.0') 'motion tick passes the 3px inset'
```

- [ ] **Step 2: Run the shell check and verify the new assertions fail**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output Detailed"
```

Expected: 6 new failures naming the assertions above.

- [ ] **Step 3: Add `Update-SlopFaceRegion`**

In `src/Slop.ps1`, insert the following after `Get-SlopPeaOrigin` (currently ends at line 255) and before the `$window.Add_SizeChanged` handler:

```powershell
# The particle layer follows whichever region is visible: a small rounded
# square around the compact pea, or the membrane's own window-space path when
# expanded. Called from mode/size hooks and once per tick so the clip follows
# the body as it grows.
function Update-SlopFaceRegion {
    if (-not $script:FaceLayer) { return }
    $layer = $script:FaceLayer
    if (-not $layer.Parent) {
        $idx = $Stage.Children.IndexOf($Frame)
        if ($idx -lt 0) { $idx = 0 }
        $Stage.Children.Insert($idx, $layer)
    }
    if ($script:Expanded) {
        $layer.Width = [Math]::Max(10.0, $window.ActualWidth)
        $layer.Height = [Math]::Max(10.0, $window.ActualHeight)
        [System.Windows.Controls.Canvas]::SetLeft($layer, 0.0)
        [System.Windows.Controls.Canvas]::SetTop($layer, 0.0)
        # The body path is only rebuilt while open; never install a null clip.
        if ($BodyPath.Data) { $layer.Clip = $BodyPath.Data }
        $script:FaceRegion = @{ Width = $layer.Width; Height = $layer.Height }
    }
    else {
        $w = 48.0
        $h = 48.0
        $px = [System.Windows.Controls.Canvas]::GetLeft($PeaCanvas)
        $py = [System.Windows.Controls.Canvas]::GetTop($PeaCanvas)
        if ([double]::IsNaN($px)) { $px = ([Math]::Max(26.0, $window.ActualWidth) - 26.0) / 2.0 }
        if ([double]::IsNaN($py)) { $py = [Math]::Max(0.0, [Math]::Max(26.0, $window.ActualHeight) - 38.0) }
        $layer.Width = $w
        $layer.Height = $h
        [System.Windows.Controls.Canvas]::SetLeft($layer, $px + 13.0 - $w / 2.0)
        [System.Windows.Controls.Canvas]::SetTop($layer, $py + 13.0 - $h / 2.0)
        $layer.Clip = [System.Windows.Media.RectangleGeometry]::new(
            [System.Windows.Rect]::new(0.0, 0.0, $w, $h), 10.0, 10.0)
        $script:FaceRegion = @{ Width = $w; Height = $h }
    }
}
```

- [ ] **Step 4: Replace the init block**

In `src/Slop.ps1`, replace lines 1139-1143:

```powershell
$script:FaceLayer = New-SlopFaceLayer -Seed ([Environment]::TickCount)
$script:FaceLayer.Width = $window.Width
$script:FaceLayer.Height = $window.Height
$Stage = $window.FindName('Stage')
$Stage.Children.Add($script:FaceLayer) | Out-Null
```

with:

```powershell
$Stage = $window.FindName('Stage')
$script:FaceLayer = New-SlopFaceLayer -Seed ([Environment]::TickCount)
$script:FaceRegion = @{ Width = 48.0; Height = 48.0 }
Update-SlopFaceRegion
```

- [ ] **Step 5: Replace the SizeChanged face block**

In the `$window.Add_SizeChanged` handler, replace lines 275-278:

```powershell
    if ($script:FaceLayer) {
        $script:FaceLayer.Width = $window.ActualWidth
        $script:FaceLayer.Height = $window.ActualHeight
    }
```

with:

```powershell
    Update-SlopFaceRegion
```

- [ ] **Step 6: Add mode/size hooks**

Add `    Update-SlopFaceRegion` on its own line at each of these exact positions:

- after the pseudo-maximize `if/else` block in `$SettingsDot.Add_Click` (currently ends at line 303);
- in `Expand-Chat`, immediately after `$script:Membrane.Expand($origin[0], $origin[1])` (line 510);
- in `Collapse-Chat`, immediately after `$script:Membrane.Collapse($origin[0], $origin[1])` (line 550);
- in `Minimize-ToTray`, immediately after `$window.Hide()` (line 583);
- in both tray restore handlers (lines 562 and 582), after `$window.Activate()`.

Replace tray restore line 562 with:

```powershell
$restore.Add_Click({ $window.Show(); $window.WindowState = 'Normal'; $window.Activate(); Update-SlopFaceRegion })
```

Replace tray double-click line 582 with:

```powershell
$script:TrayIcon.Add_DoubleClick({ $window.Show(); $window.WindowState = 'Normal'; $window.Activate(); Update-SlopFaceRegion })
```

- [ ] **Step 7: Make the tick follow the body geometry and use the region**

In the motion tick, insert `    Update-SlopFaceRegion` immediately before the face mapping block from Task 2, and replace the final `Update-SlopFaceLayer` call with:

```powershell
    Update-SlopFaceLayer -Target $script:FaceLayer -Time ([DateTime]::UtcNow.Ticks / 1e7) -Speed $speed -Width $script:FaceRegion.Width -Height $script:FaceRegion.Height -Frozen:$frozen -Pattern $pattern -Inset 3.0
```

- [ ] **Step 8: Verify and commit the clean file**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output Detailed"
```

Expected: all shell checks pass. Then:

```powershell
git add -- tests/slop-shell-check.ps1
git commit -m "test(slop): assert face region, clip and effective-signal wiring"
```

**No commit for `src/Slop.ps1`** — protected.

---

### Task 5: Reduced motion means no visible drift

**Files:**
- Modify: `src/Slop.ps1:433-434`, face mapping block (protected — no commit)
- Modify: `tests/slop-shell-check.ps1` (clean at baseline)
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Add assertions**

In `tests/slop-shell-check.ps1`, append before the `Describe` block:

```powershell
Assert-True ($src -match '\$x = if \(\$script:ReducedMotion\) \{ 0\.0 \}') 'reduced motion zeroes the pea sway'
Assert-True ($src -match 'if \(\$script:ReducedMotion\) \{\s*\$frozen = \$true;\s*\$speed = 0\.0\s*\}') 'reduced motion freezes the particle field'
```

- [ ] **Step 2: Run the shell check and verify the 2 new failures**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output Detailed"
```

- [ ] **Step 3: Zero the sway**

In `src/Slop.ps1`, replace lines 433-434:

```powershell
    $x = 1.6 * [Math]::Sin([DateTime]::UtcNow.Ticks / 10000000.0 * 0.9)
    $script:PeaTranslate.X = $x
```

with:

```powershell
    $x = if ($script:ReducedMotion) { 0.0 } else { 1.6 * [Math]::Sin([DateTime]::UtcNow.Ticks / 10000000.0 * 0.9) }
    $script:PeaTranslate.X = $x
```

- [ ] **Step 4: Freeze the face in reduced motion**

In the face mapping block, immediately after `if ($frozen) { $speed = 0.0 }`, insert:

```powershell
    if ($script:ReducedMotion) { $frozen = $true; $speed = 0.0 }
```

- [ ] **Step 5: Verify**

Run the shell check from Step 2. Expected: all pass.

**No commit** — `src/Slop.ps1` is protected.

---

### Task 6: Render the existing OpenPulse spring

**Files:**
- Modify: `src/Slop.ps1:437-439`, `:475` (protected — no commit)
- Modify: `tests/slop-shell-check.ps1`
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Add assertions**

In `tests/slop-shell-check.ps1`, append before the `Describe` block:

```powershell
Assert-True ($src -match '\$BodyPath\.StrokeThickness = 3\.0 \+ 6\.0 \* \$m\.OpenPulse\.Value') 'OpenPulse drives the body outline thickness'
Assert-True ($src -match '\$HeadHighlight\.Opacity = \[Math\]::Min\(1\.0, 0\.55 \+ 0\.10 \* \$m\.OpenPulse\.Value\)') 'OpenPulse modulates the rim highlight opacity'
Assert-True (([regex]::Matches($src, '\$HeadHighlight\.Opacity\s*=')).Count -eq 1) 'highlight opacity has a single writer'
```

- [ ] **Step 2: Run and verify the 3 new failures**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output Detailed"
```

- [ ] **Step 3: Render the pulse**

In `src/Slop.ps1`, immediately after the shadow writes (currently lines 437-439), insert:

```powershell
    # OpenPulse is already stepped in Update-SlopMotionState; render it here
    # instead of adding a new membrane/C# pulse API.
    $BodyPath.StrokeThickness = 3.0 + 6.0 * $m.OpenPulse.Value
```

Then replace line 475:

```powershell
                $HeadHighlight.Opacity = 0.55
```

with:

```powershell
                $HeadHighlight.Opacity = [Math]::Min(1.0, 0.55 + 0.10 * $m.OpenPulse.Value)
```

- [ ] **Step 4: Verify**

Run the shell check from Step 2. Expected: all pass.

**No commit** — `src/Slop.ps1` is protected.

---

### Task 7: Frame stroke and highlight stay in the signal palette

**Files:**
- Modify: `src/Slop.ps1:46-54`, `:396-410`, `:358-371` (protected — no commit)
- Modify: `tests/slop-shell-check.ps1`
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Add assertions**

In `tests/slop-shell-check.ps1`, append before the `Describe` block:

```powershell
Assert-True ($src -match 'Stroke="#553B82F6"') 'highlight initial stroke uses the idle palette with 0x55 alpha'
Assert-True ($src -match '\$script:HighlightBrush = \[System\.Windows\.Media\.SolidColorBrush\]::new\(\$highlightColor\)') 'highlight brush is tracked separately from ColorBrushes'
Assert-True ($src -match 'Animate-BrushTo -Brush \$script:HighlightBrush') 'highlight colour follows the effective signal'
```

- [ ] **Step 2: Run and verify the 3 new failures**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output Detailed"
```

- [ ] **Step 3: Palette-match the XAML initial strokes**

In `src/Slop.ps1`, replace lines 46-47:

```powershell
    <Path x:Name="BodyPath"
          Fill="#D81E293B" Stroke="#CC3B82F6" StrokeThickness="3"
```

with (comment included):

```powershell
    <!-- Initial stroke matches $SlopColors.idle (#3B82F6); the animation keeps it in sync. -->
    <Path x:Name="BodyPath"
          Fill="#D81E293B" Stroke="#CC3B82F6" StrokeThickness="3"
```

Then replace line 52:

```powershell
          Stroke="#55FFFFFF" StrokeThickness="2" StrokeLineJoin="Round"
```

with:

```powershell
          Stroke="#553B82F6" StrokeThickness="2" StrokeLineJoin="Round"
```

- [ ] **Step 4: Track the highlight brush in `Initialize-MotionVisuals`**

In `src/Slop.ps1`, insert immediately after line 405 (`$script:ColorBrushes += $BodyPath.Stroke`):

```powershell
    $idleRgb = [System.Windows.Media.BrushConverter]::new().ConvertFromString($SlopColors['idle']).Color
    $highlightColor = [System.Windows.Media.Color]::FromArgb(0x55, $idleRgb.R, $idleRgb.G, $idleRgb.B)
    $script:HighlightBrush = [System.Windows.Media.SolidColorBrush]::new($highlightColor)
    $HeadHighlight.Stroke = $script:HighlightBrush
```

It is deliberately **not** added to `$script:ColorBrushes` because its alpha differs from the body stroke.

- [ ] **Step 5: Animate the highlight on signal changes**

In `Set-SlopVisualFromSignal`, insert immediately after line 361 (`foreach ($b in $script:ColorBrushes) { Animate-BrushTo ... }`):

```powershell
    if ($script:HighlightBrush) {
        $highlightColor = [System.Windows.Media.Color]::FromArgb(0x55, $new.R, $new.G, $new.B)
        Animate-BrushTo -Brush $script:HighlightBrush -Color $highlightColor
    }
```

- [ ] **Step 6: Verify**

Run the shell check from Step 2. Expected: all pass, including the XAML parse assertions.

**No commit** — `src/Slop.ps1` is protected.

---

### Task 8: Bound idle wander to the work area

**Files:**
- Modify: `src/Slop.ps1:210`, `:257-279`, `:1169-1172` (protected — no commit)
- Modify: `tests/slop-shell-check.ps1`
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Add assertions**

In `tests/slop-shell-check.ps1`, append before the `Describe` block:

```powershell
Assert-True ($src -match '\$script:WorkArea = \[System\.Windows\.SystemParameters\]::WorkArea') 'work area is cached in script scope'
Assert-True ($src -match '\$maxLeft = \[Math\]::Max\(\$wa\.X, \$wa\.Right - \$window\.ActualWidth\)') 'wander clamps against the work area'
Assert-True ($src -match '\$window\.Left = \[Math\]::Min\(\$maxLeft') 'wander writes the clamped left position'
```

- [ ] **Step 2: Run and verify the 3 new failures**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output Detailed"
```

- [ ] **Step 3: Cache and refresh the work area**

In `src/Slop.ps1`, replace line 210:

```powershell
$work = [System.Windows.SystemParameters]::WorkArea
```

with:

```powershell
$script:WorkArea = [System.Windows.SystemParameters]::WorkArea
```

In the `$window.Add_SizeChanged` handler, insert as the first statement after `param($s, $e)`:

```powershell
    $script:WorkArea = [System.Windows.SystemParameters]::WorkArea
```

- [ ] **Step 4: Clamp the wander write**

In `src/Slop.ps1`, replace lines 1169-1172:

```powershell
    # idle wander: nudge the window horizontally
    if ($script:Motion.Phase -eq 'wander' -and -not $script:Expanded) {
        $window.Left = $window.Left + ($script:Motion.WanderDx / 4.0) * $dt
    }
```

with:

```powershell
    # idle wander: nudge horizontally, but never off the visible work area
    if ($script:Motion.Phase -eq 'wander' -and -not $script:Expanded) {
        $wa = $script:WorkArea
        $maxLeft = [Math]::Max($wa.X, $wa.Right - $window.ActualWidth)
        $nextLeft = $window.Left + ($script:Motion.WanderDx / 4.0) * $dt
        $window.Left = [Math]::Min($maxLeft, [Math]::Max($wa.X, $nextLeft))
    }
```

- [ ] **Step 5: Verify**

Run the shell check from Step 2. Expected: all pass.

**No commit** — `src/Slop.ps1` is protected.

---

### Task 9: Documentation, tour anchors, and full verification

**Files:**
- Modify: `docs/architecture.md:260-266` (protected — no commit)
- Modify: `.tours/architect-slop-architecture.tour` (protected — no commit)
- Test: `tests/slop-tour-check.ps1`, full aggregate, `verify.ps1`, live verifier

- [ ] **Step 1: Reconcile tracked architecture wording**

In `docs/architecture.md`, replace lines 262-266:

```markdown
The observed event inventory, priority rules, and proposed state-to-signal table
are maintained in [the visual signal system](visual-signal-system.md). The frame
stroke is part of the animated color-brush collection; it follows the effective
signal color. The priority controller is implemented; the proposed palette and
motion refinements remain future work.
```

with:

```markdown
The observed event inventory, priority rules, and state-to-signal table are
maintained in [the visual signal system](visual-signal-system.md). The frame
stroke and rim highlight both follow the effective signal color, and the
rim highlight carries a state-tinted 0x55 alpha. The priority controller is
implemented: stalled resolves to amber, approval is a sticky priority-0 event
held until a decision, and success/error are timed events. Cyan/teal active
tokens and acknowledgement cards remain future work.
```

Then, in the "Other current visual behavior" list, append after the compact-pea bullet:

```markdown
- the ~12 decorative pixels are confined to a rounded 48x48 region around the
  compact pea or clipped to the membrane path when expanded, and follow the
  golden-angle `spiral` pattern while thinking or awaiting approval;
```

Do not modify or commit `docs/visual-signal-system.md`.

- [ ] **Step 2: Compute the new tour anchors**

Run this from the repo root to get the authoritative mapping after all source edits:

```powershell
$root = (Get-Location).Path
$tour = Get-Content (Join-Path $root '.tours/architect-slop-architecture.tour') -Raw | ConvertFrom-Json
$map = @{
  5  = @{ file='src/Slop.Motion.ps1'; text='function Get-SlopIdleAction' }
  11 = @{ file='src/Slop.ps1'; text='function Start-Stream' }
  12 = @{ file='src/Slop.ps1'; text='function Add-SlopApprovalCard' }
  13 = @{ file='src/Slop.ps1'; text='function Request-StopStream' }
  15 = @{ file='src/Slop.ps1'; text='function Expand-Chat' }
  16 = @{ file='src/Slop.ps1'; text='MotionTimer' }
  17 = @{ file='src/Slop.ps1'; text='function Apply-SlopMotion' }
}
foreach ($k in ($map.Keys | Sort-Object)) {
    $lines = @(Get-Content (Join-Path $root $map[$k].file))
    $hit = $null
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match [regex]::Escape($map[$k].text)) { $hit = $i + 1; break }
    }
    "step $k : $($tour.steps[$k-1].line) -> $hit  ($($map[$k].file))"
}
```

Expected: it prints seven `step N : old -> new` lines corresponding to the seven failures from the tour check.

- [ ] **Step 3: Apply the anchor refresh**

For each printed pair, edit `.tours/architect-slop-architecture.tour` and change the `"line": <old>` value in step `N` to `<new>`. Then refresh the inline line references inside step descriptions to match the final source (use `Select-String -Path src/Slop.ps1 -Pattern 'function Name'` to locate each). The known inline references to re-check are:

- step 3 description: `lines 6-12`, `lines 178-195`, `lines 282-305`;
- step 4 description: `New-SlopMotionState` (spring count and `Signal` block);
- step 5 description: `Update-SlopMotionState (line 281)`, `breathing (383)`, `sway (387)`, `forced-hop threshold (line 254)`;
- step 6 description: `Kick (line 89)`, `Poke (line 102)`, `Step (line 139)`;
- step 7 description: `Rr, line 209`, `loX/hiX, line 216`, `Step (line 157)`, `ContentOpacity (line 280)`, `Slop.Silhouette.ps1 (line 9)`;
- step 8 description: `Update-SlopFaceLayer (line 39)` — now also mention the 48x48 region clip and `spiral`.

Keep all four doc-drift assertions in `tests/slop-tour-check.ps1:68-71` true: do not change step 2's description to call the modules "pure math/state", keep `48-point`/`N=48` in step 6, keep "not used at runtime" in step 7.

- [ ] **Step 4: Run the tour check**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-tour-check.ps1' -CI -Output Detailed"
```

Expected: `Tests Failed: 0`.

- [ ] **Step 5: Full gates**

Run each and read the output:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output Detailed"
```

Expected: `Tests Failed: 0`, passed count at least 369.

```powershell
pwsh -NoProfile -File verify.ps1
```

Expected: all gates pass, exit 0.

```powershell
pwsh -NoProfile -File tools/verify-motion.ps1
```

Expected: exit 0, with amber observed for thinking/approval and no orphaned app process.

- [ ] **Step 6: Report the uncommitted set; do not commit it**

Run:

```powershell
git status --short
```

Report verbatim. Expected still-modified/untracked: `src/Slop.ps1`, `src/Slop.Motion.ps1`, `tests/slop-motion-check.ps1`, `docs/architecture.md`, `.tours/architect-slop-architecture.tour`, plus the user's pre-existing untracked docs and `testResults.xml`. Ask before staging or committing any of them.

---

## Risks and checkpoints

- **Event priority is global.** Approval (0) intentionally outranks error (1) and stalled (2). Task 1's assertions lock that in; do not "fix" it by reordering priorities.
- **Expanded clip follows geometry.** `BodyPath.Data` is only rebuilt while the membrane is open, so `Update-SlopFaceRegion` must be called every tick; a one-shot clip at `Expand-Chat` would freeze particles to the pea-sized blob.
- **Null clip.** If `BodyPath.Data` is null while collapsed, keep the previous clip rather than assigning null.
- **Single opacity writer.** `HeadHighlight.Opacity` must remain written in exactly one place; Task 6 asserts this.
- **Stale anchors.** Every source edit shifts tour lines. Task 9 is last for a reason; do not move it earlier.
- **Protected files.** If a commit command would include any protected file, stop and report instead of proceeding.

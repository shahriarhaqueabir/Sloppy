# S.L.O.P. Motion Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Slop's idle pea, state feedback, chat frame, and stream entrance feel springy and fluid without changing a single visual element.

**Architecture:** Extract pure spring/hop math into a WPF-free PowerShell module (`src/Slop.Motion.ps1`) that can be checked headlessly. `src/Slop.ps1` dot-sources it and uses one `DispatcherTimer` to integrate fixed 1/120 s substeps, then writes transforms/opacity onto the existing XAML elements. No new visual elements, colors, or renderer.

**Tech Stack:** PowerShell 7, WPF (`PresentationFramework` / `WindowsBase`), embedded C# for spring math, headless assertion script for verification.

**Commit convention:** Steps include `git commit`. Leave changes uncommitted if the user says to keep WIP.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/Slop.Motion.ps1` | Pure motion math: `SlopSpring` C# type, spring factory/step, `New-SlopMotionState`, `Update-SlopMotionState`, `Set-SlopMotionMood`, `Set-SlopFrameTarget`, reduced-motion probe. **No WPF types.** |
| `src/Slop.ps1` | WPF app. Dot-sources motion module; owns one motion timer and `Apply-SlopMotion` which writes transforms/opacity to existing elements. |
| `tests/slop-motion-check.ps1` | Framework-free headless assertions for the motion math (no Pester dependency; full Pester suite remains a follow-up per spec). |
| `tools/verify-motion.ps1` | Live WPF verification: launch, pixel sampling, click/stream/Esc/drag, clean logs. |

---

### Task 1: Write failing headless motion checks

**Files:**
- Create: `tests/slop-motion-check.ps1`

- [ ] **Step 1: Create the check script**

```powershell
# Headless checks for S.L.O.P. motion math. No WPF, no Pester.
$ErrorActionPreference = 'Stop'
$motion = Join-Path $PSScriptRoot '../src/Slop.Motion.ps1'
if (-not (Test-Path $motion)) { throw "missing motion module: $motion" }
. $motion

$script:failures = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { "PASS: $Message" } else { "FAIL: $Message"; $script:failures++ }
}

# 1. spring factory + convergence
$s = New-SlopSpring 0.0 160 20
Assert-True ($s.Value -eq 0.0 -and $s.Target -eq 0.0 -and $s.Velocity -eq 0.0) 'spring starts settled'
$s.Target = 1.0
for ($i = 0; $i -lt 240; $i++) { Step-SlopSpring $s (1.0 / 120.0) }
Assert-True ([Math]::Abs($s.Value - 1.0) -lt 0.01) "spring converges to target (value=$([Math]::Round($s.Value,4)))"

# 2. hop cycle completes and returns to ground
$m = New-SlopMotionState
$m.NextHopIn = -0.01
$sawAir = $false; $sawSquat = $false; $sawCrossfade = $false; $endY = 99.0
for ($i = 0; $i -lt 480; $i++) {
    Update-SlopMotionState -State $m -Dt (1.0 / 120.0)
    if ($m.Phase -eq 'airborne') { $sawAir = $true }
    if ($m.Squash.Value -lt 0.9) { $sawSquat = $true }
    if ($m.Phase -eq 'airborne' -and ($m.Weights | Where-Object { $_.Value -gt 0.02 }).Count -ge 2) { $sawCrossfade = $true }
    $endY = $m.Y
}
Assert-True $sawSquat 'hop has anticipation squash'
Assert-True $sawAir 'hop has airborne phase'
Assert-True ($m.HopCount -ge 1) "hop count advances (count=$($m.HopCount))"
Assert-True ([Math]::Abs($endY) -lt 0.5) "blob lands back at ground (y=$([Math]::Round($endY,3)))"
Assert-True $sawCrossfade 'shape weights crossfade during hop'

# 3. exactly one shape wins after settling
$live = @($m.Weights | Where-Object { $_.Value -gt 0.9 })
Assert-True ($live.Count -eq 1) "one shape dominates after morph (live=$($live.Count))"

# 4. mood pulse decays
Set-SlopMotionMood -State $m -Mood 'error'
Assert-True ($m.MoodPulse.Value -eq 1.0) 'error mood starts a pulse'
for ($i = 0; $i -lt 240; $i++) { Update-SlopMotionState -State $m -Dt (1.0 / 120.0) }
Assert-True ([Math]::Abs($m.MoodPulse.Value) -lt 0.05) "mood pulse decays (value=$([Math]::Round($m.MoodPulse.Value,4)))"

# 5. frame targets flip
Set-SlopFrameTarget -State $m -Target 'open'
Assert-True ($m.FrameAlpha.Target -eq 1.0 -and $m.FrameScale.Target -eq 1.0) 'open targets'
Set-SlopFrameTarget -State $m -Target 'closed'
Assert-True ($m.FrameAlpha.Target -eq 0.0 -and $m.FrameScale.Target -lt 1.0) 'closed targets'

# 6. reduced motion snaps instead of animating
$r = New-SlopMotionState
$r.NextHopIn = -0.01
Update-SlopMotionState -State $r -Dt (1.0 / 120.0) -ReducedMotion
Assert-True ($r.Y -eq 0.0 -and $r.Squash.Value -eq $r.Squash.Target) 'reduced motion snaps springs'

if ($script:failures -gt 0) { throw "$($script:failures) motion check(s) failed" }
'ALL MOTION CHECKS PASSED'
```

- [ ] **Step 2: Run checks to verify they fail**

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: FAIL with `missing motion module: ...src/Slop.Motion.ps1`

- [ ] **Step 3: Commit the failing checks**

```bash
git add tests/slop-motion-check.ps1
git commit -m "test: add headless checks for slop motion math"
```

---

### Task 2: Implement the pure motion math module

**Files:**
- Create: `src/Slop.Motion.ps1`

- [ ] **Step 1: Create the module**

```powershell
# S.L.O.P. motion math. Pure math only - no WPF types, safe to dot-source headlessly.
$ErrorActionPreference = 'Stop'

if (-not ('SlopSpring' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
public sealed class SlopSpring
{
    public double Value;
    public double Velocity;
    public double Target;
    public double Stiffness = 160.0;
    public double Damping = 20.0;

    public SlopSpring() { }
    public SlopSpring(double value) { Value = value; Target = value; }

    public void Step(double dt)
    {
        double accel = (Target - Value) * Stiffness - Velocity * Damping;
        Velocity += accel * dt;
        Value += Velocity * dt;
    }

    public void Snap(double value)
    {
        Value = value;
        Target = value;
        Velocity = 0.0;
    }
}
'@
}

function New-SlopSpring {
    param(
        [double]$Value = 0.0,
        [double]$Stiffness = 160.0,
        [double]$Damping = 20.0
    )
    $s = [SlopSpring]::new()
    $s.Snap($Value)
    $s.Stiffness = $Stiffness
    $s.Damping = $Damping
    return $s
}

function Step-SlopSpring {
    param(
        [Parameter(Mandatory)][SlopSpring]$Spring,
        [Parameter(Mandatory)][double]$Dt
    )
    $Spring.Step($Dt)
    return $Spring.Value
}

function New-SlopMotionState {
    return @{
        Squash      = New-SlopSpring 1.0 150 18   # ScaleY; ScaleX is its inverse
        Lean        = New-SlopSpring 0.0 90 14    # degrees
        Puff        = New-SlopSpring 1.0 120 16   # breathing / success pulse
        Wobble      = New-SlopSpring 0.0 210 12   # landing jelly
        ShadowScale = New-SlopSpring 1.0 160 18
        ShadowAlpha = New-SlopSpring 0.40 140 18
        FrameScale  = New-SlopSpring 1.0 190 19
        FrameAlpha  = New-SlopSpring 0.0 260 28
        MoodPulse   = New-SlopSpring 0.0 170 13
        Weights     = @(
            New-SlopSpring 1.0 110 17
            New-SlopSpring 0.0 110 17
            New-SlopSpring 0.0 110 17
            New-SlopSpring 0.0 110 17
        )
        Phase       = 'idle'   # idle | anticipate | airborne | land
        PhaseTime   = 0.0
        NextHopIn   = 1.6
        Y           = 0.0
        VY          = 0.0
        HopCount    = 0
        TargetShape = 0
        Mood        = 'idle'
    }
}

function Set-SlopMotionMood {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [ValidateSet('idle','thinking','success','error')][string]$Mood
    )
    $State.Mood = $Mood
    if ($Mood -in @('success','error')) {
        $State.MoodPulse.Value = 1.0
        $State.MoodPulse.Velocity = 0.0
        $State.MoodPulse.Target = 0.0
    }
    else {
        $State.MoodPulse.Snap(0.0)
    }
}

function Set-SlopFrameTarget {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [ValidateSet('open','closed')][string]$Target
    )
    if ($Target -eq 'open') {
        $State.FrameAlpha.Target = 1.0
        $State.FrameScale.Target = 1.0
    }
    else {
        $State.FrameAlpha.Target = 0.0
        $State.FrameScale.Target = 0.94
    }
}

function Update-SlopMotionState {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][double]$Dt,
        [switch]$ReducedMotion
    )

    $allSprings = @(
        $State.Squash, $State.Lean, $State.Puff, $State.Wobble,
        $State.ShadowScale, $State.ShadowAlpha,
        $State.FrameScale, $State.FrameAlpha, $State.MoodPulse
    )
    $t = [DateTime]::UtcNow.Ticks / 10000000.0

    if ($ReducedMotion) {
        foreach ($s in $allSprings) { $s.Snap($s.Target) }
        foreach ($w in $State.Weights) { $w.Snap($w.Target) }
        $State.Y = 0.0
        $State.VY = 0.0
        return
    }

    $State.PhaseTime += $Dt
    $State.NextHopIn -= $Dt

    switch ($State.Phase) {
        'idle' {
            $State.Squash.Target = 1.0
            if ($State.Mood -eq 'thinking') {
                $State.Lean.Target = 3.5 * [Math]::Sin($t * 6.2)
                $State.Wobble.Target = 0.045 * [Math]::Sin($t * 9.1)
            }
            else {
                $State.Lean.Target = 0.0
            }
            if ($State.NextHopIn -le 0) {
                $State.Phase = 'anticipate'
                $State.PhaseTime = 0.0
                $State.Squash.Target = 0.80
                $State.ShadowScale.Target = 0.82
            }
        }
        'anticipate' {
            if ($State.PhaseTime -ge 0.12) {
                $State.Phase = 'airborne'
                $State.PhaseTime = 0.0
                $State.Y = 0.0
                $State.VY = -165.0
                $State.TargetShape = ($State.TargetShape + 1 + (Get-Random -Maximum 3)) % 4
                for ($i = 0; $i -lt 4; $i++) {
                    $State.Weights[$i].Target = if ($i -eq $State.TargetShape) { 1.0 } else { 0.0 }
                }
            }
        }
        'airborne' {
            $State.VY += 620.0 * $Dt
            $State.Y += $State.VY * $Dt
            if ($State.Y -ge 0 -and $State.VY -gt 0) {
                $State.Y = 0.0
                $State.Phase = 'land'
                $State.PhaseTime = 0.0
                $State.Squash.Target = 0.76
                $State.Wobble.Target = 0.14
                $State.ShadowScale.Target = 1.16
                $State.ShadowAlpha.Target = 0.55
                if ($State.Mood -ne 'thinking') { $State.Lean.Target = 0.0 }
            }
        }
        'land' {
            if ($State.PhaseTime -ge 0.10) {
                $State.Phase = 'idle'
                $State.PhaseTime = 0.0
                $State.Squash.Target = 1.0
                $State.Wobble.Target = 0.0
                $State.ShadowScale.Target = 1.0
                $State.ShadowAlpha.Target = 0.40
                $State.NextHopIn = [Math]::Max(1.4, 2.4 + (Get-Random -Minimum (-60) -Maximum 140) / 100.0)
                $State.HopCount++
            }
        }
    }

    if ($State.Phase -eq 'idle' -and $State.Mood -ne 'thinking') {
        $State.Puff.Target = 1.0 + 0.018 * [Math]::Sin($t * 2.1)
    }
    else {
        $State.Puff.Target = 1.0
    }

    if ($State.Mood -eq 'error') {
        $State.Lean.Target = 7.0 * $State.MoodPulse.Value * [Math]::Sin($t * 42.0)
    }
    elseif ($State.Mood -eq 'success') {
        $State.Puff.Target += 0.10 * $State.MoodPulse.Value
    }

    foreach ($s in $allSprings) { $s.Step($Dt) }
    foreach ($w in $State.Weights) { $w.Step($Dt) }
}

function Test-SlopClientAreaAnimation {
    if (-not ('SlopNativeMotion' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SlopNativeMotion
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, out bool value, uint flags);
}
'@
    }
    $enabled = $false
    [SlopNativeMotion]::SystemParametersInfo(0x1042, 0, [ref]$enabled, 0) | Out-Null
    return $enabled
}
```

- [ ] **Step 2: Run the headless checks**

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: all lines `PASS: ...` and final `ALL MOTION CHECKS PASSED`, exit code 0.

- [ ] **Step 3: Commit the module**

```bash
git add src/Slop.Motion.ps1
git commit -m "feat: add pure spring motion math for slop"
```

---

### Task 3: Wire the motion engine into the WPF app

**Files:**
- Modify: `src/Slop.ps1:19` (dot-source), `src/Slop.ps1:99` (name shadow), `src/Slop.ps1:119` (find shadow), `src/Slop.ps1:158-182` (replace morph helpers), `src/Slop.ps1:398-402` (replace morph timer), `src/Slop.ps1:406-410` (cleanup).

- [ ] **Step 1: Dot-source the module and name the ground shadow**

Replace line 19:

```powershell
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
. (Join-Path $PSScriptRoot 'Slop.Motion.ps1')
```

Replace line 99:

```xml
    <Ellipse x:Name="GroundShadow" Width="30" Height="8" Canvas.Left="145" Canvas.Top="434" Fill="#000" Opacity="0.4" IsHitTestVisible="False">
```

Add after line 119:

```powershell
$GroundShadow = $window.FindName('GroundShadow')
```

- [ ] **Step 2: Replace `Get-ShapeScale` / `Morph-Shape` with render helpers**

Replace lines 158-182 with:

```powershell
function Get-ShapeTransform {
    param($shape)
    $g = $shape.RenderTransform -as [System.Windows.Media.TransformGroup]
    if (-not $g) {
        $g = [System.Windows.Media.TransformGroup]::new()
        $g.Children.Add([System.Windows.Media.ScaleTransform]::new(1,1)) | Out-Null
        $g.Children.Add([System.Windows.Media.RotateTransform]::new(0)) | Out-Null
        $shape.RenderTransform = $g
        $shape.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    }
    return $g
}

function Initialize-MotionVisuals {
    $Frame.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $Frame.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1,1)
    $GroundShadow.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $GroundShadow.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1,1)
    $PeaCanvas.RenderTransform = [System.Windows.Media.TranslateTransform]::new(0,0)
}

function Apply-SlopMotion {
    $m = $script:Motion
    $sx = 1.0 / [Math]::Max(0.4, $m.Squash.Value)
    $sy = $m.Squash.Value + $m.Wobble.Value
    $angle = $m.Lean.Value

    for ($i = 0; $i -lt 4; $i++) {
        $shape = $script:Shapes[$i]
        $w = [Math]::Min(1.0, [Math]::Max(0.0, $m.Weights[$i].Value))
        $shape.Opacity = $w
        $shape.Visibility = if ($w -gt 0.01) { 'Visible' } else { 'Collapsed' }
        $g = Get-ShapeTransform $shape
        $g.Children[0].ScaleX = $sx * $m.Puff.Value
        $g.Children[0].ScaleY = $sy * $m.Puff.Value
        $g.Children[1].Angle = $angle
    }

    $x = 1.6 * [Math]::Sin([DateTime]::UtcNow.Ticks / 10000000.0 * 0.9)
    $PeaCanvas.RenderTransform = [System.Windows.Media.TranslateTransform]::new($x, $m.Y)

    $GroundShadow.RenderTransform = [System.Windows.Media.ScaleTransform]::new($m.ShadowScale.Value, 1.0)
    $GroundShadow.Opacity = $m.ShadowAlpha.Value

    $Frame.Opacity = [Math]::Min(1.0, [Math]::Max(0.0, $m.FrameAlpha.Value))
    $Frame.RenderTransform = [System.Windows.Media.ScaleTransform]::new($m.FrameScale.Value, $m.FrameScale.Value)

    if (-not $script:Expanded -and $m.FrameAlpha.Value -lt 0.05) {
        $Frame.Visibility = 'Collapsed'
        $PeaCanvas.Visibility = 'Visible'
    }

    foreach ($child in $ChatStack.Children) {
        $tag = $child.Tag
        if ($tag -is [hashtable] -and $tag.ContainsKey('SlopEntrance')) {
            $child.Opacity = [Math]::Min(1.0, [Math]::Max(0.0, $tag.SlopEntrance.Value))
            $tag.SlopTransform.Y = $tag.SlopLift.Value
        }
    }
    if ($script:StreamTextSpring) {
        $script:CurrentAssistantBlock.Child.Opacity = [Math]::Min(1.0, [Math]::Max(0.0, $script:StreamTextSpring.Value))
    }
}
```

- [ ] **Step 3: Replace the idle morph timer with the motion timer**

Replace lines 398-402 with:

```powershell
# single dispatcher-owned motion clock: ~30 fps render, fixed 1/120 s physics substeps
$script:Motion = New-SlopMotionState
$script:ReducedMotion = -not (Test-SlopClientAreaAnimation)
$script:MotionAccumulator = 0.0
$script:LastMotionTick = [DateTime]::UtcNow
Set-SlopFrameTarget -State $script:Motion -Target 'closed'
Initialize-MotionVisuals

$script:MotionTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:MotionTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$script:MotionTimer.Add_Tick({
    $now = [DateTime]::UtcNow
    $dt = ($now - $script:LastMotionTick).TotalSeconds
    $script:LastMotionTick = $now
    if ($dt -gt 0.25) { $dt = 0.25 }
    $script:MotionAccumulator += $dt
    $step = 1.0 / 120.0
    while ($script:MotionAccumulator -ge $step) {
        Update-SlopMotionState -State $script:Motion -Dt $step -ReducedMotion:$script:ReducedMotion
        foreach ($child in $ChatStack.Children) {
            $tag = $child.Tag
            if ($tag -is [hashtable] -and $tag.ContainsKey('SlopEntrance')) {
                $tag.SlopEntrance.Step($step)
                $tag.SlopLift.Step($step)
            }
        }
        if ($script:StreamTextSpring) { $script:StreamTextSpring.Step($step) }
        $script:MotionAccumulator -= $step
    }
    Apply-SlopMotion
})
$script:MotionTimer.Start()
```

- [ ] **Step 4: Update cleanup**

Replace lines 406-410 with:

```powershell
$window.Add_Closed({
    if ($script:Timer) { $script:Timer.Stop() }
    if ($script:MotionTimer) { $script:MotionTimer.Stop() }
    if ($script:Cts) { $script:Cts.Cancel() }
})
```

- [ ] **Step 5: Parser check and live idle check**

Run:

```powershell
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile('.\src\Slop.ps1',[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){$errors|ForEach-Object{"$($_.Extent.StartLineNumber): $($_.Message)"};exit 1}
'Parser errors: 0'
```

Expected: `Parser errors: 0`.

Then launch the app and confirm the pea still has blue pixels in the `(138,400)-(182,444)` logical region and app logs are empty. The full live harness is created in Task 5.

- [ ] **Step 6: Commit**

```bash
git add src/Slop.ps1
git commit -m "feat: drive slop transforms from one spring clock"
```

---

### Task 4: Mood, frame, bubble, and stream motion

**Files:**
- Modify: `src/Slop.ps1:150-156` (`Set-ShapeColor` → `Set-SlopMood`), `src/Slop.ps1:184-200` (expand/collapse targets), `src/Slop.ps1:259-283` (bubble entrance), `src/Slop.ps1:285-304` (stream state), `src/Slop.ps1:349-378` (drain opacity ramp), `src/Slop.ps1:213-223` (finish reset).

- [ ] **Step 1: Replace color setter with mood setter**

Replace lines 150-156 with:

```powershell
function Set-SlopMood {
    param([ValidateSet('idle','thinking','success','error')][string]$Mood)
    $color = switch ($Mood) {
        'thinking' { '#F59E0B' }
        'success'  { '#22C55E' }
        'error'    { '#EF4444' }
        default    { '#3B82F6' }
    }
    $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    foreach ($s in $script:Shapes) { $s.Fill = $brush }
    $StatusDot.Fill = $brush
    $Frame.BorderBrush = $brush
    Set-SlopMotionMood -State $script:Motion -Mood $Mood
}
```

Then replace call sites:

- line 295 `Set-ShapeColor '#F59E0B'` → `Set-SlopMood 'thinking'`
- line 359 `Set-ShapeColor '#EF4444'` → `Set-SlopMood 'error'`
- line 366 `Set-ShapeColor '#22C55E'` → `Set-SlopMood 'success'`
- line 404 `Set-ShapeColor '#3B82F6'` → `Set-SlopMood 'idle'` — **move this line to after the motion state is created in Task 3** (place it immediately after `Set-SlopFrameTarget -State $script:Motion -Target 'closed'`), otherwise `$script:Motion` is null.

- [ ] **Step 2: Drive frame open/close through spring targets**

Replace lines 184-200 with:

```powershell
function Expand-Chat {
    if ($script:Expanded) { return }
    $script:Expanded = $true
    $PeaCanvas.Visibility = 'Collapsed'
    $Frame.Visibility = 'Visible'
    $Frame.Opacity = 0
    Set-SlopFrameTarget -State $script:Motion -Target 'open'
    $InputBox.Focus() | Out-Null
}

function Collapse-Chat {
    if (-not $script:Expanded) { return }
    $script:Expanded = $false
    Set-SlopFrameTarget -State $script:Motion -Target 'closed'
}
```

- [ ] **Step 3: Add staggered bubble entrance**

Add immediately after `$ChatStack.Children.Add($border) | Out-Null` (line 280):

```powershell
if (-not $script:ReducedMotion) {
    $tt = [System.Windows.Media.TranslateTransform]::new(0,6)
    $border.Opacity = 0
    $border.RenderTransform = $tt
    $alpha = New-SlopSpring 0.0 220 22
    $lift = New-SlopSpring 6.0 200 22
    $alpha.Target = 1.0
    $lift.Target = 0.0
    $border.Tag = @{ SlopEntrance = $alpha; SlopLift = $lift; SlopTransform = $tt }
}
```

- [ ] **Step 4: Reset stream opacity spring on finish**

Add after line 220 (`$script:IsStreaming = $false`):

```powershell
    $script:StreamTextSpring = $null
```

- [ ] **Step 5: Add stream text opacity ramp**

Add after line 291 (`$script:CurrentAssistantText = ''`):

```powershell
    $script:StreamTextSpring = $null
```

Add inside the drain timer, immediately before `$tb.Text = $script:CurrentAssistantText` (line 373):

```powershell
            if (-not $script:StreamTextSpring) {
                $script:StreamTextSpring = New-SlopSpring 0.70 240 24
                $script:StreamTextSpring.Target = 1.0
            }
```

- [ ] **Step 6: Parser + headless checks**

Run the parser command from Task 3 Step 5, then:

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: `ALL MOTION CHECKS PASSED`.

- [ ] **Step 7: Commit**

```bash
git add src/Slop.ps1
git commit -m "feat: spring-drive moods, frame, bubbles and stream reveal"
```

---

### Task 5: Final live verification script and review gate

**Files:**
- Create: `tools/verify-motion.ps1`

- [ ] **Step 1: Create the live verification script**

```powershell
# Live WPF verification for the S.L.O.P. motion overlay.
# Focus-checked physical input only - no SendKeys leakage into other apps.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VM {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,int e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte scan,uint flags,int extra);
    public const uint DOWN=0x0002, UP=0x0004, KEYUP=0x0002;
    public const byte CTRL=0x11, V=0x56, ENTER=0x0D, ESC=0x1B;
}
'@

function Get-Win($id) {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $id)
    $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
}
function Phys($lx,$ly) {
    $r = $script:W.Current.BoundingRectangle
    $s = $r.Width / 320.0
    @([int]($r.X + $lx*$s), [int]($r.Y + $ly*$s))
}
function Focus-Ok {
    $h = [IntPtr]$script:W.Current.NativeWindowHandle
    [VM]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 120
    [VM]::GetForegroundWindow() -eq $h
}
function Click($lx,$ly) {
    $p = Phys $lx $ly
    [VM]::SetCursorPos($p[0],$p[1]) | Out-Null
    Start-Sleep -Milliseconds 60
    [VM]::mouse_event([VM]::DOWN,0,0,0,0)
    Start-Sleep -Milliseconds 45
    [VM]::mouse_event([VM]::UP,0,0,0,0)
}
function Grab {
    $r = $script:W.Current.BoundingRectangle
    $b = [System.Drawing.Bitmap]::new([int]$r.Width,[int]$r.Height)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen([int]$r.X,[int]$r.Y,0,0,$b.Size)
    $g.Dispose()
    $b
}
function Count($b,$lx,$ly,$lw,$lh,$mode) {
    $r = $script:W.Current.BoundingRectangle
    $s = $r.Width / 320.0
    $rect = [System.Drawing.Rectangle]::new([int]($lx*$s),[int]($ly*$s),[int]($lw*$s),[int]($lh*$s))
    $d = $b.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,$b.PixelFormat)
    $bytes = [byte[]]::new($d.Stride*$rect.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0,$bytes,0,$bytes.Length)
    $b.UnlockBits($d)
    $n = 0
    for ($y=0;$y -lt $rect.Height;$y++) {
        $idx = $y*$d.Stride
        for ($x=0;$x -lt $rect.Width;$x++) {
            $rr=$bytes[$idx+2]; $gg=$bytes[$idx+1]; $bb=$bytes[$idx]
            if     ($mode -eq 'blue'   -and $bb -gt 180 -and $rr -lt 120 -and $gg -lt 180) { $n++ }
            elseif ($mode -eq 'amber'  -and $rr -gt 200 -and $gg -gt 100 -and $gg -lt 190 -and $bb -lt 110) { $n++ }
            elseif ($mode -eq 'bright' -and $rr -gt 120 -and $gg -gt 120 -and $bb -gt 120) { $n++ }
            $idx += 4
        }
    }
    $n
}
function Pixel($b,$lx,$ly) {
    $r = $script:W.Current.BoundingRectangle
    $b.GetPixel([int]($lx*$r.Width/320.0),[int]($ly*$r.Height/460.0))
}
function Press($vk) {
    [VM]::keybd_event($vk,0,0,0)
    [VM]::keybd_event($vk,0,[VM]::KEYUP,0)
}
function Paste($text) {
    [System.Windows.Forms.Clipboard]::SetText($text)
    [VM]::keybd_event([VM]::CTRL,0,0,0)
    [VM]::keybd_event([VM]::V,0,0,0)
    [VM]::keybd_event([VM]::V,0,[VM]::KEYUP,0)
    [VM]::keybd_event([VM]::CTRL,0,[VM]::KEYUP,0)
}

$dir = Join-Path (Get-Location) '../tmp/slop-verify'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'slop.out.log'
$err = Join-Path $dir 'slop.err.log'
Remove-Item $out,$err -ErrorAction SilentlyContinue
$scriptFile = Join-Path (Get-Location) 'src/Slop.ps1'
$proc = Start-Process -FilePath 'pwsh' `
    -ArgumentList @('-STA','-NoProfile','-File',$scriptFile) `
    -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
Start-Sleep -Seconds 3
if ($proc.HasExited) { throw "app exited early: $(Get-Content $out -Raw) $(Get-Content $err -Raw)" }
$script:W = Get-Win $proc.Id
$r = $script:W.Current.BoundingRectangle
"LAUNCH pid=$($proc.Id) rect=$([int]$r.X),$([int]$r.Y) $([int]$r.Width)x$([int]$r.Height)"

# idle motion: sample blue pixel count over 2 seconds and prove variance
$counts = @()
for ($i=0;$i -lt 12;$i++) {
    $b = Grab
    $counts += Count $b 138 400 44 44 'blue'
    $b.Dispose()
    Start-Sleep -Milliseconds 160
}
"IDLE blueSamples=$($counts -join ',') distinct=$(@($counts | Select-Object -Unique).Count)"
if ($counts[-1] -le 0) { throw 'no blue pea pixels' }

# expand
$expanded = $false
for ($try=1;$try -le 3 -and -not $expanded;$try++) {
    Focus-Ok | Out-Null
    Click 160 423
    Start-Sleep -Milliseconds 600
    $b = Grab; $p = Pixel $b 160 200; $b.Dispose()
    if ($p.R -lt 60 -and $p.G -lt 80 -and $p.B -gt 30) { $expanded = $true; "EXPAND panel=$($p.R),$($p.G),$($p.B)" }
}
if (-not $expanded) { throw 'click never expanded chat' }

# send + streaming
if (-not (Focus-Ok)) { throw 'focus failed before typing' }
Click 100 407
Paste 'hi'
Press ([VM]::ENTER)
$changes = 0; $last = ''
for ($i=0;$i -lt 80;$i++) {
    Start-Sleep -Milliseconds 150
    $b = Grab
    $k = "$(Count $b 10 46 300 338 'bright')"
    $b.Dispose()
    if ($k -ne $last) { $changes++; $last = $k }
    if ($changes -ge 3) { break }
}
"STREAM changes=$changes"

# Esc collapse + drag
if (-not (Focus-Ok)) { throw 'focus failed before ESC' }
Press ([VM]::ESC)
Start-Sleep -Milliseconds 700
$b = Grab; $p2 = Pixel $b 160 200; "ESC panel=$($p2.R),$($p2.G),$($p2.B)"; $b.Dispose()

$before = $script:W.Current.BoundingRectangle
$a = Phys 160 423; $z = Phys 100 403
[VM]::SetCursorPos($a[0],$a[1]) | Out-Null
Start-Sleep -Milliseconds 70
[VM]::mouse_event([VM]::DOWN,0,0,0,0)
for ($i=1;$i -le 8;$i++) {
    [VM]::SetCursorPos([int]($a[0]+($z[0]-$a[0])*$i/8),[int]($a[1]+($z[1]-$a[1])*$i/8)) | Out-Null
    Start-Sleep -Milliseconds 25
}
[VM]::mouse_event([VM]::UP,0,0,0,0)
Start-Sleep -Milliseconds 400
$after = $script:W.Current.BoundingRectangle
"DRAG moved=$([int]($after.X-$before.X)),$([int]($after.Y-$before.Y))"

"APP OUT: $(Get-Content $out -Raw -ErrorAction SilentlyContinue)"
"APP ERR: $(Get-Content $err -Raw -ErrorAction SilentlyContinue)"
"FINAL_PID=$($proc.Id)"
```

The script uses clipboard paste + physical key events only after `Focus-Ok` succeeds. The prior session's leaking `blue test` input came from unfocused `SendKeys`; this script deliberately never uses `SendKeys`.

- [ ] **Step 2: Run parser, headless checks, and live verification**

Run:

```powershell
pwsh -NoProfile -File tests/slop-motion-check.ps1
pwsh -STA -NoProfile -File tools/verify-motion.ps1
pwsh -NoProfile -File '<agent-home>/scripts/review.ps1'
```

Expected:
- `ALL MOTION CHECKS PASSED`
- `IDLE blueSamples=... distinct=2` or more (motion variance), `EXPAND panel=` dark blue, `STREAM changes=3` or more, `ESC panel=10,10,10`, `DRAG moved=-66,-22` or similar, empty `APP OUT` / `APP ERR`
- Review gate: no TODO/FIXME introduced

- [ ] **Step 3: Commit**

```bash
git add tools/verify-motion.ps1
git commit -m "test: add live motion verification harness"
```

---

## Self-Review

**Spec coverage:** architecture → Task 2/3; idle breathing/wander/hop/morph/shadow → Task 2/3; moods → Task 4; frame/bubble/stream → Task 4; reduced motion → Task 2/3; verification → Task 5. No gaps.

**Placeholder scan:** no TBD/TODO; every code step has full code and exact commands.

**Type consistency:** `New-SlopSpring`, `Step-SlopSpring`, `New-SlopMotionState`, `Update-SlopMotionState`, `Set-SlopMotionMood`, `Set-SlopFrameTarget`, `Test-SlopClientAreaAnimation` are defined in Task 2 and used with the same names/signatures in Tasks 3-5. `Set-SlopMood` (UI color wrapper) is distinct from `Set-SlopMotionMood` (state only).


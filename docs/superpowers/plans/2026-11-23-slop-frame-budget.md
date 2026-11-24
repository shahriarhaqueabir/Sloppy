# Slop Frame Budget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> the user's standing constraint overrides the recommended option: **no subagents**. Execute inline with `executing-plans`, one task at a time.

**Goal:** Cut Slop's idle CPU by adaptive ticking, in-place transforms, collapsed-state work skipping, and work-area-sized large mode, with a committed harness that proves the change.

**Architecture:** Cadence policy lives in pure functions in `src/Slop.Motion.ps1`; the WPF shell only applies the returned interval. `Initialize-MotionVisuals` caches transforms once and `Apply-SlopMotion` mutates them. `SlopFrame.IsClosed` gates membrane physics and geometry parsing. `SettingsDot` switches between a remembered rect and `SystemParameters.WorkArea` instead of toggling `WindowState`.

**Tech Stack:** PowerShell 7.6, WPF `DispatcherTimer`/`TranslateTransform`/`ScaleTransform`, Pester 6, C# `SlopFrame` geometry engine, UIA live verifier.

**Source of truth:** `docs/superpowers/specs/2026-11-23-slop-frame-budget-design.md`. Baseline: `docs/performance/baseline-2026-11-23.md`.

**Never commit (the user's uncommitted work):** `src/Slop.ps1` header/param cleanup, `.memory/topics/companion-life-and-system-sense.md`, `docs/superpowers/specs/2026-11-23-sloppy-gui-refinement-design.md`, `docs/superpowers/plans/2026-11-23-sloppy-gui-refinement.md`. Use `git add <specific files>` in every commit. `src/Slop.ps1` is modified on entry — the tasks below edit only the motion/settings/timer regions and must not stage unrelated hunks. If a hunk outside those regions appears in `git diff`, use `git add -p` and stage only the intended hunks.

**Pester command convention:** all RED/GREEN checks use `Invoke-Pester -CI` so a failure produces exit code 1. Dot-sourcing `tests/Slop.Tests.ps1` picks up any new `tests/*-check.ps1` automatically; do not edit the aggregator.

---

### Task 1: Pure cadence helpers and headless tests

**Files:**
- Modify: `src/Slop.Motion.ps1` (append after `Test-SlopClientAreaAnimation`, currently line 426)
- Create: `tests/slop-motion-cadence-check.ps1`

- [ ] **Step 1: Write the failing test file**

Create `tests/slop-motion-cadence-check.ps1` with exactly this content:

```powershell
# Headless checks for adaptive Slop motion cadence. No WPF; Pester-backed.
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
$motion = Join-Path $PSScriptRoot '../src/Slop.Motion.ps1'
if (-not (Test-Path $motion)) { throw "missing motion module: $motion" }
. $motion

$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
}

# Return -1 while the helper is missing so the RED run is a clean assertion
# failure rather than a terminating CommandNotFoundException.
function Invoke-Cadence {
    param([hashtable]$State, [switch]$WindowMoving, [switch]$Large)
    if (-not (Get-Command Get-SlopMotionIntervalMs -ErrorAction SilentlyContinue)) { return -1 }
    return Get-SlopMotionIntervalMs -State $State -WindowMoving:$WindowMoving -Large:$Large
}
function Check-Cadence {
    param([string]$Name, [int]$Expected, [hashtable]$State, [switch]$WindowMoving, [switch]$Large)
    $actual = Invoke-Cadence -State $State -WindowMoving:$WindowMoving -Large:$Large
    Assert-True ($actual -eq $Expected) "$Name => $Expected ms (got $actual)"
}

Check-Cadence 'fresh idle uses 15 fps' 66 (New-SlopMotionState)

$opening = New-SlopMotionState
Set-SlopFrameTarget -State $opening -Target 'open'
Check-Cadence 'open spring in transit uses 30 fps' 33 $opening
for ($i = 0; $i -lt 400; $i++) { Update-SlopMotionState -State $opening -Dt (1.0 / 120.0) }
Check-Cadence 'settled open body returns to 15 fps' 66 $opening

$large = New-SlopMotionState
Check-Cadence 'idle large uses 10 fps' 100 $large -Large
Set-SlopFrameTarget -State $large -Target 'open'
Check-Cadence 'active large still uses 30 fps' 33 $large -Large

$stream = New-SlopMotionState
Set-SlopBaseCondition -State $stream -Streaming $true -ChatOpen $true -Stalled $false
Check-Cadence 'streaming uses 30 fps' 33 $stream

$phase = New-SlopMotionState
$phase.Phase = 'airborne'
Check-Cadence 'hop phase uses 30 fps' 33 $phase

$hold = New-SlopMotionState
Set-SlopSignal -State $hold -Color 'success' -Shape 'square' -HoldSeconds 1.0
Check-Cadence 'transient signal hold uses 30 fps' 33 $hold

$mood = New-SlopMotionState
Set-SlopMotionMood -State $mood -Mood 'success'
Check-Cadence 'mood pulse uses 30 fps' 33 $mood

Check-Cadence 'window drag uses 30 fps' 33 (New-SlopMotionState) -WindowMoving

$weight = New-SlopMotionState
$weight.Weights[1].Target = 1.0
Check-Cadence 'shape crossfade uses 30 fps' 33 $weight

$vel = New-SlopMotionState
$vel.Open.Velocity = 0.02
Check-Cadence 'body velocity uses 30 fps' 33 $vel

$breathe = New-SlopMotionState
for ($i = 0; $i -lt 240; $i++) {
    Update-SlopMotionState -State $breathe -Dt (1.0 / 120.0)
    $breathe.NextHopIn = 99.0
}
Check-Cadence 'idle breathing must not force 30 fps' 66 $breathe

Describe 'Slop adaptive motion cadence' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-motion-cadence-check.ps1' -CI -Output Detailed"
"exit=$LASTEXITCODE"
```

Expected: 13 failed assertions (`got -1`), `exit=1`.

- [ ] **Step 3: Append the two pure helpers to `src/Slop.Motion.ps1`**

Append after the closing brace of `Test-SlopClientAreaAnimation`:

```powershell

function Test-SlopMotionActive {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [switch]$WindowMoving
    )
    $sig = $State.Signal
    if ($sig.Streaming) { return $true }
    if ($sig.HoldRemaining -gt 0.0) { return $true }
    if ($State.Mood -ne 'idle') { return $true }
    if ($State.Phase -ne 'idle') { return $true }
    if ([Math]::Abs($State.Open.Target - $State.Open.Value) -gt 0.01) { return $true }
    if ([Math]::Abs($State.Open.Velocity) -gt 0.01) { return $true }
    foreach ($w in $State.Weights) {
        if ([Math]::Abs($w.Target - $w.Value) -gt 0.01) { return $true }
    }
    if ($WindowMoving) { return $true }
    return $false
}

function Get-SlopMotionIntervalMs {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [switch]$WindowMoving,
        [switch]$Large
    )
    if (Test-SlopMotionActive -State $State -WindowMoving:$WindowMoving) { return 33 }
    if ($Large) { return 100 }
    return 66
}
```

Why these fields: `Puff` and `Lean` targets oscillate every frame even at rest, so spring error on them would pin the timer at 33 ms forever. `ChatOpen` is also excluded so an expanded but idle body drops to 15 fps.

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2. Expected: 13 passed, 0 failed, `exit=0`.

Also confirm the whole aggregator is green:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
```

Expected: 355 passed, 0 failed, `exit=0` (342 baseline + 13 new).

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.Motion.ps1 tests/slop-motion-cadence-check.ps1
git commit -m "feat(slop): add pure adaptive motion cadence helpers"
```

---

### Task 2: Apply adaptive interval in the motion timer

**Files:**
- Modify: `tests/slop-shell-check.ps1` (source invariants near the existing `SenseAccumulator` checks)
- Modify: `src/Slop.ps1` (timer initialization around current lines 1081–1084, tick start at 1085–1090)

- [ ] **Step 1: Add failing source invariants**

Insert after line 72 of `tests/slop-shell-check.ps1` (after the `SenseAccumulator -ge 60.0` assertion):

```powershell
Assert-True ($src -match 'MotionIntervalMs = 33') 'adaptive motion interval starts at the full 33 ms rate'
Assert-True ($src -match 'Get-SlopMotionIntervalMs') 'timer selects cadence through the pure helper'
Assert-True ($src -match 'MotionTimer\.Interval = \[TimeSpan\]::FromMilliseconds\(\$wantMs\)') 'timer interval is reassigned only when cadence changes'
```

- [ ] **Step 2: Run the shell suite to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
```

Expected: 3 failures, `exit=1`.

- [ ] **Step 3: Initialize cadence state**

Replace this exact block in `src/Slop.ps1`:

```powershell
$script:SenseEnabled = Get-SlopSenseEnabled
$script:SenseAccumulator = 0.0
$script:MotionTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:MotionTimer.Interval = [TimeSpan]::FromMilliseconds(33)
```

with:

```powershell
$script:SenseEnabled = Get-SlopSenseEnabled
$script:SenseAccumulator = 0.0
$script:MotionIntervalMs = 33
$script:LastWindowLeft = $window.Left
$script:LastWindowTop = $window.Top
$script:MotionTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:MotionTimer.Interval = [TimeSpan]::FromMilliseconds($script:MotionIntervalMs)
```

- [ ] **Step 4: Compute the cadence at the top of the tick handler**

Replace this exact block (start of the `Add_Tick` scriptblock):

```powershell
$script:MotionTimer.Add_Tick({
    $now = [DateTime]::UtcNow
    $dt = ($now - $script:LastMotionTick).TotalSeconds
    $script:LastMotionTick = $now
    if ($dt -gt 0.25) { $dt = 0.25 }
```

with:

```powershell
$script:MotionTimer.Add_Tick({
    # cadence: full rate during transitions and active motion, slower at rest.
    $left = $window.Left
    $top = $window.Top
    $moving = ($left -ne $script:LastWindowLeft) -or ($top -ne $script:LastWindowTop)
    $script:LastWindowLeft = $left
    $script:LastWindowTop = $top
    $wantMs = Get-SlopMotionIntervalMs -State $script:Motion -WindowMoving:$moving -Large:$script:PseudoMaximized
    if ($wantMs -ne $script:MotionIntervalMs) {
        $script:MotionIntervalMs = $wantMs
        $script:MotionTimer.Interval = [TimeSpan]::FromMilliseconds($wantMs)
    }
    $now = [DateTime]::UtcNow
    $dt = ($now - $script:LastMotionTick).TotalSeconds
    $script:LastMotionTick = $now
    if ($dt -gt 0.25) { $dt = 0.25 }
```

Setting `Interval` on a running `DispatcherTimer` resets its countdown; the existing 0.25 s `dt` clamp prevents a physics spike. `$script:PseudoMaximized` is introduced in Task 5; until then PowerShell treats an undefined script variable as `$null`, which `-Large:$null` coerces to `$false`, so the app keeps working between commits.

- [ ] **Step 5: Verify**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\verify.ps1"
```

Expected: 358 passed, `exit=0`; verify prints `All gates passed.`

- [ ] **Step 6: Commit**

```powershell
git add -p src/Slop.ps1
git add tests/slop-shell-check.ps1
git commit -m "perf(slop): run the motion clock at 33/66/100 ms by state"
```

Use `git add -p` and stage only the timer hunks; the user's header/param edits in the same file stay unstaged.

---

### Task 3: Reuse pea and shadow transforms

**Files:**
- Modify: `tests/slop-shell-check.ps1`
- Modify: `src/Slop.ps1` (`Initialize-MotionVisuals` lines 364–367, `Apply-SlopMotion` lines 406–410)

- [ ] **Step 1: Add failing source invariants**

Insert after the Task 2 assertions:

```powershell
Assert-True (([regex]::Matches($src, '\$PeaCanvas\.RenderTransform\s*=')).Count -eq 1) 'pea transform is assigned once at initialization'
Assert-True (([regex]::Matches($src, '\$GroundShadow\.RenderTransform\s*=')).Count -eq 1) 'shadow transform is assigned once at initialization'
Assert-True ($src -match '\$script:PeaTranslate\.X\s*=') 'pea transform X updates in place'
Assert-True ($src -match '\$script:ShadowScaleTransform\.ScaleX\s*=') 'shadow scale updates in place'
```

- [ ] **Step 2: Run the shell suite to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
```

Expected: 4 failures, `exit=1`.

- [ ] **Step 3: Cache the transforms once**

Replace:

```powershell
function Initialize-MotionVisuals {
    $GroundShadow.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $GroundShadow.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1,1)
    $PeaCanvas.RenderTransform = [System.Windows.Media.TranslateTransform]::new(0,0)
```

with:

```powershell
function Initialize-MotionVisuals {
    $GroundShadow.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $GroundShadow.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1,1)
    $PeaCanvas.RenderTransform = [System.Windows.Media.TranslateTransform]::new(0,0)
    $script:PeaTranslate = $PeaCanvas.RenderTransform -as [System.Windows.Media.TranslateTransform]
    $script:ShadowScaleTransform = $GroundShadow.RenderTransform -as [System.Windows.Media.ScaleTransform]
    if (-not $script:PeaTranslate -or -not $script:ShadowScaleTransform) {
        throw 'motion transforms were not initialized'
    }
```

Names deliberately avoid every XAML `x:Name` (a previous `$script:Frame` collision silently replaced the XAML grid).

- [ ] **Step 4: Mutate instead of allocating**

Replace:

```powershell
    $x = 1.6 * [Math]::Sin([DateTime]::UtcNow.Ticks / 10000000.0 * 0.9)
    $PeaCanvas.RenderTransform = [System.Windows.Media.TranslateTransform]::new($x, $m.Y)

    $GroundShadow.RenderTransform = [System.Windows.Media.ScaleTransform]::new($m.ShadowScale.Value, 1.0)
    $GroundShadow.Opacity = $m.ShadowAlpha.Value
```

with:

```powershell
    $x = 1.6 * [Math]::Sin([DateTime]::UtcNow.Ticks / 10000000.0 * 0.9)
    $script:PeaTranslate.X = $x
    $script:PeaTranslate.Y = $m.Y

    $script:ShadowScaleTransform.ScaleX = $m.ShadowScale.Value
    $script:ShadowScaleTransform.ScaleY = 1.0
    $GroundShadow.Opacity = $m.ShadowAlpha.Value
```

- [ ] **Step 5: Verify**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\verify.ps1"
```

Expected: 362 passed, `exit=0`; verify prints `All gates passed.`

- [ ] **Step 6: Commit**

```powershell
git add -p src/Slop.ps1
git add tests/slop-shell-check.ps1
git commit -m "perf(slop): reuse pea and shadow transforms across ticks"
```

---

### Task 4: Skip membrane work while collapsed

**Files:**
- Modify: `tests/slop-shell-check.ps1`
- Modify: `src/Slop.ps1` (`Apply-SlopMotion`, current lines 412–450)

- [ ] **Step 1: Add failing source invariants**

Insert after the Task 3 assertions:

```powershell
Assert-True ($src -match '\$bodyClosed = \$script:Membrane\.IsClosed') 'collapsed state is sampled once per tick'
Assert-True ($src -match 'if \(-not \$bodyClosed\) \{\s*\$script:Membrane\.Update') 'membrane physics is skipped while collapsed'
Assert-True ($src -match 'if \(-not \$bodyClosed\) \{\s*\$BodyPath\.Data') 'outline geometry is not rebuilt while collapsed'
```

- [ ] **Step 2: Run the shell suite to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
```

Expected: 3 failures, `exit=1`.

- [ ] **Step 3: Gate physics and geometry on `IsClosed`**

Replace this exact block in `Apply-SlopMotion`:

```powershell
    # The membrane owns its physics and emits window-space path data. The signal
    # stack only selects a mood; it never transforms the content layer.
    $script:Membrane.Move([float]$window.Left, [float]$window.Top)
    $script:Membrane.Update([float]$Dt)
    $frameMood = [SlopFrame]::Idle
```

with:

```powershell
    # The membrane owns its physics and emits window-space path data. The signal
    # stack only selects a mood; it never transforms the content layer.
    # While fully collapsed the outline is invisible, so neither the C# physics
    # nor the WPF Geometry.Parse round trip needs to run.
    $bodyClosed = $script:Membrane.IsClosed
    $script:Membrane.Move([float]$window.Left, [float]$window.Top)
    if (-not $bodyClosed) { $script:Membrane.Update([float]$Dt) }
    $frameMood = [SlopFrame]::Idle
```

Then replace:

```powershell
    if ($script:Membrane.IsClosed -and -not $script:Expanded -and $script:Frame.Opacity -lt 0.02) {
```

with:

```powershell
    if ($bodyClosed -and -not $script:Expanded -and $script:Frame.Opacity -lt 0.02) {
```

Then replace the visible-body branch:

```powershell
    else {
        $BodyPath.Data = [System.Windows.Media.Geometry]::Parse($script:Membrane.Path)
        $BodyPath.Opacity = 1.0
        $BodyPath.Visibility = 'Visible'
        $hl = $script:Membrane.Highlight
        if ($hl) {
            $HeadHighlight.Data = [System.Windows.Media.Geometry]::Parse($hl)
            $HeadHighlight.Opacity = 0.55
            $HeadHighlight.Visibility = 'Visible'
        }
        else { $HeadHighlight.Visibility = 'Collapsed' }
        # Clip is rebuilt on resize (see SizeChanged); opacity follows the opening.
        $Frame.Opacity = [double]$script:Membrane.ContentOpacity
        $Frame.Visibility = 'Visible'
        $PeaCanvas.Visibility = 'Collapsed'
    }
```

with:

```powershell
    else {
        if (-not $bodyClosed) {
            $BodyPath.Data = [System.Windows.Media.Geometry]::Parse($script:Membrane.Path)
            $BodyPath.Opacity = 1.0
            $BodyPath.Visibility = 'Visible'
            $hl = $script:Membrane.Highlight
            if ($hl) {
                $HeadHighlight.Data = [System.Windows.Media.Geometry]::Parse($hl)
                $HeadHighlight.Opacity = 0.55
                $HeadHighlight.Visibility = 'Visible'
            }
            else { $HeadHighlight.Visibility = 'Collapsed' }
        }
        # Clip is rebuilt on resize (see SizeChanged); opacity follows the opening.
        $Frame.Opacity = [double]$script:Membrane.ContentOpacity
        $Frame.Visibility = 'Visible'
        $PeaCanvas.Visibility = 'Collapsed'
    }
```

`Expand()` sets `openT = 1`, which clears `IsClosed` immediately, so the next tick resumes physics with no extra state. `Move()` still runs every tick so `haveWin` stays fresh; the existing acceleration clamp bounds the first frame after a drag while collapsed.

- [ ] **Step 4: Verify**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\verify.ps1"
```

Expected: 365 passed, `exit=0`; verify prints `All gates passed.`

- [ ] **Step 5: Commit**

```powershell
git add -p src/Slop.ps1
git add tests/slop-shell-check.ps1
git commit -m "perf(slop): skip membrane physics and geometry while collapsed"
```

---

### Task 5: Work-area-sized large mode instead of true maximize

**Files:**
- Modify: `tests/slop-shell-check.ps1`
- Modify: `src/Slop.ps1` (`SettingsDot` handler lines 280–282; `WindowState -ne 'Maximized'` guards at current lines 425 and 469)

- [ ] **Step 1: Add failing source invariants**

Insert after the Task 4 assertions:

```powershell
Assert-True ($src -match '\$script:PseudoMaximized') 'work-area large state is tracked'
Assert-True ($src -match '\[System\.Windows\.SystemParameters\]::WorkArea') 'large mode sizes to the work area'
Assert-True ($src -notmatch "WindowState\s*=\s*'Maximized'") 'shell no longer toggles true maximize'
Assert-True (([regex]::Matches($src, [regex]::Escape('-and -not $script:PseudoMaximized'))).Count -eq 2) 'expand and collapse both respect the large state'
```

- [ ] **Step 2: Run the shell suite to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
```

Expected: 4 failures, `exit=1`.

- [ ] **Step 3: Replace the maximize toggle**

Replace:

```powershell
$SettingsDot.Add_Click({
    if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' } else { $window.WindowState = 'Maximized' }
})
```

with:

```powershell
$script:PseudoMaximized = $false
$script:RestoreRect = $null
$SettingsDot.Add_Click({
    if ($script:PseudoMaximized) {
        $script:PseudoMaximized = $false
        $r = $script:RestoreRect
        if ($r) {
            $window.Left   = $r[0]
            $window.Top    = $r[1]
            $window.Width  = $r[2]
            $window.Height = $r[3]
        }
        $script:RestoreRect = $null
    }
    else {
        $script:RestoreRect = @($window.Left, $window.Top, $window.Width, $window.Height)
        $script:PseudoMaximized = $true
        $wa = [System.Windows.SystemParameters]::WorkArea
        $window.Left   = $wa.X
        $window.Top    = $wa.Y
        $window.Width  = $wa.Width
        $window.Height = $wa.Height
    }
})
```

Event-handler scriptblocks do not close over function locals, so both flags use `$script:` scope. `SystemParameters.WorkArea` is in DIPs, matching WPF window geometry.

- [ ] **Step 4: Stop resize handlers from shrinking a large window**

Replace both occurrences of:

```powershell
if ($window.WindowState -ne 'Maximized') {
```

with:

```powershell
if ($window.WindowState -ne 'Maximized' -and -not $script:PseudoMaximized) {
```

They are in `Apply-SlopMotion` (`RestoreCompact` branch) and `Expand-Chat`.

- [ ] **Step 5: Verify headless and live**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output None"
"exit=$LASTEXITCODE"
pwsh -NoProfile -STA -File 'tools/verify-motion.ps1'
"live_exit=$LASTEXITCODE"
```

Expected: 369 passed, `exit=0`. Live output must include `MAXIMIZE size=1200x1920 screen=1200x1920`, `RESTORE size=950x675` (760x540 logical at 125% DPI), and `live_exit=0`. The verifier already compares against `Screen.PrimaryScreen.WorkingArea`, so work-area sizing passes its fill assertion while no longer covering the taskbar. Confirm the app process is gone afterward (the verifier kills it in `finally`).

- [ ] **Step 6: Commit**

```powershell
git add -p src/Slop.ps1
git add tests/slop-shell-check.ps1
git commit -m "perf(slop): size large mode to the work area instead of maximizing"
```

---

### Task 6: Committed profiling harness and measured proof

**Files:**
- Create: `tools/profile-slop.ps1`

- [ ] **Step 1: Write the harness**

Create `tools/profile-slop.ps1` with exactly this content:

```powershell
#requires -Version 7.6
<#
.SYNOPSIS
  Repeatable render-cost probe for Slop: headless per-tick cost plus live CPU samples.
.DESCRIPTION
  Run from the repo root in an STA shell. Emits a table; -Json writes the same
  data as structured output so pre/post runs can be compared.
#>
param(
    [int]$Iterations = 600,
    [int]$Seconds = 4,
    [int]$Samples = 3,
    [switch]$SkipLive,
    [string]$Json
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, UIAutomationClient, UIAutomationTypes

$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'src/Slop.Motion.ps1')
. (Join-Path $repo 'src/Slop.Frame.ps1')

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ProfMouse {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,int e);
}
'@

function Measure-TickCost {
    param([string]$Name, [string]$Target, [double]$W, [double]$H, [int]$N)
    $m = New-SlopMotionState
    Set-SlopFrameTarget -State $m -Target $Target
    Set-SlopBaseCondition -State $m -Streaming $false -ChatOpen ($Target -eq 'open') -Stalled $false
    $frame = [SlopFrame]::new($W, $H, 18.0, 4242)
    $frame.SetMotionScale(1.0)
    if ($Target -eq 'open') {
        $frame.SetFrame($W, $H)
        $frame.Expand(242.0, 300.0)
        for ($i = 0; $i -lt 60; $i++) { $frame.Update(1.0 / 30.0) }
    }
    for ($i = 0; $i -lt 40; $i++) {
        Update-SlopMotionState -State $m -Dt (1.0 / 120.0)
        $frame.Update(1.0 / 30.0)
        $null = [System.Windows.Media.Geometry]::Parse($frame.Path)
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $N; $i++) {
        Update-SlopMotionState -State $m -Dt (1.0 / 120.0)
        $frame.Update(1.0 / 30.0)
        if (-not $frame.IsClosed) {
            $null = [System.Windows.Media.Geometry]::Parse($frame.Path)
            if ($frame.Highlight) { $null = [System.Windows.Media.Geometry]::Parse($frame.Highlight) }
        }
    }
    $sw.Stop()
    [pscustomobject]@{ Kind = 'tick'; Scenario = $Name; MsPerTick = $sw.Elapsed.TotalMilliseconds / $N }
}

function Get-AppWindow {
    param([int]$ProcessId)
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessId)
    [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
        [System.Windows.Automation.TreeScope]::Children, $cond)
}

function Invoke-Uia {
    param([string]$Id)
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $el = $script:ProfWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if (-not $el) { throw "UIA element $Id not found" }
    $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Sample-Cpu {
    Start-Sleep -Milliseconds 400
    $before = (Get-Process -Id $script:ProfProc.Id).TotalProcessorTime.TotalSeconds
    $wall = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds $script:ProfileSeconds
    $wall.Stop()
    $after = (Get-Process -Id $script:ProfProc.Id).TotalProcessorTime.TotalSeconds
    return (100.0 * ($after - $before) / $wall.Elapsed.TotalSeconds)
}

function Get-Median {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    $mid = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 0) { return ($sorted[$mid - 1] + $sorted[$mid]) / 2.0 }
    return $sorted[$mid]
}

$script:ProfileSeconds = $Seconds
$results = @()
foreach ($case in @(
        @{ Name = 'closed compact'; Target = 'closed'; W = 448.0; H = 294.0 },
        @{ Name = 'open compact';   Target = 'open';   W = 724.0; H = 504.0 },
        @{ Name = 'closed large';   Target = 'closed'; W = 960.0; H = 1536.0 },
        @{ Name = 'open large';     Target = 'open';   W = 960.0; H = 1536.0 })) {
    $results += Measure-TickCost -Name $case.Name -Target $case.Target -W $case.W -H $case.H -N $Iterations
}

if (-not $SkipLive) {
    $svcJson = Join-Path $env:USERPROFILE '.config/opencode/service.json'
    if (Test-Path $svcJson) { $env:OPENCODE_PASSWORD = (Get-Content $svcJson -Raw | ConvertFrom-Json).password }
    if ([string]::IsNullOrEmpty($env:OPENCODE_PASSWORD)) { throw 'OPENCODE_PASSWORD is required' }
    $out = Join-Path $env:TEMP 'slop-profile.out'
    $err = Join-Path $env:TEMP 'slop-profile.err'
    $script:ProfProc = Start-Process -FilePath 'pwsh' `
        -ArgumentList @('-STA','-NoProfile','-File',(Join-Path $repo 'src/Slop.ps1')) `
        -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    Start-Sleep -Seconds 8
    try {
        if ($script:ProfProc.HasExited) { throw "app exited early: $(Get-Content $err -Raw)" }
        $script:ProfWindow = Get-AppWindow -ProcessId $script:ProfProc.Id
        if (-not $script:ProfWindow) { throw 'no app window found' }
        $null = Sample-Cpu

        $compact = @()
        for ($i = 0; $i -lt $Samples; $i++) { $compact += Sample-Cpu }
        $r = $script:ProfWindow.Current.BoundingRectangle
        $dpi = $r.Width / 484.0
        [ProfMouse]::SetCursorPos([int]($r.X + 242 * $dpi), [int]($r.Y + 305 * $dpi)) | Out-Null
        [ProfMouse]::mouse_event(2,0,0,0,0)
        Start-Sleep -Milliseconds 45
        [ProfMouse]::mouse_event(4,0,0,0,0)
        Start-Sleep -Seconds 1
        $expanded = @()
        for ($i = 0; $i -lt $Samples; $i++) { $expanded += Sample-Cpu }

        Invoke-Uia 'SettingsDot'
        Start-Sleep -Seconds 1
        $large = @()
        for ($i = 0; $i -lt $Samples; $i++) { $large += Sample-Cpu }
        Invoke-Uia 'SettingsDot'
        Start-Sleep -Milliseconds 500

        foreach ($entry in @(
                @{ Mode = 'compact idle'; Values = $compact },
                @{ Mode = 'expanded idle'; Values = $expanded },
                @{ Mode = 'work-area-large idle'; Values = $large })) {
            $results += [pscustomobject]@{
                Kind = 'cpu'
                Scenario = $entry.Mode
                MedianPctOfCore = [Math]::Round((Get-Median -Values ([double[]]$entry.Values)), 1)
                Samples = ($entry.Values | ForEach-Object { [Math]::Round($_, 1) }) -join ', '
            }
        }
    }
    finally {
        if ($script:ProfProc -and -not $script:ProfProc.HasExited) {
            Stop-Process -Id $script:ProfProc.Id -Force -ErrorAction SilentlyContinue
        }
        Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
            Where-Object { $_.CommandLine -like '*src/Slop.ps1*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
}

$results | ForEach-Object {
    if ($_.Kind -eq 'tick') {
        "{0,-24} {1,8:N3} ms/tick" -f $_.Scenario, $_.MsPerTick
    }
    else {
        "{0,-24} {1,8:N1}% of one core  samples: {2}" -f $_.Scenario, $_.MedianPctOfCore, $_.Samples
    }
}
if ($Json) { $results | ConvertTo-Json -Depth 4 | Set-Content -Path $Json }
```

The `finally` block is mandatory: the app is topmost and an orphaned launcher holds inherited stdout, which hangs piped callers.

- [ ] **Step 2: Smoke-test the harness**

```powershell
pwsh -NoProfile -STA -File 'tools/profile-slop.ps1' -Iterations 60 -Seconds 2 -Samples 1 -SkipLive
"exit=$LASTEXITCODE"
```

Expected: four `ms/tick` lines, `exit=0`. No app is launched in this mode.

- [ ] **Step 3: Run the full harness and capture post-change numbers**

```powershell
$json = Join-Path $env:TEMP 'opencode/slop-after.json'
pwsh -NoProfile -STA -File 'tools/profile-slop.ps1' -Json $json
"exit=$LASTEXITCODE"
Get-Content $json -Raw
```

Expected: four `ms/tick` lines, three `% of one core` lines, `exit=0`, and valid JSON with 7 records. Confirm no `pwsh` process with `src/Slop.ps1` in its command line remains:

```powershell
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -like '*src/Slop.ps1*' } |
    Select-Object ProcessId, CommandLine
```

Expected: no output.

- [ ] **Step 4: Run the final gates**

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\verify.ps1"
pwsh -NoProfile -STA -File 'tools/verify-motion.ps1'
"live_exit=$LASTEXITCODE"
```

Expected: `All gates passed.` with 369 Pester tests; live verifier `live_exit=0` including `MAXIMIZE`, `RESTORE`, `CHAT`, `ESC`, and `DRAG` checks.

- [ ] **Step 5: Commit with the measured deltas in the message**

```powershell
git add tools/profile-slop.ps1
git commit -m @'
perf(slop): finish frame-budget pass with repeatable profiling harness

Post-change samples from tools/profile-slop.ps1 (median % of one core, 3x4s):
- compact idle: <paste measured value>
- expanded idle: <paste measured value>
- work-area-large idle: <paste measured value>

Baseline ranges are in docs/performance/baseline-2026-11-23.md.
'@
```

Replace each `<paste measured value>` with the actual `MedianPctOfCore` from Step 3 before running. This is the only step in the plan that requires a runtime value; do not commit placeholders.

---

## Self-review checklist (run before handing off)

- **Spec coverage:** §1 cadence → Task 1 + 2; §2 transforms → Task 3; §3 collapsed skip → Task 4; §4 work-area large → Task 5; §5 harness → Task 6; §6 tests → Tasks 1–5; out-of-scope items untouched.
- **Placeholder scan:** the only runtime placeholder is the commit-message numbers in Task 6 Step 5, with explicit replacement instructions.
- **Type/name consistency:** `Test-SlopMotionActive`, `Get-SlopMotionIntervalMs`, `MotionIntervalMs`, `LastWindowLeft/Top`, `PeaTranslate`, `ShadowScaleTransform`, `bodyClosed`, `PseudoMaximized`, `RestoreRect`, `wantMs` are used with identical spelling in tests, source edits, and the harness.
- **Count arithmetic:** 342 baseline + 13 (Task 1) + 3 (Task 2) + 4 (Task 3) + 3 (Task 4) + 4 (Task 5) = 369 final.

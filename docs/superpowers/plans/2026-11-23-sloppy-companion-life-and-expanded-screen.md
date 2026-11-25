# Sloppy Companion Life and Expanded Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task, inline in this session. No subagents — standing user cost constraint. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Sloppy continuously alive, add opt-in local System Sense thought bubbles, and make the expanded chat readable at any window size.

**Architecture:** Four small modules with clear boundaries. `Slop.Sense.ps1` does pure read-only sampling and threshold classification; `Slop.Motion.ps1` owns phase selection and continuous micro-motion; `Slop.Face.ps1` renders expression patterns; `Slop.ps1` wires them to the existing 30 fps dispatcher timer and WPF shell. No new processes, jobs, timers, or network calls.

**Tech Stack:** PowerShell 7 + WPF (PresentationFramework/PresentationCore/WindowsBase), .NET `PerformanceCounter`, `IPGlobalProperties`, `DriveInfo`, `Microsoft.VisualBasic.Devices.ComputerInfo`.

---

### Task 1: System Sense module + headless test

**Files:**
- Create: `src/Slop.Sense.ps1`
- Create: `tests/slop-sense-check.ps1`

- [ ] **Step 1: Create the Sense module**

```powershell
# src/Slop.Sense.ps1 — opt-in, read-only local system observations for Sloppy.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

$script:SlopSenseBaseline = $null
$script:SlopSenseLastAlert = @{}

function Get-SlopSenseSettingsPath {
    $root = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME '.config' }
    return Join-Path $root 'Slop\settings.json'
}

function Get-SlopSenseEnabled {
    $path = Get-SlopSenseSettingsPath
    try {
        if (-not (Test-Path $path)) { return $false }
        $cfg = Get-Content $path -Raw | ConvertFrom-Json
        return [bool]$cfg.SystemSense
    } catch { return $false }
}

function Set-SlopSenseEnabled {
    param([Parameter(Mandatory)][bool]$Enabled)
    $path = Get-SlopSenseSettingsPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ([ordered]@{ SystemSense = $Enabled } | ConvertTo-Json) | Set-Content $path
}

function Get-SlopSenseReading {
    try {
        $cpu = [System.Diagnostics.PerformanceCounter]::new('Processor', '% Processor Time', '_Total')
        try { $cpuPct = [Math]::Round($cpu.NextValue(), 1) } finally { $cpu.Dispose() }

        $ci = [Microsoft.VisualBasic.Devices.ComputerInfo]::new()
        $ramPct = 0.0
        if ($ci.TotalPhysicalMemory -gt 0) {
            $ramPct = [Math]::Round(100.0 * ($ci.TotalPhysicalMemory - $ci.AvailablePhysicalMemory) / $ci.TotalPhysicalMemory, 1)
        }

        $root = [System.IO.Path]::GetPathRoot($env:SystemDrive)
        $drive = [System.IO.DriveInfo]::new($root)
        $diskPct = 0.0
        if ($drive.TotalSize -gt 0) {
            $diskPct = [Math]::Round(100.0 * $drive.AvailableFreeSpace / $drive.TotalSize, 1)
        }

        $net = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        $listeners = @($net.GetActiveTcpListeners() | ForEach-Object { $_.Port } | Sort-Object -Unique)
        $connections = @($net.GetActiveTcpConnections() | Where-Object { $_.State -eq 'Established' }).Count
        $processes = [System.Diagnostics.Process]::GetProcesses().Count

        $failedLogins = 0
        try {
            $ev = Get-WinEvent -FilterHashtable @{
                LogName = 'Security'; Id = 4625; StartTime = [DateTime]::Now.AddMinutes(-5)
            } -MaxEvents 5 -ErrorAction Stop
            if ($ev) { $failedLogins = @($ev).Count }
        } catch { }

        return @{
            CpuPct = $cpuPct; RamPct = $ramPct; DiskFreePct = $diskPct
            Listeners = $listeners; Connections = $connections
            Processes = $processes; FailedLogins = $failedLogins
            CpuHighStreak = 0
        }
    } catch { return $null }
}

function Get-SlopSenseAlerts {
    param(
        [Parameter(Mandatory)][hashtable]$Reading,
        [hashtable]$Baseline,
        [Parameter(Mandatory)][DateTime]$Now
    )

    $streak = 0
    if ($Baseline -and $Baseline.ContainsKey('CpuHighStreak')) { $streak = [int]$Baseline.CpuHighStreak }
    $streak = if ([double]$Reading.CpuPct -ge 90.0) { $streak + 1 } else { 0 }
    $Reading.CpuHighStreak = $streak

    $alerts = [System.Collections.Generic.List[hashtable]]::new()
    if ([double]$Reading.RamPct -ge 85.0) {
        $alerts.Add(@{ Kind = 'ram'; Text = "RAM at $([int]$Reading.RamPct)% — Sloppy feels sluggish." })
    }
    if ([double]$Reading.DiskFreePct -le 10.0) {
        $alerts.Add(@{ Kind = 'disk'; Text = "Disk free space down to $([int]$Reading.DiskFreePct)%." })
    }
    if ($streak -ge 2) {
        $alerts.Add(@{ Kind = 'cpu'; Text = "CPU held at $([int]$Reading.CpuPct)% for two samples." })
    }

    if ($Baseline) {
        $newPorts = @($Reading.Listeners | Where-Object { $_ -notin $Baseline.Listeners })
        if ($newPorts.Count -gt 0) {
            $alerts.Add(@{ Kind = 'listener'; Text = "New listening port: $($newPorts -join ', ')." })
        }
        $oldConn = [double]$Baseline.Connections
        if ($oldConn -gt 0 -and [double]$Reading.Connections -gt $oldConn * 1.3) {
            $alerts.Add(@{ Kind = 'connections'; Text = "TCP connections jumped $([int]$oldConn) -> $([int]$Reading.Connections)." })
        }
        $oldProc = [double]$Baseline.Processes
        if ($oldProc -gt 0 -and [double]$Reading.Processes -gt $oldProc * 1.25) {
            $alerts.Add(@{ Kind = 'processes'; Text = "Process count jumped $([int]$oldProc) -> $([int]$Reading.Processes)." })
        }
    }
    if ([int]$Reading.FailedLogins -gt 0) {
        $alerts.Add(@{ Kind = 'logins'; Text = "$([int]$Reading.FailedLogins) failed login(s) in the last 5 minutes." })
    }

    $fresh = @()
    foreach ($a in $alerts) {
        $last = $null
        if ($script:SlopSenseLastAlert.ContainsKey($a.Kind)) { $last = $script:SlopSenseLastAlert[$a.Kind] }
        if (-not $last -or ($Now - $last).TotalMinutes -ge 5) {
            $script:SlopSenseLastAlert[$a.Kind] = $Now
            $fresh += $a.Text
        }
    }
    return $fresh
}

function Invoke-SlopSenseScan {
    if (-not (Get-SlopSenseEnabled)) { return @() }
    $reading = Get-SlopSenseReading
    if (-not $reading) { return @() }
    $alerts = Get-SlopSenseAlerts -Reading $reading -Baseline $script:SlopSenseBaseline -Now ([DateTime]::UtcNow)
    $script:SlopSenseBaseline = $reading
    return @($alerts)
}
```

- [ ] **Step 2: Create the failing test**

```powershell
# tests/slop-sense-check.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Slop.Sense.ps1')

$script:failures = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { "PASS: $Message" } else { "FAIL: $Message"; $script:failures++ }
}

$oldAppData = $env:APPDATA
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('slop-sense-' + [guid]::NewGuid().ToString('N'))
$env:APPDATA = $testRoot
Assert-True (-not (Get-SlopSenseEnabled)) 'settings default to off'
Set-SlopSenseEnabled -Enabled $true
Assert-True (Get-SlopSenseEnabled) 'enable persists'
Set-SlopSenseEnabled -Enabled $false
Assert-True (-not (Get-SlopSenseEnabled)) 'disable persists'

$now = [DateTime]::UtcNow
$base = @{ CpuPct = 20.0; RamPct = 50.0; DiskFreePct = 60.0; Listeners = @(80,443); Connections = 10; Processes = 100; FailedLogins = 0; CpuHighStreak = 0 }
$quiet = @{ CpuPct = 20.0; RamPct = 50.0; DiskFreePct = 60.0; Listeners = @(80,443); Connections = 10; Processes = 100; FailedLogins = 0 }
Assert-True (@(Get-SlopSenseAlerts -Reading $quiet -Baseline $base -Now $now).Count -eq 0) 'normal readings produce no alerts'

$hot = @{ CpuPct = 91.0; RamPct = 88.0; DiskFreePct = 8.0; Listeners = @(80,443,8080); Connections = 20; Processes = 150; FailedLogins = 1 }
$alerts = @(Get-SlopSenseAlerts -Reading $hot -Baseline $base -Now $now)
Assert-True ($alerts.Count -ge 5) "threshold and delta alerts fire (got $($alerts.Count))"
Assert-True (($alerts -join ' ') -match 'RAM') 'RAM threshold alert present'
Assert-True (($alerts -join ' ') -match '8080') 'new listener alert present'
Assert-True (@(Get-SlopSenseAlerts -Reading $hot -Baseline $base -Now $now).Count -eq 0) 'cooldown suppresses repeat alerts'
Assert-True (@(Get-SlopSenseAlerts -Reading $hot -Baseline $base -Now $now.AddMinutes(6)).Count -ge 5) 'cooldown expires after five minutes'

$streakReading = @{ CpuPct = 95.0; RamPct = 50.0; DiskFreePct = 60.0; Listeners = @(80,443); Connections = 10; Processes = 100; FailedLogins = 0 }
$first = @(Get-SlopSenseAlerts -Reading $streakReading -Baseline $base -Now $now.AddMinutes(20))
Assert-True (($first -join ' ') -notmatch 'CPU') 'single high-CPU sample is ignored'
# The second sample must see the streak recorded by the first one. Pass an
# explicit baseline with CpuHighStreak = 1; reusing $base resets it to 0.
$secondBase = @{ CpuPct = 95.0; RamPct = 50.0; DiskFreePct = 60.0; Listeners = @(80,443); Connections = 10; Processes = 100; FailedLogins = 0; CpuHighStreak = 1 }
$second = @(Get-SlopSenseAlerts -Reading $streakReading -Baseline $secondBase -Now $now.AddMinutes(21))
Assert-True (($second -join ' ') -match 'CPU') 'two consecutive high-CPU samples alert'

$env:APPDATA = $oldAppData
if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
if ($script:failures -gt 0) { throw "$($script:failures) sense check(s) failed" }
'ALL SENSE CHECKS PASSED'
```

- [ ] **Step 3: Run test**

Run: `cd .; pwsh -NoProfile -File tests/slop-sense-check.ps1`
Expected: all PASS, final `ALL SENSE CHECKS PASSED`, exit 0.

- [ ] **Step 4: Commit**

```powershell
git add src/Slop.Sense.ps1 tests/slop-sense-check.ps1
git commit -m "feat(slop): add opt-in read-only System Sense module"
```

---

### Task 2: Idle action variety and continuous micro-motion

**Files:**
- Modify: `src/Slop.Motion.ps1` (state fields, idle selector, phase switch, tail block)
- Test: `tests/slop-motion-check.ps1`

- [ ] **Step 1: Add new state field**

Replace:
```powershell
        WanderDx    = 0.0
        TargetShape = 0
```
with:
```powershell
        WanderDx    = 0.0
        FaceExpression = 'scattered'
        TargetShape = 0
```

- [ ] **Step 2: Add idle action selector and settle helper**

Insert immediately before `function Update-SlopMotionState`:

```powershell
function Get-SlopIdleAction {
    param([Parameter(Mandatory)][double]$NextHopIn)
    # -0.5, not -0.005: at 30 fps a naturally expiring timer lands near -0.033,
    # so a -0.005 threshold made the forced hop swallow almost every random
    # action. Only explicit hop requests (Set-SlopTargetShape / tests) use a
    # value this negative; ordinary expiry must roll for real variety.
    if ($NextHopIn -le -0.5) { return 'anticipate' }
    $roll = Get-Random -Minimum 0 -Maximum 100
    if     ($roll -lt 22) { return 'anticipate' }
    elseif ($roll -lt 36) { return 'sit' }
    elseif ($roll -lt 48) { return 'stretch' }
    elseif ($roll -lt 60) { return 'wander' }
    elseif ($roll -lt 74) { return 'blink' }
    elseif ($roll -lt 84) { return 'tilt' }
    elseif ($roll -lt 92) { return 'bounce' }
    elseif ($roll -lt 97) { return 'peek' }
    else                  { return 'yawn' }
}

function Complete-SlopIdleAction {
    param([Parameter(Mandatory)][hashtable]$State)
    $State.Phase = 'idle'
    $State.PhaseTime = 0.0
    $State.Squash.Target = 1.0
    $State.Puff.Target = 1.0
    $State.Lean.Target = 0.0
    $State.Wobble.Target = 0.0
    $State.ShadowScale.Target = 1.0
    $State.ShadowAlpha.Target = 0.40
    $State.FaceExpression = 'scattered'
    $State.NextHopIn = 1.0 + (Get-Random -Minimum 0 -Maximum 200) / 100.0
}
```

Keep explicit forced hops working with the new `-0.5` threshold. In `Set-SlopTargetShape` (line 231 of `src/Slop.Motion.ps1`), replace:

```powershell
    if ($State.Phase -eq 'idle') { $State.NextHopIn = 0.0 }
```

with:

```powershell
    if ($State.Phase -eq 'idle') { $State.NextHopIn = -1.0 }
```

This preserves the existing "shape morph lands with a hop" flourish without making ordinary timer expiry force a hop.

- [ ] **Step 3: Replace the phase switch**

Replace the entire `switch ($State.Phase) { ... }` block (currently lines 275–380) with:

```powershell
    switch ($State.Phase) {
        'idle' {
            $State.Squash.Target = 1.0
            $State.FaceExpression = 'scattered'
            if ($State.Mood -eq 'thinking') {
                $State.Lean.Target = 3.5 * [Math]::Sin($t * 6.2)
                $State.Wobble.Target = 0.045 * [Math]::Sin($t * 9.1)
            }
            if ($State.Mood -eq 'idle' -and $State.Open.Value -lt 0.1 -and $State.NextHopIn -le 0) {
                $action = Get-SlopIdleAction -NextHopIn $State.NextHopIn
                $State.Phase = $action
                $State.PhaseTime = 0.0
                switch ($action) {
                    'anticipate' { $State.Squash.Target = 0.80; $State.ShadowScale.Target = 0.82 }
                    'sit'        { $State.Squash.Target = 0.85; $State.FaceExpression = 'cluster' }
                    'stretch'    { $State.Squash.Target = 1.15; $State.Puff.Target = 1.08; $State.FaceExpression = 'line' }
                    'yawn'       { $State.Squash.Target = 1.12; $State.Lean.Target = -6.0; $State.FaceExpression = 'ring' }
                    'blink'      { $State.Lean.Target = 4.0; $State.FaceExpression = 'line' }
                    'tilt'       { $State.FaceExpression = 'cluster' }
                    'bounce'     { $State.FaceExpression = 'ring' }
                    'peek'       { $State.Lean.Target = -5.0; $State.FaceExpression = 'line' }
                    'wander'     { $State.WanderDx = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { -30.0 } else { 30.0 } }
                }
            }
        }
        'anticipate' {
            if ($State.PhaseTime -ge 0.12) {
                $State.Phase = 'airborne'
                $State.PhaseTime = 0.0
                $State.Y = 0.0
                $State.VY = -165.0
                $State.FaceExpression = 'ring'
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
                Complete-SlopIdleAction -State $State
                $State.HopCount++
            }
        }
        'sit'     { if ($State.PhaseTime -ge 1.8) { Complete-SlopIdleAction -State $State } }
        'stretch' { if ($State.PhaseTime -ge 1.2) { Complete-SlopIdleAction -State $State } }
        'wander'  { if ($State.PhaseTime -ge 3.0) { Complete-SlopIdleAction -State $State } }
        'blink'   { if ($State.PhaseTime -ge 0.35) { Complete-SlopIdleAction -State $State } }
        'tilt' {
            $State.Lean.Target = 7.0 * [Math]::Sin($State.PhaseTime * 5.0)
            if ($State.PhaseTime -ge 0.9) { Complete-SlopIdleAction -State $State }
        }
        'bounce' {
            $State.Squash.Target = 1.0 + 0.12 * [Math]::Sin($State.PhaseTime * 14.0)
            if ($State.PhaseTime -ge 0.8) { Complete-SlopIdleAction -State $State }
        }
        'peek' { if ($State.PhaseTime -ge 0.7) { Complete-SlopIdleAction -State $State } }
        'yawn' { if ($State.PhaseTime -ge 1.2) { Complete-SlopIdleAction -State $State } }
    }
```

- [ ] **Step 4: Add continuous sway/breathing to every phase**

Replace the tail block (currently lines 382–387):

```powershell
    if ($State.Phase -eq 'idle' -and $State.Mood -ne 'thinking') {
        $State.Puff.Target = 1.0 + 0.018 * [Math]::Sin($t * 2.1)
    }
    else {
        $State.Puff.Target = 1.0
    }
```

with:

```powershell
    # Micro-motion never stops: breathing in all phases, sway except where a
    # phase owns the lean (tilt/peek/yawn) or an error pulse owns it.
    if ($State.Mood -notin @('thinking','error') -and $State.Phase -ne 'stretch') {
        $State.Puff.Target = 1.0 + 0.018 * [Math]::Sin($t * 2.1)
    }
    if ($State.Mood -notin @('thinking','error','success') -and
        $State.Phase -notin @('tilt','peek','yawn','airborne','land')) {
        $State.Lean.Target = 1.2 * [Math]::Sin($t * 0.5)
    }
```

- [ ] **Step 5: Add headless assertions**

First, in `tests/slop-motion-check.ps1`, change the two explicit hop-injection values from `-0.01` to `-1.0` (lines 22 and 66). The old value no longer crosses the `-0.5` forced-hop threshold.

Then append before the final `if ($script:failures -gt 0)` in `tests/slop-motion-check.ps1`:

```powershell
$seen = @{}
for ($i = 0; $i -lt 400; $i++) { $seen[(Get-SlopIdleAction -NextHopIn 1.0)] = $true }
foreach ($p in @('anticipate','sit','stretch','wander','blink','tilt','bounce','peek','yawn')) {
    Assert-True ($seen.ContainsKey($p)) "idle action $p is reachable"
}
Assert-True ((Get-SlopIdleAction -NextHopIn -1.0) -eq 'anticipate') 'explicit hop request overrides random action'
$m2 = New-SlopMotionState
Complete-SlopIdleAction -State $m2
Assert-True ($m2.NextHopIn -ge 1.0 -and $m2.NextHopIn -le 3.0) "idle gap is 1-3s (got $([Math]::Round($m2.NextHopIn,2)))"
Assert-True ($m2.FaceExpression -eq 'scattered') 'settle resets the face expression'
```

- [ ] **Step 6: Run tests**

Run: `cd .; pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: all PASS, `ALL MOTION CHECKS PASSED`, exit 0.

- [ ] **Step 7: Commit**

```powershell
git add src/Slop.Motion.ps1 tests/slop-motion-check.ps1
git commit -m "feat(slop): nine idle actions, short gaps, continuous micro-motion"
```

---

### Task 3: Face expression patterns

**Files:**
- Modify: `src/Slop.Face.ps1`
- Test: `tests/slop-face-check.ps1`

- [ ] **Step 1: Replace the face module**

Overwrite `src/Slop.Face.ps1` with:

```powershell
# src/Slop.Face.ps1 — 12 alive pixels with switchable expression patterns.
$ErrorActionPreference = 'Stop'

$script:FaceDots = $null

function Initialize-SlopFaceDots {
    param([int]$Count = 12, [int]$Seed = 1337)
    $rng = New-Object System.Random($Seed)
    $dots = @()
    $palette = @('#93C5FD','#FDE68A','#86EFAC','#FCA5A5','#C4B5FD','#FFFFFF')
    for ($i = 0; $i -lt $Count; $i++) {
        $dots += @{
            X = $rng.NextDouble()
            Y = $rng.NextDouble()
            Phase = $rng.NextDouble() * 6.283
            Freq = 0.6 + $rng.NextDouble() * 1.4
            Size = 1.0 + $rng.NextDouble() * 1.2
            Color = $palette[$rng.Next($palette.Count)]
        }
    }
    $script:FaceDots = $dots
}

function New-SlopFaceLayer {
    param([int]$Seed = 1337)
    if (-not $script:FaceDots) { Initialize-SlopFaceDots -Seed $Seed }
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.IsHitTestVisible = $false
    foreach ($d in $script:FaceDots) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = $d.Size * 2
        $e.Height = $d.Size * 2
        $e.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($d.Color)
        $canvas.Children.Add($e) | Out-Null
    }
    return $canvas
}

function Update-SlopFaceLayer {
    param(
        [Parameter(Mandatory)]$Target,
        [double]$Time = 0.0,
        [double]$Speed = 1.0,
        [double]$Width = 100.0,
        [double]$Height = 100.0,
        [bool]$Frozen = $false,
        [ValidateSet('scattered','ring','cluster','line')][string]$Pattern = 'scattered'
    )
    if (-not $script:FaceDots) { Initialize-SlopFaceDots }
    $inset = 24.0
    $w = [Math]::Max(10.0, $Width - 2 * $inset)
    $h = [Math]::Max(10.0, $Height - 2 * $inset)
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
                $a = (6.2831853 * $i / $count) + $Time * 0.15 * $Speed
                $nx = 0.5 + 0.30 * [Math]::Cos($a)
                $ny = 0.5 + 0.26 * [Math]::Sin($a)
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
        $px = $inset + $nx * $w
        $py = $inset + $ny * $h
        [System.Windows.Controls.Canvas]::SetLeft($el, $px - $el.Width / 2)
        [System.Windows.Controls.Canvas]::SetTop($el, $py - $el.Height / 2)
    }
}
```

- [ ] **Step 2: Extend the face test**

Replace `tests/slop-face-check.ps1` with:

```powershell
# tests/slop-face-check.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Slop.Face.ps1')

$script:failures = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { "PASS: $Message" } else { "FAIL: $Message"; $script:failures++ }
}

$face = New-SlopFaceLayer
Assert-True ($face.Children.Count -eq 12) "face has 12 dots (got $($face.Children.Count))"

foreach ($pattern in @('scattered','ring','cluster','line')) {
    Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Pattern $pattern
    $xs = @($face.Children | ForEach-Object { [System.Windows.Controls.Canvas]::GetLeft($_) })
    Assert-True (($xs | Where-Object { [double]::IsNaN($_) }).Count -eq 0) "$pattern positions are finite"
    Assert-True (($xs | Measure-Object -Minimum).Minimum -ge 0) "$pattern stays inside the window"
}
Update-SlopFaceLayer -Target $face -Time 2.0 -Speed 0.0 -Width 484 -Height 330 -Frozen $true -Pattern 'ring'
Assert-True ($face.Children.Count -eq 12) 'frozen pattern keeps 12 dots'

if ($script:failures -gt 0) { throw "$($script:failures) face check(s) failed" }
'ALL FACE CHECKS PASSED'
```

- [ ] **Step 3: Run tests**

Run: `cd .; pwsh -NoProfile -File tests/slop-face-check.ps1`
Expected: `ALL FACE CHECKS PASSED`, exit 0.

- [ ] **Step 4: Commit**

```powershell
git add src/Slop.Face.ps1 tests/slop-face-check.ps1
git commit -m "feat(slop): face expression patterns scattered/ring/cluster/line"
```

---

### Task 4: Flexible expanded window and full-screen fix

**Files:**
- Modify: `src/Slop.ps1` (XAML, state, SizeChanged, Expand/Collapse, motion tick, shell check)
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Remove the fixed chat height**

Replace:
```xml
        <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto" Margin="4" MaxHeight="235">
```
with:
```xml
        <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto" Margin="4">
```

- [ ] **Step 2: Add resize/restore state**

Replace:
```powershell
$script:Expanded = $false
$script:Pinned = $false
```
with:
```powershell
$script:Expanded = $false
$script:Pinned = $false
$script:ExpandedSize = $null
$script:RestoreCompact = $false
```

- [ ] **Step 3: Fix the SizeChanged handler**

Replace the whole handler (currently lines 258–265):

```powershell
$window.Add_SizeChanged({
    param($s, $e)
    # 18 px of goo room on every side, matching the frame engine's margin.
    $Frame.Width = [Math]::Max(300.0, $window.ActualWidth - 36)
    $Frame.Height = [Math]::Max(200.0, $window.ActualHeight - 36)
    if ($script:Membrane) { $script:Membrane.SetFrame([float]$Frame.Width, [float]$Frame.Height) }
    Update-PeaAnchor
})
```

with:

```powershell
$window.Add_SizeChanged({
    param($s, $e)
    # 18 px of goo room on every side, matching the frame engine's margin.
    $Frame.Width = [Math]::Max(300.0, $window.ActualWidth - 36)
    $Frame.Height = [Math]::Max(200.0, $window.ActualHeight - 36)
    # The clip used to stay at 440x286, which clipped all chat content to the
    # original 484x330 box when maximized. Rebuild it for the new size.
    $clipRect = [System.Windows.Rect]::new(4.0, 4.0, [Math]::Max(10.0, $Frame.Width - 8.0), [Math]::Max(10.0, $Frame.Height - 8.0))
    $Frame.Clip = [System.Windows.Media.RectangleGeometry]::new($clipRect, 26.0, 26.0)
    if ($script:Membrane) { $script:Membrane.SetFrame([float]$Frame.Width, [float]$Frame.Height) }
    Update-PeaAnchor
    if ($script:FaceLayer) {
        $script:FaceLayer.Width = $window.ActualWidth
        $script:FaceLayer.Height = $window.ActualHeight
    }
})
```

- [ ] **Step 4: Remember manual resize while expanded**

Replace inside `$ResizeGrip.Add_MouseMove` (after the two width/height assignments):

```powershell
    $window.Height = [Math]::Max(314.0, [Math]::Min(1840.0, $script:resizeOrigin[3] + ($p.Y - $script:resizeOrigin[1])))
```

with:

```powershell
    $window.Height = [Math]::Max(314.0, [Math]::Min(1840.0, $script:resizeOrigin[3] + ($p.Y - $script:resizeOrigin[1])))
    if ($script:Expanded) { $script:ExpandedSize = [System.Windows.Size]::new($window.Width, $window.Height) }
```

- [ ] **Step 5: Size the window on expand; queue compact restore on collapse**

Replace `function Expand-Chat { ... }` and `function Collapse-Chat { ... }` with:

```powershell
function Expand-Chat {
    if ($script:Expanded) { return }
    $script:Expanded = $true
    $script:RestoreCompact = $false
    if (-not $script:ExpandedSize) { $script:ExpandedSize = [System.Windows.Size]::new(760.0, 540.0) }
    if ($window.WindowState -ne 'Maximized') {
        $window.Width = $script:ExpandedSize.Width
        $window.Height = $script:ExpandedSize.Height
    }
    $PeaCanvas.Visibility = 'Collapsed'
    $BodyPath.Visibility = 'Visible'
    $origin = Get-SlopPeaOrigin
    $script:Membrane.Expand($origin[0], $origin[1])
    Set-SlopFrameTarget -State $script:Motion -Target 'open'
    Set-SlopBaseCondition -State $script:Motion -Streaming $script:IsStreaming -ChatOpen $true -Stalled $false
    $InputBox.Focus() | Out-Null
}

function Collapse-Chat {
    if (-not $script:Expanded) { return }
    Request-StopStream
    $script:Expanded = $false
    $script:RestoreCompact = $true
    $origin = Get-SlopPeaOrigin
    $script:Membrane.Collapse($origin[0], $origin[1])
    Set-SlopFrameTarget -State $script:Motion -Target 'closed'
    Set-SlopBaseCondition -State $script:Motion -Streaming $script:IsStreaming -ChatOpen $false -Stalled $false
}
```

- [ ] **Step 6: Restore compact size only after the collapse finishes**

Replace the closed-state branch in `Apply-SlopMotion`:

```powershell
    if ($script:Membrane.IsClosed -and -not $script:Expanded -and $script:Frame.Opacity -lt 0.02) {
        $BodyPath.Visibility = 'Collapsed'
```

with:

```powershell
    if ($script:Membrane.IsClosed -and -not $script:Expanded -and $script:Frame.Opacity -lt 0.02) {
        if ($script:RestoreCompact) {
            $script:RestoreCompact = $false
            if ($window.WindowState -ne 'Maximized') {
                $window.Width = 484.0
                $window.Height = 330.0
            }
        }
        $BodyPath.Visibility = 'Collapsed'
```

- [ ] **Step 7: Update the shell check**

In `tests/slop-shell-check.ps1` line 15, replace the element list with:

```powershell
    foreach ($name in @('BodyPath','HeadHighlight','Frame','SettingsDot','PinDot','CloseDot','ControlDots','ChatScroll','ChatStack','InputBox','MicBtn','AttachBtn','StatusDot','ResizeGrip','PeaCanvas','GroundShadow')) {
```

Replace line 39:

```powershell
Assert-True ($src -match 'RectangleGeometry Rect="4,4,440,286" RadiusX="26" RadiusY="26"') 'content has a static rounded clip'
```

with:

```powershell
Assert-True ($src -match '\$Frame\.Clip\s*=') 'content clip is rebuilt on resize'
Assert-True ($src -match 'Add_SizeChanged(?s:.*?)\$Frame\.Clip\s*=') 'clip rebuild lives in the SizeChanged handler'
Assert-True ($src -notmatch 'MaxHeight="235"') 'chat scroll is not height-capped'
Assert-True ($src -match '\$script:ExpandedSize') 'expanded size is remembered'
Assert-True ($src -match '\$script:RestoreCompact') 'compact size restores after collapse'
```

- [ ] **Step 8: Run tests**

Run: `cd .; pwsh -NoProfile -File tests/slop-shell-check.ps1`
Expected: `ALL SHELL CHECKS PASSED`, exit 0.

- [ ] **Step 9: Commit**

```powershell
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "fix(slop): dynamic content clip and flexible expanded window"
```

---

### Task 5: Richer chat bubbles and profile shortcut chips

**Files:**
- Modify: `src/Slop.ps1` (XAML chat tile, `Add-Bubble`, new `Insert-SlopShortcut`, wiring)
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Add the shortcut strip to the chat tile**

Replace:

```xml
        <Border Grid.Row="1" Margin="18,8,18,4" CornerRadius="14" Background="#1AFFFFFF" BorderBrush="#33FFFFFF" BorderThickness="1">
          <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto" Margin="4">
            <StackPanel x:Name="ChatStack"/>
          </ScrollViewer>
        </Border>
```

with:

```xml
        <Border Grid.Row="1" Margin="18,8,18,4" CornerRadius="14" Background="#1AFFFFFF" BorderBrush="#33FFFFFF" BorderThickness="1">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <WrapPanel x:Name="ShortcutsStrip" Grid.Row="0" Margin="8,6,8,2"/>
            <ScrollViewer x:Name="ChatScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="8">
              <StackPanel x:Name="ChatStack"/>
            </ScrollViewer>
          </Grid>
        </Border>
```

- [ ] **Step 2: Replace Add-Bubble and add the insert helper**

Replace the existing `function Add-Bubble { ... }` (lines 605–639) with:

```powershell
function Insert-SlopShortcut {
    param([Parameter(Mandatory)][string]$Command)
    $InputBox.Text = if ($InputBox.Text) { $InputBox.Text.TrimEnd() + ' ' + $Command } else { $Command }
    $InputBox.CaretIndex = $InputBox.Text.Length
    $InputPlaceholder.Visibility = 'Collapsed'
    $InputBox.Focus() | Out-Null
}

function Add-Bubble {
    param(
        [Parameter(Mandatory)][string]$Text,
        [bool]$IsUser,
        [string]$Emoji
    )
    if (-not $Emoji) { $Emoji = if ($IsUser) { '👤 ' } else { '🧠 ' } }
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $border.Padding = [System.Windows.Thickness]::new(12)
    $border.Margin = [System.Windows.Thickness]::new(0,0,0,10)
    if ($IsUser) {
        $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3B82F6')
        $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#93C5FD')
        $border.HorizontalAlignment = 'Right'
        $border.Margin = [System.Windows.Thickness]::new(48,0,0,10)
    } else {
        $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2AFFFFFF')
        $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#44FFFFFF')
        $border.HorizontalAlignment = 'Left'
        $border.Margin = [System.Windows.Thickness]::new(0,0,48,10)
    }
    $border.BorderThickness = [System.Windows.Thickness]::new(1)

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = "$Emoji$Text"
    $tb.Foreground = [System.Windows.Media.Brushes]::White
    $tb.TextWrapping = 'Wrap'
    $tb.FontSize = 12
    if ($Text -match '^(>|&|\$)\s|^(startslop|stopslop|slopstatus|verify|review|kickoff|sign out)\b') {
        $tb.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    }
    $border.Child = $tb
    $ChatStack.Children.Add($border) | Out-Null
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
    $ChatScroll.ScrollToEnd()
    return $border
}
```

- [ ] **Step 3: Create the shortcut chips**

Add `$ShortcutsStrip = $window.FindName('ShortcutsStrip')` next to the other `FindName` calls, then add after `Add-SlopThoughtBubble`/before `Add-Bubble`:

```powershell
$script:ShortcutCommands = @('startslop','stopslop','slopstatus','verify','review','kickoff','sign out')
foreach ($cmd in $script:ShortcutCommands) {
    $chip = New-Object System.Windows.Controls.Button
    $chip.Content = $cmd
    $chip.Style = $window.Resources['SlopButton']
    $chip.FontSize = 9
    $chip.Padding = [System.Windows.Thickness]::new(6,2,6,2)
    $chip.Margin = [System.Windows.Thickness]::new(0,0,5,4)
    $chip.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#22FFFFFF')
    $chip.Foreground = [System.Windows.Media.Brushes]::White
    $chip.Tag = $cmd
    $chip.Add_Click({ param($s,$e) Insert-SlopShortcut -Command $s.Tag })
    $ShortcutsStrip.Children.Add($chip) | Out-Null
}
```

- [ ] **Step 4: Update the shell check**

Replace `'PeaCanvas','GroundShadow')) {` with `'PeaCanvas','GroundShadow','ShortcutsStrip')) {` in the XAML element list (line 15). Then append before the final failure check:

```powershell
Assert-True ($src -match 'function Insert-SlopShortcut') 'shortcut chips only insert text, never execute'
Assert-True ($src -match "startslop.*stopslop.*slopstatus") 'profile helper shortcuts are present'
Assert-True ($src -match "Add-Bubble|function Add-Bubble") 'bubble renderer exists'
```

- [ ] **Step 5: Run tests**

Run: `cd .; pwsh -NoProfile -File tests/slop-shell-check.ps1`
Expected: `ALL SHELL CHECKS PASSED`, exit 0.

- [ ] **Step 6: Commit**

```powershell
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "feat(slop): richer chat bubbles and profile shortcut chips"
```

---

### Task 6: Thought bubbles — system-only content and correct sizing

**Files:**
- Modify: `src/Slop.ps1` (remove canned lines, rewrite `Add-SlopThoughtBubble`)

- [ ] **Step 1: Remove canned facts/jokes**

Replace:

```powershell
$script:ThoughtLines = @(
    'Did you know: honey never spoils.'
    'Tip: Ctrl+Shift+T reopens a closed tab.'
    'Joke: why do programmers prefer dark mode? light attracts bugs.'
    'Fact: octopuses have three hearts.'
    'Idea: take a 2-minute stretch break.'
    'News: stay curious, stay kind.'
    'Reminder: drink some water.'
)
```

with:

```powershell
# Thought bubbles are reserved for System Sense alerts only. No canned trivia.
```

- [ ] **Step 2: Rewrite Add-SlopThoughtBubble**

Replace the existing `function Add-SlopThoughtBubble { ... }` with:

```powershell
function Add-SlopThoughtBubble {
    param([Parameter(Mandatory)][string]$Text)
    $expanded = $script:Expanded
    $maxWidth = if ($expanded) { 320.0 } else { 190.0 }
    $fontSize = if ($expanded) { 10 } else { 8 }

    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $b.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2A1E293B')
    $b.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#55F59E0B')
    $b.BorderThickness = [System.Windows.Thickness]::new(1)
    $b.Padding = [System.Windows.Thickness]::new(12,8,12,8)
    $b.IsHitTestVisible = $false
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = "⚠️ $Text"
    $tb.Foreground = [System.Windows.Media.Brushes]::White
    $tb.FontSize = $fontSize
    $tb.FontStyle = 'Italic'
    $tb.TextWrapping = 'Wrap'
    $tb.MaxWidth = $maxWidth
    $b.Child = $tb
    $b.Opacity = 0
    $Stage.Children.Add($b) | Out-Null

    $b.Measure([System.Windows.Size]::new($maxWidth, 400.0))
    $bw = $b.DesiredSize.Width
    $bh = $b.DesiredSize.Height
    if ($expanded) {
        $x = 42.0
        $y = 62.0
    }
    else {
        $pea = Get-SlopPeaOrigin
        $x = $pea[0] - ($bw / 2.0)
        $y = $pea[1] - $bh - 18.0
        $x = [Math]::Max(8.0, [Math]::Min($x, $window.ActualWidth - $bw - 8.0))
        $y = [Math]::Max(8.0, $y)
    }
    [System.Windows.Controls.Canvas]::SetLeft($b, $x)
    [System.Windows.Controls.Canvas]::SetTop($b, $y)
    $b.Tag = @{ Born = [DateTime]::UtcNow }
}
```

- [ ] **Step 3: Update the shell check**

Append before the final failure check:

```powershell
Assert-True ($src -notmatch "Did you know: honey never spoils") 'canned trivia is removed'
Assert-True ($src -match "if \(\$expanded\) \{ 10 \} else \{ 8 \}") 'bubble font is 8 compact / 10 expanded'
Assert-True ($src -match 'TextWrapping = ''Wrap''') 'bubble text wraps instead of clipping'
```

- [ ] **Step 4: Run tests**

Run: `cd .; pwsh -NoProfile -File tests/slop-shell-check.ps1`
Expected: `ALL SHELL CHECKS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "feat(slop): system-only thought bubbles with correct sizing"
```

---

### Task 7: Wire Sense + expressions into the shell

**Files:**
- Modify: `src/Slop.ps1` (dot-source, tray toggle, timer loop)
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Dot-source Sense**

Replace:
```powershell
. (Join-Path $PSScriptRoot 'Slop.Motion.ps1')
```
with:
```powershell
. (Join-Path $PSScriptRoot 'Slop.Motion.ps1')
. (Join-Path $PSScriptRoot 'Slop.Sense.ps1')
```

- [ ] **Step 2: Add cached toggle state**

Replace:
```powershell
$script:ThoughtAccumulator = 0.0
```
with:
```powershell
$script:SenseEnabled = Get-SlopSenseEnabled
$script:SenseAccumulator = 0.0
```

- [ ] **Step 3: Add the tray toggle**

Replace `function Minimize-ToTray { ... }` with:

```powershell
function Minimize-ToTray {
    if ($script:TrayIcon) { return }
    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayIcon.Text = 'S.L.O.P.'
    try { $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application } catch { }
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $restore = $menu.Items.Add('Restore')
    $restore.Add_Click({ $window.Show(); $window.WindowState = 'Normal'; $window.Activate() })
    $senseLabel = if ($script:SenseEnabled) { 'System Sense: On' } else { 'System Sense: Off' }
    $script:TraySenseItem = $menu.Items.Add($senseLabel)
    $script:TraySenseItem.Add_Click({
        # Publish to script scope first: a WinForms Add_Click scriptblock does
        # not close over function locals in PowerShell.
        $script:SenseEnabled = -not $script:SenseEnabled
        Set-SlopSenseEnabled -Enabled $script:SenseEnabled
        $script:SenseAccumulator = 0.0
        if ($script:SenseEnabled) {
            $script:TraySenseItem.Text = 'System Sense: On'
            Add-SlopThoughtBubble -Text 'System Sense online — watching thresholds and listeners.'
        } else {
            $script:TraySenseItem.Text = 'System Sense: Off'
        }
    })
    $exit = $menu.Items.Add('Exit')
    $exit.Add_Click({ if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() }; Stop-Process -Id $PID -Force })
    $script:TrayIcon.ContextMenuStrip = $menu
    $script:TrayIcon.Visible = $true
    $script:TrayIcon.Add_DoubleClick({ $window.Show(); $window.WindowState = 'Normal'; $window.Activate() })
    $window.Hide()
}
```

The Sense menu item is stored as `$script:TraySenseItem` rather than a function local because PowerShell event-handler scriptblocks do not capture enclosing function locals. All state the handler touches is script-scoped.

- [ ] **Step 4: Replace the timer loop's bubble logic**

Replace:

```powershell
    # thought bubbles when idle
    if ($script:Motion.Mood -eq 'idle' -and -not $script:Expanded) {
        $script:ThoughtAccumulator += $dt
        if ($script:ThoughtAccumulator -ge (25.0 + (Get-Random -Minimum 0 -Maximum 20))) {
            $script:ThoughtAccumulator = 0.0
            Add-SlopThoughtBubble -Text ($script:ThoughtLines | Get-Random)
        }
    }
```

with:

```powershell
    # System Sense: one cached evaluation per minute when opted in.
    if ($script:SenseEnabled) {
        $script:SenseAccumulator += $dt
        if ($script:SenseAccumulator -ge 60.0) {
            $script:SenseAccumulator = 0.0
            foreach ($alert in @(Invoke-SlopSenseScan)) {
                if ([string]::IsNullOrWhiteSpace($alert)) { continue }
                Add-SlopThoughtBubble -Text $alert
                break
            }
        }
    } else {
        $script:SenseAccumulator = 0.0
    }
```

- [ ] **Step 5: Pass the face expression to the face layer**

Replace:
```powershell
    Update-SlopFaceLayer -Target $script:FaceLayer -Time ([DateTime]::UtcNow.Ticks / 1e7) -Speed $speed -Width $window.Width -Height $window.Height -Frozen:$frozen
```
with:
```powershell
    Update-SlopFaceLayer -Target $script:FaceLayer -Time ([DateTime]::UtcNow.Ticks / 1e7) -Speed $speed -Width $window.Width -Height $window.Height -Frozen:$frozen -Pattern $script:Motion.FaceExpression
```

- [ ] **Step 6: Update the shell check**

Append before the final failure check:

```powershell
Assert-True ($src -match 'Slop\.Sense\.ps1') 'System Sense module is dot-sourced'
Assert-True ($src -match 'System Sense: On') 'tray toggle is wired'
Assert-True ($src -match 'SenseAccumulator -ge 60\.0') 'sense runs once a minute'
Assert-True ($src -match 'Pattern \$script:Motion\.FaceExpression') 'motion phase drives face expression'
Assert-True ($src -notmatch 'ThoughtAccumulator') 'old random thought timer is gone'
```

- [ ] **Step 7: Run tests**

Run: `cd .; pwsh -NoProfile -File tests/slop-shell-check.ps1`
Expected: `ALL SHELL CHECKS PASSED`, exit 0.

- [ ] **Step 8: Commit**

```powershell
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "feat(slop): wire System Sense, tray toggle, and face expressions"
```

---

### Task 8: Full verification and live maximize pass

**Files:** none (verification only). Update `docs/architecture.md` if a new module needs documenting.

- [ ] **Step 1: Run every headless suite**

```powershell
cd .
foreach ($t in 'slop-shell-check','slop-motion-check','slop-face-check','slop-sense-check','slop-lifecycle-check','slop-opencode-check','slop-frame-check','slop-silhouette-check','slop-control-check') {
    $r = (pwsh -NoProfile -File "tests/$t.ps1" 2>&1 | Select-Object -Last 1)
    Write-Host "$t : $r"
}
```
Expected: every line ends in PASSED / PASS with `$LASTEXITCODE` 0.

- [ ] **Step 2: Run the verify gate**

```powershell
pwsh -NoProfile -File <agent-home>/scripts/verify.ps1
```
Expected: `=== VERIFY COMPLETE ===` / `All gates passed.`

- [ ] **Step 3: Live check**

```powershell
pwsh -NoProfile -File tools/slop-control.ps1 -Action Start
```
Then manually:
1. Click the pea — expanded window should be ~760×540 with the shortcut strip visible.
2. Press `□` — maximized. Chat input and Send must remain visible; no clipped content.
3. Click `□` again — back to remembered size.
4. Click `_` — collapses to pea; compact 484×330 restored after the animation.
5. Tray icon → `System Sense: On` — after a minute, a system alert bubble may appear; toggle off stops it.
6. Watch idle for 30s — at least several distinct actions (hop, sit, stretch, blink, tilt, peek) and face rearrangements.

- [ ] **Step 4: Stop and commit docs if needed**

```powershell
pwsh -NoProfile -File tools/slop-control.ps1 -Action Status
git status --short
```
Expected: Slop stopped cleanly, no orphan `pwsh` holding the app.

- [ ] **Step 5: Commit**

```powershell
git add docs/architecture.md
git commit -m "docs(slop): update architecture for sense module"
```
Skip if nothing changed.

---

## Self-review notes

- Every spec section maps to a task: System Sense → T1/T7, thought bubbles → T6, always-alive motion → T2/T3, expanded/full screen → T4, richer chat → T5, tests → T8.
- The old shell assertion for the fixed clip is explicitly replaced in T4 Step 7. The XAML keeps its static initial clip (SizeChanged replaces it on first layout); the new assertion checks that a rebuild happens inside the handler, not that the literal disappears. Requiring the literal to disappear would fail against the untouched XAML.
- The CPU-streak test in T1 was validated headlessly against the planned threshold logic. Reusing `$base` for both samples resets `CpuHighStreak` to 0 and never fires the CPU alert; the test now passes an explicit baseline of 1 for the second sample.
- The forced-hop threshold was raised from `-0.005` to `-0.5` (T2). At 30 fps a naturally expiring `NextHopIn` lands near `-0.033`, so the old threshold made hops swallow nearly all random actions. `Set-SlopTargetShape` now injects `-1.0` to preserve deliberate morph hops, and the two motion-test injections were updated to match.
- Event-handler state in T7 is script-scoped (`$script:TraySenseItem`) because PowerShell handler scriptblocks do not capture function locals.
- `Add-SlopThoughtBubble` is called from the tray toggle (T7) and the timer (T7), both defined after the function in T6.
- Function names are consistent across tasks: `Get-SlopSenseEnabled`, `Set-SlopSenseEnabled`, `Invoke-SlopSenseScan`, `Get-SlopIdleAction`, `Complete-SlopIdleAction`, `Update-SlopFaceLayer -Pattern`, `Insert-SlopShortcut`.
- No subagents are used, per the standing user cost constraint.


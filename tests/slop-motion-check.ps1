# Headless checks for S.L.O.P. motion math. No WPF; Pester-backed.
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

# 1. spring factory + convergence
$s = New-SlopSpring 0.0 160 20
Assert-True ($s.Value -eq 0.0 -and $s.Target -eq 0.0 -and $s.Velocity -eq 0.0) 'spring starts settled'
$s.Target = 1.0
for ($i = 0; $i -lt 240; $i++) { Step-SlopSpring $s (1.0 / 120.0) | Out-Null }
Assert-True ([Math]::Abs($s.Value - 1.0) -lt 0.01) "spring converges to target (value=$([Math]::Round($s.Value,4)))"

# 2. hop cycle completes and returns to ground
$m = New-SlopMotionState
$m.NextHopIn = -1.0
# shape changes are signal-driven now (no random idle morph), so request one via
# the same resolver the app uses and let it land mid-hop.
Set-SlopBaseCondition -State $m -Streaming $true -ChatOpen $false -Stalled $false
$sawAir = $false; $sawSquat = $false; $sawCrossfade = $false; $endY = 99.0
$signalSynced = $false
for ($i = 0; $i -lt 480; $i++) {
    Update-SlopMotionState -State $m -Dt (1.0 / 120.0)
    # first hop is forced immediate below; a random short second hop made the
    # end-of-window ground assertion flaky, so pin idle once one hop completes.
    if ($m.HopCount -ge 1) { $m.NextHopIn = 99.0 }
    if ($m.Phase -eq 'airborne' -and -not $signalSynced) {
        Sync-SlopSignal -State $m | Out-Null
        $signalSynced = $true
    }
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
$r.NextHopIn = -1.0
Update-SlopMotionState -State $r -Dt (1.0 / 120.0) -ReducedMotion
Assert-True ($r.Y -eq 0.0 -and $r.Squash.Value -eq $r.Squash.Target) 'reduced motion snaps springs'

# 6b. organic body springs
Set-SlopFrameTarget -State $m -Target 'open'
Assert-True ($m.Open.Target -eq 1.0) 'open target expands the organic body'
Set-SlopFrameTarget -State $m -Target 'closed'
Assert-True ($m.Open.Target -eq 0.0) 'closed target returns the body to the pea'
$r2 = New-SlopMotionState
Set-SlopFrameTarget -State $r2 -Target 'open'
Update-SlopMotionState -State $r2 -Dt (1.0 / 120.0) -ReducedMotion
Assert-True ($r2.Open.Value -eq 1.0) 'reduced motion snaps the body open'
$s2 = New-SlopMotionState
Set-SlopBaseCondition -State $s2 -Streaming $true -ChatOpen $true -Stalled $false
Update-SlopMotionState -State $s2 -Dt (1.0 / 120.0)
Assert-True ($s2.OpenPulse.Target -gt 0.0) 'streaming drives a body pulse'

# 7. two-axis signal table
function Assert-Signal {
    param([string]$Color, [string]$Shape, [string]$Label)
    $e = Get-SlopSignal -State $m
    Assert-True ($e.Color -eq $Color -and $e.Shape -eq $Shape) `
        "$Label => $Color/$Shape (got $($e.Color)/$($e.Shape))"
}

$s = New-SlopMotionState
$script:m = $s
Set-SlopBaseCondition -State $m -Streaming $false -ChatOpen $false -Stalled $false
Assert-Signal 'idle' 'circle' 'idle'
Set-SlopBaseCondition -State $m -Streaming $false -ChatOpen $true -Stalled $false
Assert-Signal 'idle' 'square' 'chat-open changes shape only'
Set-SlopBaseCondition -State $m -Streaming $true -ChatOpen $true -Stalled $false
Assert-Signal 'working' 'triangle' 'streaming outranks chat-open'
Set-SlopBaseCondition -State $m -Streaming $true -ChatOpen $false -Stalled $true
Assert-Signal 'thinking' 'rect' 'stalled signals attention in amber'

# 8. transient overlay wins, expires, and returns to base
Set-SlopSignal -State $m -Color 'success' -Shape 'square' -HoldSeconds 1.0
Assert-Signal 'success' 'square' 'success overlay'
for ($i=0;$i -lt 150;$i++) { Update-SlopMotionState -State $m -Dt (1.0/120.0) }
Assert-Signal 'thinking' 'rect' 'overlay expires to stalled attention'

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

# 9. a new request pre-empts an active overlay
Set-SlopSignal -State $m -Color 'error' -Shape 'rect' -HoldSeconds 2.0
Clear-SlopSignal -State $m
Set-SlopBaseCondition -State $m -Streaming $true -ChatOpen $false -Stalled $false
Assert-Signal 'working' 'triangle' 'new request clears overlay'

# 10. canonical shape index mapping
Set-SlopTargetShape -State $m -Shape 'rect'
Assert-True ($m.TargetShape -eq 3 -and $m.Weights[3].Target -eq 1.0 -and $m.Weights[0].Target -eq 0.0) `
    'canonical shape index maps rect to weights[3]'

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

Describe 'Slop motion math' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}

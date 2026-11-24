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

$approval = New-SlopMotionState
Set-SlopSignalEvent -State $approval -Id 'permission:1:p1' -Kind approval -Status 'Approval needed'
Check-Cadence 'sticky approval uses 30 fps' 33 $approval

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

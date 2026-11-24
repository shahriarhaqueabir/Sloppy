# tests/slop-sense-check.ps1
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
. (Join-Path $PSScriptRoot '..\src\Slop.Sense.ps1')

$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
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

Describe 'Slop System Sense' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}

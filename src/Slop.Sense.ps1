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

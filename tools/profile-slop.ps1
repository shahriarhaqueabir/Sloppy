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

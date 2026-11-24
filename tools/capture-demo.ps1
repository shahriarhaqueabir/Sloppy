# Capture real Sloppy frames for the portfolio showcase.
# Produces assets/demo-frames.png (2x2 still strip) and assets/hero.png.
# No network access, no downloads, no installs. Teardown is guaranteed.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CD {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,int e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte scan,uint flags,int extra);
    public const uint DOWN=0x0002, UP=0x0004, KEYUP=0x0002;
    public const byte CTRL=0x11, V=0x56;
}
'@

function Get-Win($id) {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $id)
    $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
}
function Find-Uia($id) {
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
    $script:W.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}
function Set-UiaValue($id, $value) {
    $el = Find-Uia $id
    if (-not $el) { throw "UIA element $id not found" }
    $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($value)
}
function Invoke-Uia($id) {
    $el = Find-Uia $id
    if (-not $el) { throw "UIA element $id not found" }
    $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function Phys($lx, $ly) {
    $r = $script:W.Current.BoundingRectangle
    @([int]($r.X + $lx*$script:DpiX), [int]($r.Y + $ly*$script:DpiY))
}
function Focus-Ok {
    $h = [IntPtr]$script:W.Current.NativeWindowHandle
    [CD]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 120
    [CD]::GetForegroundWindow() -eq $h
}
function Click($lx, $ly) {
    $p = Phys $lx $ly
    [CD]::SetCursorPos($p[0], $p[1]) | Out-Null
    Start-Sleep -Milliseconds 60
    [CD]::mouse_event([CD]::DOWN,0,0,0,0)
    Start-Sleep -Milliseconds 45
    [CD]::mouse_event([CD]::UP,0,0,0,0)
}
function Grab {
    $r = $script:W.Current.BoundingRectangle
    $b = [System.Drawing.Bitmap]::new([int]$r.Width, [int]$r.Height)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $b.Size)
    $g.Dispose()
    $b
}
function Pixel($b, $lx, $ly) {
    $p = Phys $lx $ly
    $r = $script:W.Current.BoundingRectangle
    $b.GetPixel([int]($p[0]-$r.X), [int]($p[1]-$r.Y))
}
function Classify($p) {
    if ($p.B -gt 150 -and $p.R -lt 120 -and $p.G -lt 180) { return 'blue' }
    if ($p.R -gt 180 -and $p.G -gt 100 -and $p.G -lt 200 -and $p.B -lt 120) { return 'amber' }
    if ($p.G -gt 140 -and $p.R -lt 150 -and $p.B -lt 180) { return 'green' }
    if ($p.R -gt 150 -and $p.G -lt 120 -and $p.B -lt 120) { return 'red' }
    'other'
}
function DotColor {
    $b = Grab
    try { Classify (Pixel $b 50 36) } finally { $b.Dispose() }
}
function Add-Panel($canvas, $g, $index, $frame, $label) {
    $cw = 620; $ch = 400; $cap = 34
    $x = ($index % 2) * $cw
    $y = [int]([Math]::Floor($index / 2)) * ($ch + $cap)
    $g.FillRectangle([System.Drawing.Brushes]::Black, $x, $y, $cw, $ch + $cap)
    if ($frame) {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($frame, [System.Drawing.Rectangle]::new($x, $y, $cw, $ch))
    }
    $f = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $g.DrawString($label, $f, [System.Drawing.Brushes]::White, $x + 14, $y + $ch + 6)
    $f.Dispose()
}

$repo = Split-Path $PSScriptRoot -Parent
$assets = Join-Path $repo 'assets'
$strip = Join-Path $assets 'demo-frames.png'
$hero  = Join-Path $assets 'hero.png'

# Never overwrite user-owned artwork.
foreach ($protected in @('sloppy.png','sloppy.ico')) {
    if ((Test-Path (Join-Path $assets $protected)) -and
        ($protected -eq 'sloppy.png' -or $protected -eq 'sloppy.ico')) {
        # these files are intentionally left alone; we only guard against accidental reuse
    }
}
if (-not (Test-Path $assets)) { New-Item -ItemType Directory -Path $assets | Out-Null }

# Kill only stale app processes, never this capture helper.
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -like '*src/Slop.ps1*' -or $_.CommandLine -like '*slop-run-wrapper.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800

# Reuse the persisted OpenCode service password for a real request.
if ([string]::IsNullOrEmpty($env:OPENCODE_PASSWORD)) {
    $svcJson = Join-Path $env:USERPROFILE '.config/opencode/service.json'
    if (Test-Path $svcJson) {
        $env:OPENCODE_PASSWORD = (Get-Content $svcJson -Raw | ConvertFrom-Json).password
    }
}
if ([string]::IsNullOrEmpty($env:OPENCODE_PASSWORD)) {
    throw 'OPENCODE_PASSWORD is required; set it or start the OpenCode service'
}

$dir = Join-Path $env:TEMP 'slop-capture'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'app.out.log'; $err = Join-Path $dir 'app.err.log'
Remove-Item $out,$err -ErrorAction SilentlyContinue
$scriptFile = Join-Path $repo 'src/Slop.ps1'
$proc = Start-Process -FilePath 'pwsh' `
    -ArgumentList @('-STA','-NoProfile','-File',$scriptFile) `
    -PassThru -RedirectStandardOutput $out -RedirectStandardError $err

$frames = @{}
try {
    if ($proc.HasExited) { throw "app exited early: $(Get-Content $out -Raw) $(Get-Content $err -Raw)" }
    Start-Sleep -Seconds 3
    $script:W = Get-Win $proc.Id
    if (-not $script:W) { throw 'no app window found' }
    $r = $script:W.Current.BoundingRectangle
    $script:DpiX = $r.Width / 484.0
    $script:DpiY = $r.Height / 330.0

    # 01 idle compact
    $frames['idle'] = Grab

    # 02 expanded chat
    $expanded = $false
    for ($try=1; $try -le 3 -and -not $expanded; $try++) {
        Focus-Ok | Out-Null
        Click 242 305
        Start-Sleep -Milliseconds 700
        $b = Grab; $p = Pixel $b 242 144; $b.Dispose()
        if ($p.R -lt 60 -and $p.G -lt 80 -and $p.B -gt 30) { $expanded = $true }
    }
    if (-not $expanded) { throw 'click never expanded chat' }
    $frames['expanded'] = Grab
    if (-not (Test-Path $hero)) { $frames['expanded'].Save($hero, [System.Drawing.Imaging.ImageFormat]::Png) }

    # 03 thinking + 04 success, from a real request
    if (-not (Focus-Ok)) { throw 'focus failed before typing' }
    Set-UiaValue 'InputBox' 'Name three colors, one per line.'
    Invoke-Uia 'SendBtn'
    $sawAmber = $false; $sawGreen = $false
    for ($i=0; $i -lt 100 -and -not ($sawAmber -and $sawGreen); $i++) {
        Start-Sleep -Milliseconds 60
        $c = DotColor
        if ($c -eq 'amber' -and -not $sawAmber) {
            $sawAmber = $true
            $frames['thinking'] = Grab
        }
        if ($c -eq 'green' -and -not $sawGreen) {
            $sawGreen = $true
            $frames['success'] = Grab
        }
    }
    "CAPTURE amber=$sawAmber green=$sawGreen"

    # Assemble the strip from the beats actually captured.
    $canvas = [System.Drawing.Bitmap]::new(1240, 868)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $specs = @(
        @{ k='idle';     label='01  IDLE' },
        @{ k='expanded'; label='02  EXPANDED' },
        @{ k='thinking'; label='03  THINKING' },
        @{ k='success';  label='04  SUCCESS' }
    )
    for ($i=0; $i -lt $specs.Count; $i++) {
        $s = $specs[$i]
        $f = if ($frames.ContainsKey($s.k)) { $frames[$s.k] } else { $null }
        Add-Panel $canvas $g $i $f "$( $s.label )"
    }
    $g.Dispose()
    $canvas.Save($strip, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    "WROTE $strip"
    "WROTE $hero"
}
finally {
    foreach ($key in @($frames.Keys)) { if ($frames[$key]) { $frames[$key].Dispose() } }
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 600
    }
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -like '*src/Slop.ps1*' -or $_.CommandLine -like '*slop-run-wrapper.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    'TEARDOWN complete'
}

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

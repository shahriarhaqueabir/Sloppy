# src/Slop.Silhouette.ps1
# Sloppy organic body geometry. Pure math only - no WPF types, safe to dot-source headlessly.
$ErrorActionPreference = 'Stop'

# Anchors are in frame-local coordinates: the content Grid is 300 x 420 at Canvas (10,10).
# Clockwise from the head shelf. Eight anchors are enough for a soft, asymmetrical blob.
# Ordered clockwise from the upper-left so the head shelf grows out of the
# pea's upper-left instead of swinging around the body during opening.
$SlopCompactAnchors = @(
    @{ X = 141.0; Y = 404.0 }   # upper-left  -> head shelf left
    @{ X = 150.0; Y = 400.0 }   # top         -> head shelf right
    @{ X = 159.0; Y = 404.0 }   # upper-right
    @{ X = 163.0; Y = 413.0 }   # right       -> right flank
    @{ X = 159.0; Y = 422.0 }   # lower-right
    @{ X = 150.0; Y = 426.0 }   # bottom
    @{ X = 141.0; Y = 422.0 }   # lower-left  -> left flank
    @{ X = 137.0; Y = 413.0 }   # left        -> upper-left rise
)

$SlopExpandedAnchors = @(
    @{ X = 60.0;  Y = 2.0 }    # wide flat head shelf, left end
    @{ X = 102.0; Y = 2.0 }    # wide flat head shelf, right end
    @{ X = 288.0; Y = 12.0 }
    @{ X = 296.0; Y = 220.0 }
    @{ X = 296.0; Y = 420.0 }
    @{ X = 46.0;  Y = 420.0 }
    @{ X = 4.0;   Y = 220.0 }
    @{ X = 16.0;  Y = 12.0 }   # rise from upper-left into the head shelf
)

function Format-SlopNumber {
    param([double]$Value)
    return $Value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-SlopSilhouettePoints {
    param(
        [Parameter(Mandatory)][double]$Open,
        [double]$Width = 300.0,
        [double]$Height = 420.0,
        [double]$Pulse = 0.0,
        [double]$Lean = 0.0
    )
    $o = [Math]::Min(1.0, [Math]::Max(0.0, $Open))
    $sx = $Width / 300.0
    $sy = $Height / 420.0
    $cx = $Width / 2.0
    $cy = 240.0 * $sy
    $points = @()
    for ($i = 0; $i -lt 8; $i++) {
        $c = $SlopCompactAnchors[$i]
        $e = $SlopExpandedAnchors[$i]
        # Compact pea stays pea-sized and centred; expanded body fills the frame.
        # Interpolating between the two keeps the pea from stretching on wide frames.
        $xCompact = $cx + ($c.X - 150.0)
        $xExpanded = $e.X * $sx
        $x = $xCompact + ($xExpanded - $xCompact) * $o
        $y = ($c.Y + ($e.Y - $c.Y) * $o) * $sy
        $y = $cy + ($y - $cy) * (1.0 + 0.05 * $Pulse)
        $x = $x + $Lean * ($y - $cy) * 0.004
        $points += @{ X = $x; Y = $y }
    }
    return $points
}

function Convert-SlopSilhouetteToPathData {
    param([Parameter(Mandatory)][object[]]$Points)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append('M ').Append((Format-SlopNumber $Points[0].X)).Append(' ').Append((Format-SlopNumber $Points[0].Y))
    $n = $Points.Count
    for ($i = 0; $i -lt $n; $i++) {
        $prev = $Points[($i - 1 + $n) % $n]
        $p0   = $Points[$i]
        $p1   = $Points[($i + 1) % $n]
        $next = $Points[($i + 2) % $n]
        $c1x = $p0.X + ($p1.X - $prev.X) / 6.0
        $c1y = $p0.Y + ($p1.Y - $prev.Y) / 6.0
        $c2x = $p1.X - ($next.X - $p0.X) / 6.0
        $c2y = $p1.Y - ($next.Y - $p0.Y) / 6.0
        [void]$sb.Append(' C ').Append((Format-SlopNumber $c1x)).Append(' ').Append((Format-SlopNumber $c1y))
        [void]$sb.Append(' ').Append((Format-SlopNumber $c2x)).Append(' ').Append((Format-SlopNumber $c2y))
        [void]$sb.Append(' ').Append((Format-SlopNumber $p1.X)).Append(' ').Append((Format-SlopNumber $p1.Y))
    }
    [void]$sb.Append(' Z')
    return $sb.ToString()
}

function Test-SlopSilhouetteContains {
    param(
        [Parameter(Mandatory)][object[]]$Points,
        [Parameter(Mandatory)][double]$X,
        [Parameter(Mandatory)][double]$Y
    )
    $inside = $false
    $n = $Points.Count
    $j = $n - 1
    for ($i = 0; $i -lt $n; $j = $i++) {
        $a = $Points[$i]
        $b = $Points[$j]
        if ((($a.Y -gt $Y) -ne ($b.Y -gt $Y)) -and
            ($X -lt (($b.X - $a.X) * ($Y - $a.Y) / ($b.Y - $a.Y)) + $a.X)) {
            $inside = -not $inside
        }
    }
    return $inside
}

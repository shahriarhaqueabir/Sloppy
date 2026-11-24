#Requires -Version 7.4
<#
.SYNOPSIS
  Headless geometry verifier for SlopFrame. Parses Build() output, samples the
  emitted Beziers, checks window containment / content containment, and renders
  a PNG contact sheet. Pure geometry + System.Drawing; no WPF, no app launch.

  Evidence harness for review items A1-A6. Does NOT prove WPF/DPI/timer/DragMove
  behavior - use tools/verify-motion.ps1 live for that.
#>
param(
    [int]$SamplesPerSegment = 12,
    [string]$OutDir = (Join-Path $env:TEMP 'slop-geometry')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot '../src/Slop.Frame.ps1')

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# ---------- Bezier sampling (PSCustomObject points survive the pipeline) ----------
function Parse-SlopPath {
    param([Parameter(Mandatory)][string]$Path)
    $segments = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($tok in [regex]::Matches($Path, '([MCZ])([^MCZ]*)')) {
        $cmd = $tok.Groups[1].Value
        $nums = @([regex]::Matches($tok.Groups[2].Value, '-?\d+(?:\.\d+)?') | ForEach-Object { [double]$_.Value })
        if ($cmd -eq 'M') { $current = [pscustomobject]@{ X = $nums[0]; Y = $nums[1] } }
        elseif ($cmd -eq 'C') {
            $segments.Add([pscustomobject]@{
                X0 = $current.X; Y0 = $current.Y
                C1X = $nums[0]; C1Y = $nums[1]; C2X = $nums[2]; C2Y = $nums[3]
                X1 = $nums[4]; Y1 = $nums[5]
            })
            $current = [pscustomobject]@{ X = $nums[4]; Y = $nums[5] }
        }
    }
    return $segments.ToArray()
}

function Get-SampledOutline {
    param([Parameter(Mandatory)][string]$Path, [int]$Per = 12)
    $pts = [System.Collections.Generic.List[object]]::new()
    foreach ($s in (Parse-SlopPath -Path $Path)) {
        for ($i = 0; $i -lt $Per; $i++) {
            $t = $i / $Per; $u = 1.0 - $t
            $u2=$u*$u; $u3=$u2*$u; $t2=$t*$t; $t3=$t2*$t
            $a = 3*$u2*$t; $b = 3*$u*$t2
            $pts.Add([pscustomobject]@{
                X = $u3*$s.X0 + $a*$s.C1X + $b*$s.C2X + $t3*$s.X1
                Y = $u3*$s.Y0 + $a*$s.C1Y + $b*$s.C2Y + $t3*$s.Y1
            })
        }
    }
    return $pts.ToArray()
}

function Get-EdgeMargin {
    param([object[]]$Outline, [double]$W, [double]$H)
    $minX=[double]::MaxValue; $maxX=[double]::MinValue; $minY=[double]::MaxValue; $maxY=[double]::MinValue
    foreach ($p in $Outline) {
        if ($p.X -lt $minX) { $minX = $p.X }
        if ($p.X -gt $maxX) { $maxX = $p.X }
        if ($p.Y -lt $minY) { $minY = $p.Y }
        if ($p.Y -gt $maxY) { $maxY = $p.Y }
    }
    return @($minX, $maxX, $minY, $maxY, [Math]::Min([Math]::Min($minX,$minY), [Math]::Min($W-$maxX,$H-$maxY)))
}

function Get-RoundedRectPoints {
    param([double]$X, [double]$Y, [double]$W, [double]$H, [double]$R, [int]$PerCorner = 5)
    $pts = [System.Collections.Generic.List[object]]::new()
    $corners = @(
        [pscustomobject]@{ CX=$X+$W-$R; CY=$Y+$R;    A=-90 },
        [pscustomobject]@{ CX=$X+$W-$R; CY=$Y+$H-$R; A=0 },
        [pscustomobject]@{ CX=$X+$R; CY=$Y+$H-$R;    A=90 },
        [pscustomobject]@{ CX=$X+$R; CY=$Y+$R;       A=180 }
    )
    foreach ($c in $corners) {
        for ($i = 0; $i -le $PerCorner; $i++) {
            $a = ($c.A + 90*$i/$PerCorner) * [Math]::PI / 180.0
            $pts.Add([pscustomobject]@{ X = $c.CX + $R*[Math]::Cos($a); Y = $c.CY + $R*[Math]::Sin($a) })
        }
    }
    return $pts.ToArray()
}

function Get-DistanceToPolyline {
    param($P, [object[]]$Points)
    $best = [double]::MaxValue
    $n = $Points.Count
    for ($i = 0; $i -lt $n; $i++) {
        $a = $Points[$i]; $b = $Points[($i + 1) % $n]
        $dx = $b.X - $a.X; $dy = $b.Y - $a.Y
        $len2 = $dx*$dx + $dy*$dy
        $t = 0.0
        if ($len2 -gt 0.0) {
            $t = (($P.X-$a.X)*$dx + ($P.Y-$a.Y)*$dy) / $len2
            if ($t -lt 0.0) { $t = 0.0 } elseif ($t -gt 1.0) { $t = 1.0 }
        }
        $ex = $P.X - ($a.X + $t*$dx); $ey = $P.Y - ($a.Y + $t*$dy)
        $d = $ex*$ex + $ey*$ey
        if ($d -lt $best) { $best = $d }
    }
    return [Math]::Sqrt($best)
}

function Test-InPolygon {
    param($P, [object[]]$Points)
    $inside = $false; $j = $Points.Count - 1
    for ($i = 0; $i -lt $Points.Count; $j = $i++) {
        $a = $Points[$i]; $b = $Points[$j]
        if ((($a.Y -gt $P.Y) -ne ($b.Y -gt $P.Y)) -and
            ($P.X -lt ($b.X - $a.X) * ($P.Y - $a.Y) / ($b.Y - $a.Y) + $a.X)) { $inside = -not $inside }
    }
    return $inside
}

function Measure-Frame {
    param(
        [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Path,
        [double]$W, [double]$H, [double]$ContentW, [double]$ContentH, [double]$Margin,
        [double]$StrokeHalf, [int]$Per, [switch]$SkipContent
    )
    $outline = Get-SampledOutline -Path $Path -Per $Per
    $e = Get-EdgeMargin -Outline $outline -W $W -H $H
    $minInner = 0.0; $outside = 0
    if (-not $SkipContent) {
        # Frame clip: (Margin+10,Margin+10), size (ContentW-20)x(ContentH-20),
        # radius max(26, 0.11*min(CW,CH) - 5) - matches Slop.ps1 SizeChanged.
        # Input bar Border: Margin 20,4,20,16 inside Frame, Padding 10 + 34px field -> ~54px tall, radius 14.
        $clipRadius = [Math]::Max(26.0, 0.11*[Math]::Min($ContentW,$ContentH) - 5.0)
        $contentBoundary = Get-RoundedRectPoints -X ($Margin+10) -Y ($Margin+10) -W ($ContentW-20) -H ($ContentH-20) -R $clipRadius
        $inputBoundary  = Get-RoundedRectPoints -X ($Margin+20) -Y ($Margin+$ContentH-16-54) -W ($ContentW-40) -H 54 -R 14
        $minInner = [double]::MaxValue
        foreach ($c in @($contentBoundary) + @($inputBoundary)) {
            $d = Get-DistanceToPolyline -P $c -Points $outline
            if ($d -lt $minInner) { $minInner = $d }
            if (-not (Test-InPolygon -P $c -Points $outline)) { $outside++ }
        }
    }
    $cx = 0.0; $cy = 0.0
    foreach ($p in $outline) { $cx += $p.X; $cy += $p.Y }
    $cx /= $outline.Count; $cy /= $outline.Count
    $asym = ($cx - ($Margin + $ContentW/2.0)) / [Math]::Max(1.0, $ContentW/2.0)

    [pscustomobject]@{
        Name=$Name; Samples=$outline.Count
        MinX=[Math]::Round($e[0],2); MaxX=[Math]::Round($e[1],2)
        MinY=[Math]::Round($e[2],2); MaxY=[Math]::Round($e[3],2)
        EdgeMargin=[Math]::Round($e[4],2); EdgePass=($e[4] -ge ($StrokeHalf + 1))
        ContentInset=[Math]::Round($minInner,2)
        ContentPass=$(if ($SkipContent) { $true } else { ($outside -eq 0 -and $minInner -ge 4) })
        OutsideCorners=$outside; AsymPct=[Math]::Round($asym*100,2)
        Outline=$outline; W=$W; H=$H
    }
}

# Lightweight worst-edge search: no distance checks in the hot loop.
function Find-WorstEdge {
    param([scriptblock]$Script, [int]$Frames, [int]$Every, [double]$W, [double]$H, [int]$Per)
    $worstMargin = [double]::MaxValue; $worstPath = ''
    for ($i = 0; $i -lt $Frames; $i++) {
        & $Script $i
        if ($i % $Every -eq 0) {
            $o = Get-SampledOutline -Path $script:FRAME.Path -Per $Per
            $m = (Get-EdgeMargin -Outline $o -W $W -H $H)[4]
            if ($m -lt $worstMargin) { $worstMargin = $m; $worstPath = $script:FRAME.Path }
        }
    }
    return $worstPath
}

function New-ContactSheet {
    param([object[]]$Results, [string]$Path)
    $cellW=380; $cellH=290; $cols=3
    $rows=[Math]::Ceiling($Results.Count/$cols)
    $bmp=[System.Drawing.Bitmap]::new($cellW*$cols, $cellH*$rows)
    $g=[System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(18,20,28))
    $font=[System.Drawing.Font]::new('Consolas',9)
    for ($k=0; $k -lt $Results.Count; $k++) {
        $r=$Results[$k]; $ox=($k%$cols)*$cellW; $oy=[Math]::Floor($k/$cols)*$cellH
        $sx=[Math]::Min(($cellW-24)/$r.W, ($cellH-56)/$r.H)
        $g.TranslateTransform([float]($ox+12),[float]($oy+40)); $g.ScaleTransform([float]$sx,[float]$sx)
        $pts=[System.Drawing.PointF[]]@($r.Outline | ForEach-Object { [System.Drawing.PointF]::new([float]$_.X,[float]$_.Y) })
        $gp=[System.Drawing.Drawing2D.GraphicsPath]::new()
        if ($pts.Count -gt 1) { $gp.AddPolygon($pts); $gp.CloseFigure() }
        $g.FillPath([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(0x33,0x3B,0x82,0xF6)),$gp)
        $g.DrawPath([System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(0xCC,0x3B,0x82,0xF6),2),$gp)
        $g.ResetTransform()
        $status=if ($r.EdgePass -and $r.ContentPass) {'PASS'} else {'FAIL'}
        $g.DrawString("$($r.Name): $status edge=$($r.EdgeMargin) inset=$($r.ContentInset) asym=$($r.AsymPct)%",$font,
            [System.Drawing.Brushes]::White,[float]($ox+8),[float]($oy+10))
        $gp.Dispose()
    }
    $g.Dispose(); $bmp.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $font.Dispose()
}

# ---------- scenarios ----------
$margin=18.0; $strokeHalf=2.5; $pps=$SamplesPerSegment
# compact: window 484x330, Frame 448x294. expanded: window 760x540, Frame 724x504.
$cW=484.0; $cH=330.0; $cCW=448.0; $cCH=294.0
$eW=760.0; $eH=540.0; $eCW=724.0; $eCH=504.0
$results=[System.Collections.Generic.List[object]]::new()

function Add-Scenario {
    param([string]$Name,[string]$Path,[double]$W,[double]$H,[double]$CW,[double]$CH,[switch]$Skip)
    $results.Add((Measure-Frame -Name $Name -Path $Path -W $W -H $H -ContentW $CW -ContentH $CH -Margin $margin -StrokeHalf $strokeHalf -Per $pps -SkipContent:$Skip))
}
function Settle { param([int]$Frames=240) for ($i=0;$i -lt $Frames;$i++) { $script:FRAME.Update(1.0/120.0) } }

# 1. compact pea + expansion
$script:FRAME=[SlopFrame]::new($cCW,$cCH,$margin,1337)
Add-Scenario 'compact-pea' $FRAME.Path $cW $cH $cCW $cCH -Skip
$script:FRAME.Expand([float]($margin+$cCW/2),[float]($margin+$cCH))
for ($i=0;$i -lt 120;$i++) { $FRAME.Update(1.0/120.0); if ($i -in @(10,20,30,40,60,100)) { Add-Scenario "expand-$i" $FRAME.Path $cW $cH $cCW $cCH -Skip } }
Add-Scenario 'expanded-compact' $FRAME.Path $cW $cH $cCW $cCH

# 2. expanded full frame
$script:FRAME=[SlopFrame]::new($eCW,$eCH,$margin,7331)
$FRAME.Expand([float]($margin+$eCW/2),[float]($margin+$eCH)); Settle
Add-Scenario 'expanded-760x540' $FRAME.Path $eW $eH $eCW $eCH

# 3. moods, 10s each - find worst edge frame then measure fully once
foreach ($mood in @(@('idle',[SlopFrame]::Idle),@('thinking',[SlopFrame]::Thinking),@('alert',[SlopFrame]::Alert),@('happy',[SlopFrame]::Happy))) {
    $script:FRAME=[SlopFrame]::new($eCW,$eCH,$margin,4242)
    $FRAME.Expand([float]($margin+$eCW/2),[float]($margin+$eCH)); Settle
    $FRAME.SetMood($mood[1])
    $step={ param($i) $script:FRAME.Update(1.0/120.0) }
    $worst=Find-WorstEdge -Script $step -Frames 1200 -Every 15 -W $eW -H $eH -Per $pps
    Add-Scenario "mood-$($mood[0])" $worst $eW $eH $eCW $eCH
}

# 4. max kick
$script:FRAME=[SlopFrame]::new($eCW,$eCH,$margin,999)
$FRAME.Expand([float]($margin+$eCW/2),[float]($margin+$eCH)); Settle
$step={ param($i) $script:FRAME.Kick(10.0); for($k=0;$k -lt 20;$k++){ $script:FRAME.Update(1.0/120.0) } }
$worst=Find-WorstEdge -Script $step -Frames 20 -Every 1 -W $eW -H $eH -Per $pps
Add-Scenario 'max-kick' $worst $eW $eH $eCW $eCH

# 5. poke
$script:FRAME=[SlopFrame]::new($eCW,$eCH,$margin,5150)
$FRAME.Expand([float]($margin+$eCW/2),[float]($margin+$eCH)); Settle
$FRAME.Poke([float]($margin+40),[float]($margin+40),14.0)
for ($i=0;$i -lt 30;$i++) { $FRAME.Update(1.0/120.0) }
Add-Scenario 'poke-corner' $FRAME.Path $eW $eH $eCW $eCH

# 6. drag slosh
$script:FRAME=[SlopFrame]::new($eCW,$eCH,$margin,8080)
$FRAME.Expand([float]($margin+$eCW/2),[float]($margin+$eCH)); Settle
for ($i=0;$i -lt 120;$i++) { $FRAME.Move([float](100+12*$i),[float](100+3*$i)); $FRAME.Update(1.0/120.0) }
Add-Scenario 'drag-slosh' $FRAME.Path $eW $eH $eCW $eCH

# 7. resize tall (window 536x736, Frame 500x700)
$script:FRAME=[SlopFrame]::new($eCW,$eCH,$margin,6060)
$FRAME.Expand([float]($margin+$eCW/2),[float]($margin+$eCH)); Settle
$FRAME.SetFrame(500.0,700.0)
for ($i=0;$i -lt 240;$i++) { $FRAME.Update(1.0/120.0) }
Add-Scenario 'resize-tall' $FRAME.Path 536 736 500 700

# 8. reduced motion
$script:FRAME=[SlopFrame]::new($eCW,$eCH,$margin,7070)
$FRAME.SetMotionScale(0.0)
$FRAME.Expand([float]($margin+$eCW/2),[float]($margin+$eCH)); Settle
$FRAME.Kick(10.0)
for ($i=0;$i -lt 60;$i++) { $FRAME.Update(1.0/120.0) }
Add-Scenario 'reduced-motion' $FRAME.Path $eW $eH $eCW $eCH

# ---------- report ----------
$png=Join-Path $OutDir 'geometry-contact-sheet.png'
New-ContactSheet -Results $results.ToArray() -Path $png
$results | Select-Object Name,Samples,EdgeMargin,EdgePass,ContentInset,ContentPass,OutsideCorners,AsymPct | Format-Table -AutoSize | Out-String | Write-Output
$fail=@($results | Where-Object { -not $_.EdgePass -or -not $_.ContentPass })
Write-Output "contact_sheet=$png"
Write-Output "scenarios=$($results.Count) failures=$($fail.Count)"
if ($fail.Count -gt 0) { $fail | Select-Object Name,EdgeMargin,ContentInset,OutsideCorners | Format-Table -AutoSize | Out-String | Write-Output }
exit $(if ($fail.Count -gt 0) { 1 } else { 0 })

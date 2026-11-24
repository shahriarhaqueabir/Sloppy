# tests/slop-asymmetry-check.ps1
# A4: the frame must have a stable, per-instance asymmetry at rest while the
# dynamic wave stays inside the subtle-amplitude budget. Headless, no WPF.
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
. (Join-Path $PSScriptRoot '../src/Slop.Frame.ps1')

$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
}
function Get-Points([string]$path) {
    $pts = [System.Collections.Generic.List[object]]::new()
    $m = [regex]::Match($path, '^M(-?[\d.]+),(-?[\d.]+)')
    $pts.Add(@([double]$m.Groups[1].Value, [double]$m.Groups[2].Value))
    foreach ($c in [regex]::Matches($path, 'C\s*(-?[\d.]+),(-?[\d.]+)\s+(-?[\d.]+),(-?[\d.]+)\s+(-?[\d.]+),(-?[\d.]+)')) {
        $pts.Add(@([double]$c.Groups[5].Value, [double]$c.Groups[6].Value))
    }
    $pts.RemoveAt($pts.Count - 1)   # drop the duplicated closing endpoint
    return $pts
}
function Settle($frame, [int]$n = 360) { for ($i = 0; $i -lt $n; $i++) { $frame.Update(1.0 / 120.0) } }
function Shoelace($pts) {
    $a = 0.0
    for ($i = 0; $i -lt $pts.Count; $i++) { $j = ($i + 1) % $pts.Count; $a += $pts[$i][0] * $pts[$j][1] - $pts[$j][0] * $pts[$i][1] }
    return [Math]::Abs($a) / 2.0
}
function ClipX($pts, [double]$xc, [bool]$keepLeft) {
    $out = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $pts.Count; $i++) {
        $p = $pts[$i]; $q = $pts[($i + 1) % $pts.Count]
        $pin = if ($keepLeft) { $p[0] -le $xc } else { $p[0] -ge $xc }
        $qin = if ($keepLeft) { $q[0] -le $xc } else { $q[0] -ge $xc }
        if ($pin) { $out.Add($p) }
        if ($pin -ne $qin) { $t = ($xc - $p[0]) / ($q[0] - $p[0]); $out.Add(@($xc, $p[1] + $t * ($q[1] - $p[1]))) }
    }
    return $out
}
function LRDiff($pts) {
    $cx = ($pts | ForEach-Object { $_[0] } | Measure-Object -Average).Average
    $al = Shoelace (ClipX $pts $cx $true)
    $ar = Shoelace (ClipX $pts $cx $false)
    return [Math]::Abs($al - $ar) / ($al + $ar) * 100.0
}
function MaxBetween($a, $b) {
    $max = 0.0
    for ($i = 0; $i -lt $a.Count; $i++) {
        $dx = $a[$i][0] - $b[$i][0]; $dy = $a[$i][1] - $b[$i][1]
        $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
        if ($d -gt $max) { $max = $d }
    }
    return $max
}
function DevFrom($pts, $base) {
    $sum = 0.0
    for ($i = 0; $i -lt $pts.Count; $i++) {
        $dx = $pts[$i][0] - $base[$i][0]; $dy = $pts[$i][1] - $base[$i][1]
        $sum += $dx * $dx + $dy * $dy
    }
    return [Math]::Sqrt($sum / $pts.Count)
}

$FW = 448.0; $FH = 294.0; $M = 18.0; $half = $FH / 2.0
$seeds = @(1337, 42, 999)
$rest = @()
foreach ($seed in $seeds) {
    $f = [SlopFrame]::new($FW, $FH, $M, $seed)
    $f.Expand($M + $FW / 2.0, $M + $FH)
    Settle $f
    $rest += ,(Get-Points $f.Path)
}

# 1. per-instance asymmetry: distinct seeds must settle to distinguishable outlines
$d12 = MaxBetween $rest[0] $rest[1]
$d13 = MaxBetween $rest[0] $rest[2]
Assert-True ($d12 -ge 0.5 -and $d13 -ge 0.5) "distinct seeds yield distinct rest outlines (max diff $([Math]::Round($d12, 3)) / $([Math]::Round($d13, 3))px)"

# 2. left/right area difference at rest lands in the suggested 1-4% band
foreach ($i in 0..($seeds.Count - 1)) {
    $lr = LRDiff $rest[$i]
    Assert-True ($lr -ge 1.0 -and $lr -le 4.0) "seed $($seeds[$i]) rest left/right area difference $([Math]::Round($lr, 3))% is inside 1-4%"
}

# 3. dynamic wave amplitude stays subtle (budget: idle RMS <= ~1.5% of half-size)
foreach ($i in 0..($seeds.Count - 1)) {
    $seed = $seeds[$i]
    $ref = [SlopFrame]::new($FW, $FH, $M, $seed)
    $ref.SetMotionScale(0.0)
    $ref.Expand($M + $FW / 2.0, $M + $FH)
    Settle $ref
    $refPts = Get-Points $ref.Path

    $idle = [SlopFrame]::new($FW, $FH, $M, $seed)
    $idle.Expand($M + $FW / 2.0, $M + $FH)
    Settle $idle
    $idleRms = DevFrom (Get-Points $idle.Path) $refPts
    Assert-True (($idleRms / $half) -le 0.015) "seed $seed idle dynamic RMS $([Math]::Round($idleRms / $half * 100.0, 3))% of half-size is within 1.5%"

    $kick = [SlopFrame]::new($FW, $FH, $M, $seed)
    $kick.Expand($M + $FW / 2.0, $M + $FH)
    Settle $kick
    $kick.Kick(100.0)
    $peak = 0.0
    for ($i = 0; $i -lt 240; $i++) {
        $kick.Update(1.0 / 120.0)
        if ($i % 12 -eq 0) {
            $rms = DevFrom (Get-Points $kick.Path) $refPts
            if ($rms -gt $peak) { $peak = $rms }
        }
    }
    Assert-True (($peak / $half) -le 0.02) "seed $seed max-kick dynamic RMS $([Math]::Round($peak / $half * 100.0, 3))% of half-size stays within 2%"
}

Describe 'Slop asymmetry geometry' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}

# tests/slop-frame-check.ps1
# Headless checks for the organic membrane engine. No WPF types are used here.
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
. (Join-Path $PSScriptRoot '../src/Slop.Frame.ps1')

$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
}
function Numbers($path) {
    @([regex]::Matches($path, '-?\d+\.?\d*') | ForEach-Object { [double]::Parse($_.Value, [Globalization.CultureInfo]::InvariantCulture) })
}
function Contained($frame, $w, $h) {
    $n = Numbers $frame.Path
    if ($n.Count -lt 64) { return $false }
    # Path data alternates x,y: M x,y then six numbers per cubic segment.
    $xs = @(); $ys = @()
    for ($i = 0; $i -lt $n.Count; $i += 2) {
        $xs += $n[$i]
        if ($i + 1 -lt $n.Count) { $ys += $n[$i + 1] }
    }
    # Every x and y is clamped inside the window with stroke safety.
    return (($xs | Measure-Object -Minimum).Minimum -ge 4.0 -and
            ($xs | Measure-Object -Maximum).Maximum -le ($w - 4.0) -and
            ($ys | Measure-Object -Minimum).Minimum -ge 4.0 -and
            ($ys | Measure-Object -Maximum).Maximum -le ($h - 4.0))
}

$FW = 448.0; $FH = 294.0; $M = 18.0
$W = $FW + 2 * $M; $H = $FH + 2 * $M
$f = [SlopFrame]::new($FW, $FH, $M, 12345)

Assert-True ($f.Margin -eq $M) 'margin is preserved'
Assert-True ($f.OutLimit -le ($M - 2.0)) 'outward bulge is bounded by the margin'
Assert-True $f.IsClosed 'frame starts closed'
Assert-True ($f.ContentOpacity -le 0.001) 'content is hidden while closed'

$f.Expand(242.0, 305.0)
Assert-True (-not $f.IsClosed) 'expand leaves the closed state'
1..90 | ForEach-Object { $f.Update(1.0 / 60.0) }
Assert-True ($f.ContentOpacity -ge 0.999) 'content is fully visible when open'
Assert-True $f.Path.StartsWith('M') 'path starts with a move'
Assert-True $f.Path.EndsWith(' Z') 'path is closed'
$curveCount = ([regex]::Matches($f.Path, '\bC')).Count
Assert-True ($curveCount -eq 48) "path has 48 cubic segments (got $curveCount) - 16 under-sampled the rounded corners"
Assert-True (([SlopFrame].GetField('Version')) -ne $null) 'compiled frame type carries a version marker (stale-type guard)'
Assert-True (-not ($f.Path -match 'NaN|Infinity')) 'path has no NaN or Infinity'
# One move (2 numbers) plus six numbers per cubic; derive from the actual
# segment count so a future point-count change cannot silently stale this.
Assert-True ((Numbers $f.Path).Count -eq (2 + $curveCount * 6)) 'coordinate count matches one move plus all cubics'
Assert-True (Contained $f $W $H) 'expanded outline stays inside the window'
Assert-True ($f.Highlight.Length -gt 10 -and $f.Highlight.StartsWith('M')) 'upper-left rim highlight is emitted'

# Spring overshoot and violent disturbances must never escape the hard clamp.
$f.Kick(10000.0)
$f.Poke(0.0, 0.0, 10000.0)
$f.Poke($W, $H, 10000.0)
1..180 | ForEach-Object { $f.Update(1.0 / 60.0) }
Assert-True (Contained $f $W $H) 'extreme kick and corner pokes stay clipped inside the window'

# Resizing relayouts the content and the outline together.
$f.SetFrame(600.0, 400.0)
1..180 | ForEach-Object { $f.Update(1.0 / 60.0) }
Assert-True (Contained $f 636.0 436.0) 'resized frame stays inside the larger window'

# Fast window drags inject acceleration; the resulting slosh must stay bounded.
$f.Move(100.0, 100.0)
$f.Update(1.0 / 60.0)
$f.Move(340.0, 260.0)
$f.Update(1.0 / 60.0)
1..60 | ForEach-Object { $f.Update(1.0 / 60.0) }
Assert-True (Contained $f 636.0 436.0) 'drag acceleration slosh stays clipped inside the window'

# Reduced motion disables impulses and waves while expand/collapse still works.
$f.SetMotionScale(0.0)
$f.SetFrame($FW, $FH)
$f.Collapse(242.0, 305.0)
1..180 | ForEach-Object { $f.Update(1.0 / 60.0) }
Assert-True $f.IsClosed 'collapse settles to the pea with reduced motion'
$f.Expand(242.0, 305.0)
$f.Kick(5000.0)
1..90 | ForEach-Object { $f.Update(1.0 / 60.0) }
Assert-True (Contained $f $W $H) 'reduced motion keeps the outline contained'
Assert-True ($f.ContentOpacity -ge 0.999) 'reduced motion still opens the content'

# Mood channels are distinct and validated at the call site.
Assert-True ([SlopFrame]::Idle -ne [SlopFrame]::Thinking -and
             [SlopFrame]::Thinking -ne [SlopFrame]::Alert -and
             [SlopFrame]::Alert -ne [SlopFrame]::Happy) 'mood channels are distinct'

Describe 'Slop membrane frame engine' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}

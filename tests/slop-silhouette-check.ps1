# tests/slop-silhouette-check.ps1
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
. (Join-Path $PSScriptRoot '../src/Slop.Silhouette.ps1')

$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
}

$compact  = Get-SlopSilhouettePoints -Open 0
$expanded = Get-SlopSilhouettePoints -Open 1
Assert-True ($compact.Count -eq 8 -and $expanded.Count -eq 8) 'eight anchors in both silhouettes'
Assert-True ([Math]::Abs($compact[0].X - 141.0) -lt 0.001) 'compact seed sits at pea upper-left'
Assert-True ([Math]::Abs($expanded[0].X - 60.0) -lt 0.001 -and [Math]::Abs($expanded[0].Y - 2.0) -lt 0.001) 'expanded head shelf anchor'

$mid = Get-SlopSilhouettePoints -Open 0.5
Assert-True ([Math]::Abs($mid[0].X - ((141.0 + 60.0) / 2.0)) -lt 0.001) 'open interpolates anchors linearly'
$quarter = Get-SlopSilhouettePoints -Open 0.25
Assert-True ($quarter[0].Y -lt $quarter[3].Y) 'head shelf stays above the right flank while opening'
Assert-True ([Math]::Abs((Get-SlopSilhouettePoints -Open 2.0)[0].X - 60.0) -lt 0.001) 'open clamps above 1'
Assert-True ([Math]::Abs((Get-SlopSilhouettePoints -Open -1.0)[0].X - 141.0) -lt 0.001) 'open clamps below 0'

$data = Convert-SlopSilhouetteToPathData -Points $expanded
Assert-True ($data.StartsWith('M ') -and $data.EndsWith(' Z')) 'path data is a closed path'
$curveCount = ([regex]::Matches($data, ' C ')).Count
Assert-True ($curveCount -eq 8) "path has eight cubic segments (got $curveCount)"
Assert-True (-not ($data -match 'NaN|Infinity')) 'path data has no NaN or Infinity'
Assert-True (-not ($data -match ',')) 'path data uses invariant decimal point'

# These are the frame-local equivalents of the live verifier's sample points:
# window (160,200) -> local (150,190); window (36,28) -> local (26,18);
# window (160,407) -> local (150,397).
foreach ($probe in @(@(150.0,190.0), @(26.0,18.0), @(150.0,397.0))) {
    Assert-True (Test-SlopSilhouetteContains -Points $expanded -X $probe[0] -Y $probe[1]) `
        "verifier sample $($probe -join ',') stays inside expanded body"
}

$pulsed = Get-SlopSilhouettePoints -Open 1 -Pulse 1.0
Assert-True ([Math]::Abs(($pulsed[3].Y - 240.0) - (($expanded[3].Y - 240.0) * 1.05)) -lt 0.001) 'pulse expands body vertically'
$leaned = Get-SlopSilhouettePoints -Open 1 -Lean 7.0
Assert-True ([Math]::Abs(($leaned[3].X - $expanded[3].X) - (7.0 * ($expanded[3].Y - 240.0) * 0.004)) -lt 0.001) 'lean shears body horizontally'
$wide = Get-SlopSilhouettePoints -Open 1 -Width 600
Assert-True ([Math]::Abs($wide[0].X - 120.0) -lt 0.001) 'width scales anchors for resize'

Describe 'Slop silhouette geometry' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}

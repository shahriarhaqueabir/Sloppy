#Requires -Version 7.4
<#
.SYNOPSIS
  Pester regression gate for the expand / minimize-to-blob animation.
  Drives SlopFrame at the real 30fps tick and asserts the transition is a smooth
  eased grow/shrink (not a 6-frame pop), that chat content never appears before
  the body covers it, and that collapse has no opacity ghost.
#>
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0

Describe 'SlopFrame expand / collapse animation' {
    BeforeAll {
        # Defined here so it is visible when this suite is dot-sourced by
        # tests/Slop.Tests.ps1 (Pester runs BeforeAll in its own scope).
        function Get-RingPoints([string]$Path) {
            $all = [regex]::Matches($Path, '(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)')
            $pts = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -lt $all.Count; $i += 3) {
                $pts.Add([pscustomobject]@{
                    X = [double]$all[$i].Groups[1].Value
                    Y = [double]$all[$i].Groups[2].Value
                })
            }
            return $pts.ToArray()
        }

        . (Join-Path $PSScriptRoot '../src/Slop.Frame.ps1')

        $frame = [SlopFrame]::new(448.0, 294.0, 18.0, 4242)
        $frame.SetFrame(724.0, 504.0)   # expanded content box (760x540 window - 36)
        for ($i = 0; $i -lt 30; $i++) { $frame.Update(1.0 / 30.0) }

        $targetWidth = 724.0
        $expand = [System.Collections.Generic.List[object]]::new()
        $frame.Expand(242.0, 300.0)
        $previous = $null
        $maxJumpPx = 0.0
        for ($i = 0; $i -lt 45; $i++) {
            $frame.Update(1.0 / 30.0)
            $points = Get-RingPoints $frame.Path
            $xs = @($points | ForEach-Object { $_.X })
            $width = ($xs | Measure-Object -Maximum).Maximum - ($xs | Measure-Object -Minimum).Minimum
            if ($null -ne $previous) {
                for ($k = 0; $k -lt [Math]::Min($previous.Count, $points.Count); $k++) {
                    $d = [Math]::Sqrt([Math]::Pow($points[$k].X - $previous[$k].X, 2) + [Math]::Pow($points[$k].Y - $previous[$k].Y, 2))
                    if ($d -gt $maxJumpPx) { $maxJumpPx = $d }
                }
            }
            $previous = $points
            $expand.Add([pscustomobject]@{ Frame = $i; Width = $width; Opacity = $frame.ContentOpacity })
        }

        $script:ExpandNinety = @($expand | Where-Object { $_.Width -ge 0.9 * $targetWidth } | Select-Object -First 1)[0]
        $script:ExpandMaxJump = $maxJumpPx
        $script:ExpandLeak = @($expand | Where-Object { $_.Width -lt 0.8 * $targetWidth -and $_.Opacity -gt 0.02 } | Select-Object -First 1)[0]

        $frame.Collapse(242.0, 300.0)
        $collapse = [System.Collections.Generic.List[object]]::new()
        $closedAt = -1
        for ($i = 0; $i -lt 60; $i++) {
            $frame.Update(1.0 / 30.0)
            $collapse.Add([pscustomobject]@{ Frame = $i; Opacity = $frame.ContentOpacity })
            if ($closedAt -lt 0 -and $frame.IsClosed) { $closedAt = $i }
        }
        $ghost = $false
        $gone = $false
        foreach ($c in $collapse) {
            if ($c.Opacity -lt 0.01) { $gone = $true }
            elseif ($gone -and $c.Opacity -gt 0.02) { $ghost = $true; break }
        }
        $script:CollapseGhost = $ghost
        $script:CollapseClosedAt = $closedAt
    }

    It 'grows to 90% of full width in 10-20 frames (eased, not a pop)' {
        $script:ExpandNinety | Should -Not -BeNull -Because 'the body must reach the expanded size'
        $script:ExpandNinety.Frame | Should -BeGreaterOrEqual 10 -Because 'the old springs popped in ~6 frames'
        $script:ExpandNinety.Frame | Should -BeLessOrEqual 20 -Because 'the easing must still finish promptly'
    }

    It 'moves no ring point more than 60px in one 33ms tick' {
        $script:ExpandMaxJump | Should -BeLessOrEqual 60.0 -Because 'a large per-frame jump reads as stutter'
    }

    It 'hides chat content until the body covers 80% of the content rect' {
        $script:ExpandLeak | Should -BeNull -Because 'content must not float over a pea-sized blob'
    }

    It 'fades out monotonically with no opacity ghost on collapse' {
        $script:CollapseGhost | Should -BeFalse -Because 'content must not reappear after going out'
    }

    It 'fully closes in 22-42 frames (no fast snap)' {
        $script:CollapseClosedAt | Should -BeGreaterOrEqual 22 -Because 'collapse must be eased'
        $script:CollapseClosedAt | Should -BeLessOrEqual 42 -Because 'collapse must still finish promptly'
    }
}

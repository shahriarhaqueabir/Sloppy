#requires -Version 7.6
Describe 'Slop.Surfaces' {
    BeforeAll {
        # Get-SlopDeletionScope delegates copy text to the Disclosure module.
        . (Join-Path $PSScriptRoot '../src/Slop.Disclosure.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Surfaces.ps1')
    }
    It 'exposes exactly four destinations' {
        (Get-SlopDestinationMap).Keys | Sort-Object | Should -Be @('Brain','Customize','Privacy','Settings')
    }
    It 'keeps persona text out of permissions' {
        $r = Test-SlopSurfaceSeparation -Destination 'Customize' -Payload @{ personaText='be warm'; permissions=@() }
        $r.Ok | Should -BeTrue
        $r2 = Test-SlopSurfaceSeparation -Destination 'Customize' -Payload @{ personaText='be warm'; permissions=@(@{effect='allow'}) }
        $r2.Ok | Should -BeFalse
    }
    It 'places developer commands only under Settings Advanced' {
        $m = Get-SlopDestinationMap
        $m.Settings.Contains('Advanced / developer') | Should -BeTrue
        $m.Customize -join ',' | Should -Not -Match 'developer'
    }
    It 'maps each deletion action to a distinct scope' {
        $scopes = @('conversation','session','local-data') | ForEach-Object { (Get-SlopDeletionScope -Action $_).Scope }
        ($scopes | Select-Object -Unique).Count | Should -Be 3
    }
}

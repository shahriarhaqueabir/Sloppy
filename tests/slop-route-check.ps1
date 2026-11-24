#requires -Version 7.6
Describe 'Slop.Route' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.LocalModel.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Provider.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCode.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeProfile.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Route.ps1')
    }

    It 'classifies the bundled default' {
        Resolve-SlopRouteKind -Config @{ brain = 'builtin' } | Should -Be 'local-bundled'
    }

    It 'classifies a custom local endpoint' {
        Resolve-SlopRouteKind -Config @{ brain = 'custom' } | Should -Be 'custom'
    }

    It 'classifies an OpenCode route with a local provider' {
        Resolve-SlopRouteKind -Config @{ brain='opencode'; providerLocality='local'; providerTier='free' } |
            Should -Be 'opencode-local'
    }

    It 'classifies an OpenCode route with a remote paid provider' {
        Resolve-SlopRouteKind -Config @{ brain='opencode'; providerLocality='remote'; providerTier='paid' } |
            Should -Be 'opencode-paid'
    }

    It 'lets an agent model preference win over the config default' {
        Resolve-SlopEffectiveModel -Agent @{ model='kimi-k3' } -Config @{ model='beam-free' } |
            Should -Be 'kimi-k3'
    }

    It 'falls back to the config model when the agent has no preference' {
        Resolve-SlopEffectiveModel -Agent @{} -Config @{ model='beam-free' } | Should -Be 'beam-free'
    }

    It 'badges locality, provider and effective model - not the tier' {
        Get-SlopRouteBadge -Kind 'opencode-local' -Provider 'Ollama' -Model 'qwen3:8b' |
            Should -Be 'Local · Ollama · qwen3:8b'
        Get-SlopRouteBadge -Kind 'opencode-paid' -Provider 'OpenCode Go' -Model 'Beam Free' |
            Should -Be 'Remote · OpenCode Go · Beam Free'
    }

    It 'rejects an unknown route kind' {
        { Get-SlopRouteBadge -Kind 'magic' -Provider 'x' -Model 'y' } | Should -Throw
    }

    It 'marks only remote routes as requiring disclosure' {
        (Get-SlopRouteCatalog)['opencode-remote'].TermsRequired | Should -BeTrue
        (Get-SlopRouteCatalog)['opencode-paid'].TermsRequired | Should -BeTrue
        (Get-SlopRouteCatalog)['local-bundled'].TermsRequired | Should -BeFalse
        (Get-SlopRouteCatalog)['custom'].TermsRequired | Should -BeFalse
    }

    It 'never persists a credential in controlled config' {
        $cfg = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        ($cfg | ConvertTo-Json -Depth 8 -Compress) | Should -Not -Match 'apiKey|password|token|secret'
    }

    It 'plans a custom route without starting the bundled model' {
        $plan = Get-SlopRoutePlan -Config @{
            brain='custom'; endpointUrl='http://127.0.0.1:11434/'; model='qwen3:8b'
        } -UserText 'hello' -ScriptRootPath 'C:/fake/src' -RepoRootPath 'C:/fake'
        $plan.Ok | Should -BeTrue
        $plan.Kind | Should -Be 'custom'
        $plan.AdapterPath | Should -Match 'Slop\.Adapter\.OpenAi\.ps1$'
        $plan.AdapterArgs.BaseUrl | Should -Be 'http://127.0.0.1:11434'
        $plan.RequiresDisclosure | Should -BeFalse
    }
}

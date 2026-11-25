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
        Get-SlopRouteBadge -Kind 'opencode-paid' -Provider 'OpenCode Go' -Model 'Qwen3.5-2B Q4_K_M' |
            Should -Be 'Remote · OpenCode Go · Qwen3.5-2B Q4_K_M'
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

    It 'plans a local-bundled route with the Qwen contract when runtime files exist' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('slop-route-rt-' + [guid]::NewGuid().ToString('N'))
        $savedLocal = $env:LOCALAPPDATA
        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $env:LOCALAPPDATA = $root
            $paths = Get-SlopRuntimePaths
            New-Item -ItemType File -Path $paths.ServerExe -Force | Out-Null
            New-Item -ItemType File -Path $paths.ModelFile -Force | Out-Null

            $plan = Get-SlopRoutePlan -Config @{
                brain='builtin'; localContextSize=16384; localModelName='Qwen3.5-2B Q4_K_M'
            } -UserText 'hello' -ScriptRootPath 'C:/fake/src' -RepoRootPath 'C:/fake'

            $plan.Ok | Should -BeTrue
            $plan.Kind | Should -Be 'builtin'
            $plan.RouteKind | Should -Be 'local-bundled'
            $plan.ReadyToSend | Should -BeFalse
            $plan.NeedsLocalModelStart | Should -BeTrue
            $plan.Badge | Should -Be 'Local · bundled · Qwen3.5-2B Q4_K_M'
            $plan.AdapterPath | Should -Match 'Slop\.Adapter\.OpenAi\.ps1$'
            $plan.AdapterArgs.BaseUrl | Should -Be 'http://127.0.0.1:18080'
            $plan.LocalModelContextSize | Should -Be 16384
            $plan.LocalModelPaths.MmprojFile | Should -Be ''
        } finally {
            $env:LOCALAPPDATA = $savedLocal
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'fails closed for local-bundled route when runtime files are missing' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('slop-route-miss-' + [guid]::NewGuid().ToString('N'))
        $savedLocal = $env:LOCALAPPDATA
        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $env:LOCALAPPDATA = $root
            $plan = Get-SlopRoutePlan -Config @{ brain='builtin' } -UserText 'hello' -ScriptRootPath 'C:/fake/src' -RepoRootPath 'C:/fake'
            $plan.Ok | Should -BeFalse
            $plan.Reason | Should -Match 'missing|llama-server|model'
        } finally {
            $env:LOCALAPPDATA = $savedLocal
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}

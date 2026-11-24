#requires -Version 7.6
Describe 'Slop.Config' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('slop-config-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        $script:ConfigPath = Join-Path $script:TestRoot 'config.json'
        $script:PersonaPath = Join-Path $script:TestRoot 'persona.md'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'honours the disposable test appdata override without touching LOCALAPPDATA' {
        $previous = $env:SLOP_TEST_APPDATA
        try {
            $env:SLOP_TEST_APPDATA = $script:TestRoot
            Get-SlopUserDataPath | Should -Be $script:TestRoot
            Get-SlopConfigPath | Should -Be $script:ConfigPath
            Get-SlopPersonaPath | Should -Be $script:PersonaPath
        } finally {
            if ($null -eq $previous) { Remove-Item Env:SLOP_TEST_APPDATA -ErrorAction SilentlyContinue }
            else { $env:SLOP_TEST_APPDATA = $previous }
        }
    }

    It 'default config passes validation' {
        $result = Test-SlopConfig -Config (New-SlopDefaultConfig)
        $result.Ok | Should -BeTrue
        @($result.Errors).Count | Should -Be 0
    }

    It 'returns six identity colors, none of which is a semantic signal hex' {
        $colors = Get-SlopIdentityColors
        @($colors.Keys).Count | Should -Be 6
        $signals = @('#3B82F6', '#F59E0B', '#22C55E', '#EF4444')
        foreach ($hex in $colors.Values) { $signals | Should -Not -Contain $hex }
        Get-SlopIdentityColor ocean | Should -Be '#6366F1'
        { Get-SlopIdentityColor 'not-a-swatch' } | Should -Throw
    }

    It 'lists both built-in and opt-in brains' {
        $brains = Get-SlopBrains
        $brains | Should -Contain 'builtin'
        $brains | Should -Contain 'custom'
        $brains | Should -Contain 'opencode'
    }

    It 'rejects invalid scalar and enum values' {
        $base = New-SlopDefaultConfig
        $cases = @(
            @{ key='color'; value='not-a-swatch' }
            @{ key='personality'; value='chaotic' }
            @{ key='brain'; value='telepathy' }
            @{ key='name'; value=('x' * 41) }
            @{ key='autostart'; value='yes' }
            @{ key='providerLocality'; value='somewhere' }
            @{ key='providerTier'; value='enterprise' }
            @{ key='capabilityProfile'; value='root' }
            @{ key='agent'; value='not-a-table' }
        )
        foreach ($case in $cases) {
            $cfg = @{} + $base
            $cfg[$case.key] = $case.value
            (Test-SlopConfig -Config $cfg).Ok | Should -BeFalse
        }
    }

    It 'accepts an OpenCode route config' {
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'opencode'
        $cfg.providerLocality = 'local'
        $cfg.providerTier = 'free'
        $cfg.provider = 'Ollama'
        $cfg.model = 'qwen3:8b'
        $cfg.capabilityProfile = 'companion'
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
    }

    It 'rejects a non-local endpointUrl only for the custom brain' {
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'custom'
        $cfg.endpointUrl = 'https://example.invalid/v1'
        (Test-SlopConfig -Config $cfg).Ok | Should -BeFalse
        $cfg2 = New-SlopDefaultConfig
        $cfg2.brain = 'opencode'
        $cfg2.endpointUrl = ''
        (Test-SlopConfig -Config $cfg2).Ok | Should -BeTrue
    }

    It 'reports a nonexistent config as absent with defaults' {
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeTrue
        $r.Exists | Should -BeFalse
        $r.Config.name | Should -Be 'Sloppy'
        $r.Reason | Should -BeNullOrEmpty
    }

    It 'ignores unknown keys and fills missing known keys from defaults' {
        [IO.File]::WriteAllText($script:ConfigPath, '{"name":"Pea","futureKey":123}', [Text.UTF8Encoding]::new($false))
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeTrue
        $r.Config.name | Should -Be 'Pea'
        $r.Config.color | Should -Be 'ocean'
        $r.Config.brain | Should -Be 'builtin'
        $r.Config.PSObject.Properties.Name | Should -Not -Contain 'futureKey'
    }

    It 'migrates version 0 to version 1 in memory' {
        [IO.File]::WriteAllText($script:ConfigPath, '{"version":0,"name":"Pea"}', [Text.UTF8Encoding]::new($false))
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeTrue
        $r.Config.version | Should -Be 1
    }

    It 'fails closed on malformed JSON with a plain-language reason' {
        [IO.File]::WriteAllText($script:ConfigPath, '{ not json', [Text.UTF8Encoding]::new($false))
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeFalse
        $r.Exists | Should -BeTrue
        $r.Reason | Should -Match 'not valid JSON'
        $r.Config.name | Should -Be 'Sloppy'
    }

    It 'keeps one backup whose content is the first config' {
        $first = New-SlopDefaultConfig
        $first.name = 'First'
        Write-SlopConfig -Config $first -ConfigPath $script:ConfigPath
        $second = New-SlopDefaultConfig
        $second.name = 'Second'
        Write-SlopConfig -Config $second -ConfigPath $script:ConfigPath
        Test-Path -LiteralPath "$script:ConfigPath.bak" | Should -BeTrue
        $bak = Get-Content -LiteralPath "$script:ConfigPath.bak" -Raw | ConvertFrom-Json
        $bak.name | Should -Be 'First'
    }

    It 'refuses to write an invalid config and creates no file' {
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'not-a-brain'
        { Write-SlopConfig -Config $cfg -ConfigPath $script:ConfigPath } | Should -Throw
        Test-Path -LiteralPath $script:ConfigPath | Should -BeFalse
    }

    It 'quotes and escapes an autostart executable path' {
        $plain = Get-SlopAutostartValue 'C:\Program Files\Sloppy\launch.exe'
        $plain | Should -Be '"C:\Program Files\Sloppy\launch.exe"'
        $tricky = Get-SlopAutostartValue 'C:\Odd"Name\launch.exe'
        $tricky | Should -Match '\\"'
    }

    It 'round-trips Unicode persona text through UTF-8 without BOM' {
        $text = "line one`nline two — café ☕ `n"
        Write-SlopPersona -Text $text -PersonaPath $script:PersonaPath
        Read-SlopPersona -PersonaPath $script:PersonaPath | Should -Be $text
        $bytes = [IO.File]::ReadAllBytes($script:PersonaPath)
        $bytes[0] | Should -Not -Be 0xEF
    }
}

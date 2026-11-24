#Requires -Version 7.4
<#
.SYNOPSIS
  Pester gate for slop-control password recovery.
  Verifies startslop can recover OpenCode's persisted service password without
  prompting. Uses a temp service.json via the SLOP_SERVICE_CONFIG test hook.
#>
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0

Describe 'Slop control password source' {
    BeforeAll {
        $script:ScriptPath = Join-Path $PSScriptRoot '../tools/slop-control.ps1'
        $script:Tmp = Join-Path ([IO.Path]::GetTempPath()) "slop-control-test-$([guid]::NewGuid().ToString('N')).json"
        $script:SavedEnv = $env:OPENCODE_PASSWORD
        $script:SavedCfg = $env:SLOP_SERVICE_CONFIG

        Set-Content -Path $script:Tmp -Value '{"password":"unit-test-password"}' -Encoding utf8
        $env:SLOP_SERVICE_CONFIG = $script:Tmp
        $env:OPENCODE_PASSWORD = $null

        . $script:ScriptPath -Action Status | Out-Null
        $script:Actual = Get-SlopOpenCodePassword
    }

    AfterAll {
        Remove-Item $script:Tmp -Force -ErrorAction SilentlyContinue
        if ($null -eq $script:SavedEnv) { Remove-Item Env:OPENCODE_PASSWORD -ErrorAction SilentlyContinue }
        else { $env:OPENCODE_PASSWORD = $script:SavedEnv }
        if ($null -eq $script:SavedCfg) { Remove-Item Env:SLOP_SERVICE_CONFIG -ErrorAction SilentlyContinue }
        else { $env:SLOP_SERVICE_CONFIG = $script:SavedCfg }
    }

    It 'recovers the persisted password without prompting' {
        $script:Actual | Should -Be 'unit-test-password'
    }
}

Describe 'Slop control service restart after config sync' {
    BeforeAll {
        $script:ControlSource = Get-Content -LiteralPath $script:ScriptPath -Raw
        $match = [regex]::Match(
            $script:ControlSource,
            'if \(Sync-SlopOpenCodeConfig\)\s*\{(?<body>[\s\S]*?)\n        \}'
        )
        $script:SyncBody = $match.Groups['body'].Value
    }

    It 'restarts the service after set env stops it' {
        $script:SyncBody | Should -Not -Be ''
        $script:SyncBody | Should -Match 'opencode service start'
    }

    It 'polls for readiness instead of trusting a single status query' {
        $script:ControlSource | Should -Match 'function Wait-OpenCodeService'
        $script:ControlSource | Should -Match 'Start-Sleep -Milliseconds'
        $script:SyncBody | Should -Match 'Wait-OpenCodeService'
    }

    It 'does not keep the stale claim that set env restarts the service' {
        $script:ControlSource | Should -Not -Match 'set env` restarts the service'
    }
}

Describe 'Slop control config precedence' {
    BeforeAll {
        . $script:ScriptPath -Action Status | Out-Null
        $script:ControlSource = Get-Content -LiteralPath $script:ScriptPath -Raw
    }

    It 'treats an empty active config as needing the bundled fallback' {
        Test-SlopShouldInstallFallbackConfig -CurrentConfig '' | Should -BeTrue
    }

    It 'treats a whitespace-only active config as needing the bundled fallback' {
        Test-SlopShouldInstallFallbackConfig -CurrentConfig " `n`t " | Should -BeTrue
    }

    It 'leaves a user-supplied active config untouched' {
        Test-SlopShouldInstallFallbackConfig -CurrentConfig '{"agents":{}}' | Should -BeFalse
    }

    It 'does not throw when the bundled fallback file is absent' {
        $script:ControlSource | Should -Match 'if \(-not \(Test-Path \$configPath\)\) \{ return \$false \}'
    }
}

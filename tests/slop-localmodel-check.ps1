#requires -Version 7.6
Describe 'Slop.LocalModel' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.LocalModel.ps1')
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('slop-model-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'resolves runtime paths under a supplied install root' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $paths.InstallRoot | Should -Be $script:TestRoot
        $paths.ServerExe | Should -Match 'runtime\\llama-server\.exe$'
        $paths.ModelFile | Should -Match 'models\\.*\.gguf$'
        $paths.Port | Should -Be 18080
        $paths.BaseUrl | Should -Be 'http://127.0.0.1:18080'
    }

    It 'reports missing server, missing model, and invalid port separately' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $r = Test-SlopLocalModelPaths -Paths $paths
        $r.Ok | Should -BeFalse
        $r.Reason | Should -Match 'llama-server'
        $r.Reason | Should -Match 'model file'

        New-Item -ItemType File -Path $paths.ServerExe -Force | Out-Null
        $r2 = Test-SlopLocalModelPaths -Paths $paths
        $r2.Reason | Should -Not -Match 'llama-server'
        $r2.Reason | Should -Match 'model file'

        New-Item -ItemType File -Path $paths.ModelFile -Force | Out-Null
        $r3 = Test-SlopLocalModelPaths -Paths $paths
        $r3.Ok | Should -BeTrue

        $paths.Port = 80
        $r4 = Test-SlopLocalModelPaths -Paths $paths
        $r4.Ok | Should -BeFalse
        $r4.Reason | Should -Match 'port'
    }

    It 'builds llama arguments with the expected flags and clamped threads' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $args = @(New-SlopLlamaArguments -Paths $paths -Threads 99)
        $args | Should -Contain '--ctx-size'
        $args | Should -Contain '4096'
        $args | Should -Contain '--cache-ram'
        $args | Should -Contain '0'
        $args | Should -Contain '--host'
        $args | Should -Contain '127.0.0.1'
        $args | Should -Contain '--port'
        $args | Should -Contain '18080'
        $args | Should -Contain '--alias'
        $args | Should -Contain 'sloppy'
        $idx = [array]::IndexOf($args, '--threads')
        [int]$args[$idx + 1] | Should -BeLessOrEqual 8
        [int]$args[$idx + 1] | Should -BeGreaterOrEqual 2
    }

    It 'detects a held loopback port and frees it afterwards' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        try {
            $listener.Start()
            $port = $listener.LocalEndpoint.Port
            Test-SlopPortAvailable -Port $port | Should -BeFalse
        }
        finally { $listener.Stop() }
        Test-SlopPortAvailable -Port $port | Should -BeTrue
    }

    It 'returns a non-throwing failure for an unused local port' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        try {
            $listener.Start()
            $port = $listener.LocalEndpoint.Port
        }
        finally { $listener.Stop() }
        $r = Test-SlopLocalModelHealth -BaseUrl "http://127.0.0.1:$port" -TimeoutMs 300
        $r.Ok | Should -BeFalse
        $r.Reason | Should -Not -BeNullOrEmpty
    }

    It 'gives memory-specific copy for an OOM reason and the tray hint otherwise' {
        Format-SlopLocalModelFailure -Reason 'out of memory' | Should -Match 'not enough free memory'
        Format-SlopLocalModelFailure -Reason 'missing binary' | Should -Match 'change brains any time'
    }

    It 'treats a null or exited process as a no-op on stop' {
        $child = $null
        try {
            { Stop-SlopLocalModel -Process $null } | Should -Not -Throw
            $child = Start-Process -FilePath 'pwsh' -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru
            Start-Sleep -Milliseconds 300
            $child.Refresh()
            if (-not $child.HasExited) {
                Stop-Process -Id $child.Id -Force
                $child.WaitForExit()
            }
            { Stop-SlopLocalModel -Process $child } | Should -Not -Throw
        }
        finally {
            if ($child -and -not $child.HasExited) { Stop-Process -Id $child.Id -Force }
        }
    }
}

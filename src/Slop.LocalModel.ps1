# Bundled llama.cpp lifecycle. Headless: process/argument helpers and HTTP health only.
$ErrorActionPreference = 'Stop'
$script:SlopModelPort = 18080

function Get-SlopRuntimePaths {
    param([string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\Sloppy'))
    return @{
        InstallRoot  = $InstallRoot
        ServerExe    = (Join-Path $InstallRoot 'runtime\llama-server.exe')
        ModelFile    = (Join-Path $InstallRoot 'models\qwen3-4b-q4_k_m-00001-of-00002.gguf')
        Port         = $script:SlopModelPort
        BaseUrl      = "http://127.0.0.1:$script:SlopModelPort"
    }
}

function Test-SlopLocalModelPaths {
    param([Parameter(Mandatory)][hashtable]$Paths)
    $errors = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Paths.ServerExe)) { $errors.Add('the built-in brain is missing llama-server.exe') }
    if (-not (Test-Path -LiteralPath $Paths.ModelFile)) { $errors.Add('the built-in brain model file is missing') }
    if ($Paths.Port -lt 1024 -or $Paths.Port -gt 65535) { $errors.Add('the local model port is invalid') }
    return @{ Ok = ($errors.Count -eq 0); Reason = ($errors -join '; ') }
}

function New-SlopLlamaArguments {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [int]$Threads = 0,
        [int]$ContextSize = 4096,
        [int]$MaxTokens = 512
    )
    if ($Threads -le 0) { $Threads = [Environment]::ProcessorCount - 2 }
    $Threads = [Math]::Max(2, [Math]::Min(8, $Threads))
    return @(
        '--model', $Paths.ModelFile
        '--host', '127.0.0.1'
        '--port', [string]$Paths.Port
        '--ctx-size', [string]$ContextSize
        '--cache-ram', '0'
        '--threads', [string]$Threads
        '--n-predict', [string]$MaxTokens
        '--alias', 'sloppy'
    )
}

function Test-SlopLocalModelHealth {
    param([Parameter(Mandatory)][string]$BaseUrl, [int]$TimeoutMs = 1000)
    $uri = $null
    if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'http' -or -not $uri.IsLoopback) {
        return @{ Ok = $false; Reason = 'local model health URL must be loopback http' }
    }
    try {
        $resp = Invoke-WebRequest -Uri "$BaseUrl/health" -Method Get -TimeoutSec ([Math]::Max(1, [int]($TimeoutMs / 1000))) -UseBasicParsing
        return @{ Ok = ($resp.StatusCode -eq 200); Reason = $null }
    }
    catch { return @{ Ok = $false; Reason = $_.Exception.Message } }
}

function Test-SlopOwnedModelProcess {
    param([Parameter(Mandatory)][hashtable]$Paths, [System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return $false }
    try {
        $Process.Refresh()
        if ($Process.HasExited) { return $false }
        $actualPath = [IO.Path]::GetFullPath($Process.MainModule.FileName)
        $expectedPath = [IO.Path]::GetFullPath($Paths.ServerExe)
        if (-not $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$($Process.Id)" -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$processInfo.CommandLine) -or
            $processInfo.CommandLine.IndexOf([string]$Paths.ModelFile, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            return $false
        }

        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Paths.Port -ErrorAction SilentlyContinue)
        if (@($listeners | Where-Object {
            $_.OwningProcess -eq $Process.Id -and $_.LocalAddress -in @('127.0.0.1','::1')
        }).Count -eq 0) { return $false }
        return (Test-SlopLocalModelHealth -BaseUrl $Paths.BaseUrl -TimeoutMs 1000).Ok
    }
    catch { return $false }
}

function Test-SlopPortAvailable {
    param([Parameter(Mandatory)][int]$Port)
    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    }
    catch { return $false }
    finally { if ($listener) { $listener.Stop() } }
}

function Start-SlopLocalModel {
    # This readiness loop may wait up to 90 seconds. Call it from a worker, never
    # from the WPF dispatcher thread.
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [System.Diagnostics.Process]$Process,
        [int]$WaitSeconds = 90
    )
    $pre = Test-SlopLocalModelPaths -Paths $Paths
    if (-not $pre.Ok) { return @{ Ok = $false; Reason = $pre.Reason; Process = $null } }
    if ($Process) {
        if (Test-SlopOwnedModelProcess -Paths $Paths -Process $Process) {
            return @{ Ok = $true; Reason = $null; Process = $Process }
        }
        return @{ Ok = $false; Reason = 'the existing local brain is no longer the Sloppy-owned model process; restart the brain before continuing'; Process = $null }
    }
    if (-not (Test-SlopPortAvailable -Port $Paths.Port)) {
        return @{ Ok = $false; Reason = 'another program is using the local brain port; Sloppy will not send prompts to an unverified local service'; Process = $null }
    }
    $llamaArgs = New-SlopLlamaArguments -Paths $Paths
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Paths.ServerExe
    $startInfo.WorkingDirectory = Split-Path -Parent $Paths.ServerExe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    foreach ($arg in $llamaArgs) { [void]$startInfo.ArgumentList.Add([string]$arg) }
    try { $proc = [Diagnostics.Process]::Start($startInfo) }
    catch { return @{ Ok = $false; Reason = 'the built-in brain could not be started; check the installed runtime and try again'; Process = $null } }
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($proc.HasExited) {
            return @{ Ok = $false; Reason = 'the built-in brain stopped while starting; close other apps to free memory and try again'; Process = $null }
        }
        if ((Test-SlopOwnedModelProcess -Paths $Paths -Process $proc)) {
            return @{ Ok = $true; Reason = $null; Process = $proc }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    return @{ Ok = $false; Reason = 'the built-in brain took too long to wake; close other apps and try again'; Process = $null }
}

function Stop-SlopLocalModel {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process -or $Process.HasExited) { return }
    Stop-Process -Id $Process.Id -Force
}

function Format-SlopLocalModelFailure {
    param([Parameter(Mandatory)][string]$Reason)
    if ($Reason -match 'memory|resource|out of memory') {
        return 'There is not enough free memory. Close a few apps or use Sleep model in the tray, then try again.'
    }
    return "$Reason You can change brains any time from the tray."
}

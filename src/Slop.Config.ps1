# Sloppy portable configuration. Pure path/schema/IO helpers; no WPF, no network.
$ErrorActionPreference = 'Stop'

$script:SlopConfigVersion = 1
$script:SlopIdentityColors = @{
    ocean = '#6366F1'
    moss  = '#14B8A6'
    plum  = '#A855F7'
    ember = '#EC4899'
    sky   = '#38BDF8'
    stone = '#94A3B8'
}
# 'custom' is a local OpenAI-compatible endpoint; 'opencode' is the opt-in
# harness route (local or remote provider). Part B requires both.
$script:SlopBrains = @('builtin', 'custom', 'opencode')
$script:SlopPersonalities = @('calm', 'playful', 'curious', 'professional')
$script:SlopCapabilityProfiles = @('companion', 'workspace', 'power')

function Get-SlopUserDataPath {
    # Live verifiers point this at a disposable directory. LOCALAPPDATA itself is
    # deliberately left alone because the bundled runtime lives under it.
    if (-not [string]::IsNullOrWhiteSpace($env:SLOP_TEST_APPDATA)) {
        return $env:SLOP_TEST_APPDATA
    }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set' }
    return Join-Path $env:LOCALAPPDATA 'Sloppy'
}
function Get-SlopConfigPath    { return Join-Path (Get-SlopUserDataPath) 'config.json' }
function Get-SlopPersonaPath   { return Join-Path (Get-SlopUserDataPath) 'persona.md' }
function Get-SlopIdentityColors { return @{} + $script:SlopIdentityColors }
function Get-SlopPersonalities  { return @($script:SlopPersonalities) }
function Get-SlopBrains         { return @($script:SlopBrains) }
function Get-SlopCapabilityProfiles { return @($script:SlopCapabilityProfiles) }
function Get-SlopIdentityColor {
    param([Parameter(Mandatory)][string]$ColorKey)
    if (-not $script:SlopIdentityColors.ContainsKey($ColorKey)) { throw "unknown identity color: $ColorKey" }
    return $script:SlopIdentityColors[$ColorKey]
}

function Test-SlopLoopbackHttpUrl {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Url)
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.Scheme -ne 'http' -or -not $uri.IsLoopback) { return $false }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) { return $false }
    return $true
}

function New-SlopDefaultConfig {
    return @{
        version           = $script:SlopConfigVersion
        name              = 'Sloppy'
        ownerName         = ''
        color             = 'ocean'
        personality       = 'calm'
        instructions      = ''
        brain             = 'builtin'
        endpointUrl       = ''
        modelName         = ''
        autostart         = $true

        # Tier 1 bundled local brain (Gemma 4 E2B QAT Q4_0). Readiness flags
        # describe runtime capability hooks, not enabled capture/UI wiring.
        localModelName    = 'Gemma 4 E2B QAT Q4_0'
        localModelFile    = 'models\gemma-4-E2B_q4_0-it.gguf'
        localMmprojFile   = 'models\gemma-4-E2B-it-mmproj.gguf'
        localContextSize  = 8192
        localVisionReady  = $true
        localAudioReady   = $true

        # Part B route fields. Defaults stay local-first and disclose nothing.
        provider          = ''
        providerLocality  = ''
        providerTier      = 'free'
        capabilityProfile = 'companion'
        agentId           = 'sloppy'
        model             = ''
        agent             = @{}
        openCodeBaseUrl   = ''
        serviceConfigPath = ''
        openCodeSessionId = ''
    }
}

function Get-SlopAutostartValue {
    param([Parameter(Mandatory)][string]$ExecutablePath)
    return '"' + ($ExecutablePath -replace '"', '\"') + '"'
}

function Test-SlopConfig {
    param([Parameter(Mandatory)][hashtable]$Config)
    $errors = [Collections.Generic.List[string]]::new()
    if ($Config.version -isnot [int] -or $Config.version -lt 1 -or $Config.version -gt $script:SlopConfigVersion) {
        $errors.Add('version is unsupported')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Config.name) -or ([string]$Config.name).Length -gt 40) {
        $errors.Add('name must be 1-40 characters')
    }
    if (([string]$Config.ownerName).Length -gt 40) { $errors.Add('ownerName must be at most 40 characters') }
    if ($Config.ContainsKey('instructions') -and ([string]$Config.instructions).Length -gt 1200) { $errors.Add('instructions must be at most 1200 characters') }
    if (-not $script:SlopIdentityColors.ContainsKey([string]$Config.color)) { $errors.Add('color is not an identity swatch') }
    if ($script:SlopPersonalities -notcontains [string]$Config.personality) { $errors.Add('personality preset is unknown') }
    if ($script:SlopBrains -notcontains [string]$Config.brain) { $errors.Add('brain choice is unknown') }
    if (([string]$Config.modelName).Length -gt 120) { $errors.Add('modelName is too long') }
    if ($Config.brain -eq 'custom') {
        if (-not (Test-SlopLoopbackHttpUrl -Url ([string]$Config.endpointUrl))) {
            $errors.Add('endpointUrl must be a local http URL')
        }
    }
    if ($Config.autostart -isnot [bool]) { $errors.Add('autostart must be a boolean') }

    # Route fields: keep them bounded and enumerable so a tampered config cannot
    # silently escalate a route or a capability profile.
    if ([string]$Config.providerLocality -notin @('', 'local', 'remote')) {
        $errors.Add('providerLocality must be local or remote')
    }
    if ([string]$Config.providerTier -notin @('free', 'paid')) {
        $errors.Add('providerTier must be free or paid')
    }
    if ($script:SlopCapabilityProfiles -notcontains [string]$Config.capabilityProfile) {
        $errors.Add('capabilityProfile is unknown')
    }
    if (([string]$Config.provider).Length -gt 80) { $errors.Add('provider is too long') }
    if (([string]$Config.model).Length -gt 120) { $errors.Add('model is too long') }
    if (([string]$Config.localModelName).Length -gt 120) { $errors.Add('localModelName is too long') }
    if (([string]$Config.localModelFile).Length -gt 260) { $errors.Add('localModelFile is too long') }
    if (([string]$Config.localMmprojFile).Length -gt 260) { $errors.Add('localMmprojFile is too long') }
    if (@(8192, 16384, 32768) -notcontains [int]$Config.localContextSize) { $errors.Add('localContextSize must be 8192, 16384, or 32768') }
    if ($Config.localVisionReady -isnot [bool]) { $errors.Add('localVisionReady must be a boolean') }
    if ($Config.localAudioReady -isnot [bool]) { $errors.Add('localAudioReady must be a boolean') }
    if (([string]$Config.agentId).Length -gt 80) { $errors.Add('agentId is too long') }
    if (([string]$Config.serviceConfigPath).Length -gt 260) { $errors.Add('serviceConfigPath is too long') }
    if (([string]$Config.openCodeBaseUrl).Length -gt 260) { $errors.Add('openCodeBaseUrl is too long') }
    if (-not [string]::IsNullOrWhiteSpace([string]$Config.openCodeBaseUrl) -and
        -not (Test-SlopLoopbackHttpUrl -Url ([string]$Config.openCodeBaseUrl))) {
        $errors.Add('openCodeBaseUrl must be a loopback http URL without embedded credentials or query data')
    }
    if (([string]$Config.openCodeSessionId).Length -gt 120) { $errors.Add('openCodeSessionId is too long') }
    if ($null -ne $Config.agent -and $Config.agent -isnot [hashtable]) { $errors.Add('agent must be a hashtable') }

    return @{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function Read-SlopConfig {
    param([string]$ConfigPath = (Get-SlopConfigPath))
    $defaults = New-SlopDefaultConfig
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return @{ Ok = $true; Exists = $false; Config = $defaults; Reason = $null }
    }
    try { $raw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json }
    catch { return @{ Ok = $false; Exists = $true; Config = $defaults; Reason = 'config.json is not valid JSON' } }

    # Unknown keys are ignored. Missing known keys take defaults. Version 0/absent
    # is the pre-release shape and is migrated to version 1 before validation.
    $cfg = @{}
    foreach ($key in $defaults.Keys) {
        $cfg[$key] = if ($raw.PSObject.Properties[$key]) { $raw.$key } else { $defaults[$key] }
    }
    if ($cfg.version -isnot [int] -or $cfg.version -lt 1) { $cfg.version = 1 }
    if ([string]$cfg.brain -eq 'builtin' -or [string]$cfg.brain -eq 'custom' -or [string]$cfg.brain -eq 'opencode') {
        # normalise JSON booleans and strings without accepting arbitrary values
        $cfg.autostart = [bool]$cfg.autostart
    }
    # Local bundled brain readiness hooks: keep backward-compatible defaults and
    # normalize invalid enum/bool values to safe defaults.
    $allowedLocalCtx = @(8192, 16384, 32768)
    if ($allowedLocalCtx -notcontains [int]$cfg.localContextSize) { $cfg.localContextSize = 8192 }
    $cfg.localVisionReady = [bool]$cfg.localVisionReady
    $cfg.localAudioReady = [bool]$cfg.localAudioReady
    if ([string]::IsNullOrWhiteSpace([string]$cfg.localModelName)) { $cfg.localModelName = $defaults.localModelName }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.localModelFile)) { $cfg.localModelFile = $defaults.localModelFile }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.localMmprojFile)) { $cfg.localMmprojFile = $defaults.localMmprojFile }
    # A JSON object for 'agent' arrives as PSCustomObject; the route resolver
    # only needs hashtable-style member access, so normalise it explicitly.
    if ($cfg.agent -isnot [hashtable]) {
        $agent = @{}
        if ($null -ne $cfg.agent) {
            foreach ($prop in $cfg.agent.PSObject.Properties) { $agent[$prop.Name] = $prop.Value }
        }
        $cfg.agent = $agent
    }
    $check = Test-SlopConfig -Config $cfg
    if (-not $check.Ok) {
        return @{ Ok = $false; Exists = $true; Config = $defaults; Reason = ($check.Errors -join '; ') }
    }
    return @{ Ok = $true; Exists = $true; Config = $cfg; Reason = $null }
}

function Write-SlopConfig {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$ConfigPath = (Get-SlopConfigPath)
    )
    $check = Test-SlopConfig -Config $Config
    if (-not $check.Ok) { throw "refusing to write invalid config: $($check.Errors -join '; ')" }
    $dir = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (Test-Path -LiteralPath $ConfigPath) {
        Copy-Item -LiteralPath $ConfigPath -Destination "$ConfigPath.bak" -Force
    }
    $tmp = "$ConfigPath.tmp"
    [IO.File]::WriteAllText($tmp, ($Config | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($tmp, $ConfigPath, $true)
}

function Read-SlopPersona {
    param([string]$PersonaPath = (Get-SlopPersonaPath))
    if (Test-Path -LiteralPath $PersonaPath) { return Get-Content -LiteralPath $PersonaPath -Raw }
    return ''
}
function Write-SlopPersona {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$PersonaPath = (Get-SlopPersonaPath)
    )
    $dir = Split-Path -Parent $PersonaPath
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText($PersonaPath, $Text, [Text.UTF8Encoding]::new($false))
}

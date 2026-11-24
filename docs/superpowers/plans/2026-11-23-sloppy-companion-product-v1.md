# Sloppy Companion Product v1 Implementation Plan

> **For agentic workers:** Execute with `executing-plans`. No subagents (user cost constraint). No commits — the user stages and commits. No remote, push, PR, deploy, or CI/CD changes.

**Goal:** Turn Sloppy from a developer-facing OpenCode frontend into a product an ordinary Windows user can install with one double-click, use offline with a bundled local model by default, and optionally point at a controlled OpenCode harness with full route disclosure — without changing the proven visual state machinery.

**Architecture:** Headless PowerShell modules (config, local model, provider seam, route resolution, controlled OpenCode profile, disclosure, surfaces, onboarding) plus two adapter modules. `src/Slop.ps1` receives wiring only: dot-sources, a config/onboarding bootstrap, an always-visible route badge, four quiet destination panels, a thin adapter dispatch inside `Start-Stream`, and tray items. The DispatcherTimer tick body in `Start-Stream` (currently lines 1037–1164), `Slop.Motion.ps1`, `Slop.Frame.ps1`, `Slop.Face.ps1`, `Slop.Lifecycle.ps1`, and the existing assertions in `tools/verify-motion.ps1` are **not modified**. Every adapter feeds the same `ConcurrentQueue[string]` the OpenCode bridge feeds today, so every existing signal, cancellation, and finalization path is reused unchanged.

**Tech Stack:** PowerShell 7.6, WPF/XAML, `System.Net.Http`, llama.cpp `llama-server.exe`, Qwen3-4B-GGUF Q4_K_M, a pinned OpenCode v2 service for the opt-in route, WiX v5 (Burn bundle + two per-user MSIs), Pester 6.

**Source spec:** `docs/superpowers/specs/2026-11-23-sloppy-companion-product-v1-design.md` (amended 2026-11-23).

**Amendment 1 applies:** Tasks 8–14 and the supersession table at the end of this document add the reviewed route, UI, disclosure, and security scope. Where Part B conflicts with Tasks 1–7, Part B wins. Automatic failover is deferred, not planned.

**Facts verified during planning (do not re-litigate):**
- `Qwen/Qwen3-4B-GGUF` ships an Apache License 2.0 file; Q4_K_M is ~2.5 GB. Bundling is permitted; attribution must ship.
- WiX v5 uses `Package Scope="perUser"`, `LocalAppDataFolder`, and an HKCU `RegistryValue KeyPath="yes"` for per-user components (ICE38/ICE64).
- llama.cpp server flags are `--model`, `--host`, `--port`, `--ctx-size`, `--cache-ram 0`, `--threads`, `--n-predict`, `--alias`.
- `src/Slop.Lifecycle.ps1:159` `Read-SlopSseStream` already parses OpenAI-style `data: {"choices":[{"delta":{"content":...}}]}` frames and `[DONE]`, and already uses `ReadLineAsync($Token)`. Do **not** write a second SSE parser or a second cancellation path.
- `Resolve-SlopStreamToken` (`src/Slop.Lifecycle.ps1:209`) recognizes exactly `__DONE__`, `__CONNECTED__`, `__WARN__*`, `__ERR__*`, `__TOK__*`; unmarked text is already a token. The OpenAI adapter can enqueue raw deltas because it emits no mid-stream control markers.

---

## File structure

| File | Responsibility |
| --- | --- |
| `src/Slop.Config.ps1` (new) | `%LOCALAPPDATA%\Sloppy\` paths, schema, validation, versioned migration, atomic writes, persona file, autostart value |
| `src/Slop.LocalModel.ps1` (new) | Bundled runtime paths, llama-server argument construction, health probe, process start/stop, plain-language failures |
| `src/Slop.Provider.ps1` (new) | Adapter contract, OpenAI chat body builder, stream-plan resolution, identity accent palette |
| `src/Slop.Adapter.OpenAi.ps1` (new) | Built-in and custom-endpoint adapter (OpenAI-compatible streaming) |
| `src/Slop.Adapter.OpenCode.ps1` (new) | First-class Tier 2 OpenCode adapter; job body moved verbatim from `src/Slop.ps1` (Part B) |
| `src/Slop.Route.ps1` (new, Part B) | Route taxonomy, effective model resolution, always-visible badge string |
| `src/Slop.OpenCodeProfile.ps1` (new, Part B) | Capability profiles → controlled config + hard-deny policies; effective-permission verification |
| `src/Slop.Disclosure.ps1` (new, Part B) | Provider-specific data path, verified terms links, no blanket retention claims |
| `src/Slop.Surfaces.ps1` (new, Part B) | Headless helpers for Settings / Customize / Brain / Privacy and the three deletion scopes |
| `src/Slop.Onboarding.ps1` (new) | Four-screen WPF wizard, persona presets, persona markdown builder |
| `src/Slop.ps1` (modify) | Adapter/config/tray wiring only; timer dispatch untouched |
| `tests/slop-config-check.ps1` (new) | Config defaults, validation, migration, corrupt recovery, atomic backup |
| `tests/slop-provider-check.ps1` (new) | Chat body, stream plan, fake SSE deltas, terminal, cancellation, malformed frames |
| `tests/slop-localmodel-check.ps1` (new) | Runtime paths, launch arguments, health parsing, port conflict, failure copy |
| `tests/slop-onboarding-check.ps1` (new) | Persona presets, persona markdown, name/color validation |
| `tests/slop-route-check.ps1` (new, Part B) | Route taxonomy, badge strings, agent model preference, recomputation on switch |
| `tests/slop-opencode-profile-check.ps1` (new, Part B) | Profile rules, hard-deny presence, fail-closed verification, no `Allow always` |
| `tests/slop-disclosure-check.ps1` (new, Part B) | Verified provider terms, no blanket retention or permanent-free wording |
| `tests/slop-surfaces-check.ps1` (new, Part B) | Distinct destinations and distinct deletion scopes |
| `installer/SloppyApp.wxs` (new) | Per-user app MSI: scripts, shortcut, autostart, data directory |
| `installer/SloppyPayload.wxs` (new) | Per-user payload MSI: llama.cpp runtime + sharded GGUF, multi-cab media |
| `installer/SloppyBundle.wxs` (new) | WiX v5 Burn bundle producing the single signed `.exe` |
| `installer/Build-Installer.ps1` (new) | Builds both MSIs and the bundle, optionally signs with a user-supplied cert |
| `installer/THIRD-PARTY-NOTICES.txt` (new) | Apache-2.0 attribution for Qwen3 and llama.cpp |
| `tools/bootstrap-sloppy.ps1` (new) | One-line bootstrap taking a required `-ReleaseBaseUrl` parameter |
| `tools/verify-motion.ps1` (modify) | **Append-only** onboarding + bundled-reply checks; existing assertions unchanged |
| `.gitignore` (modify) | Ignore `installer/payload/` and generated MSI/EXE output |

Deliberately untouched: `src/Slop.Motion.ps1`, `src/Slop.Frame.ps1`, `src/Slop.Face.ps1`, `src/Slop.Sense.ps1`, `src/Slop.Lifecycle.ps1` (except no changes at all), `src/Slop.OpenCode.ps1`, all existing `tests/*-check.ps1` files, `.tours/architect-slop-architecture.tour` (only its anchors are refreshed in Task 5), and all untracked user-owned docs.

---

## Task 1: Portable configuration module

**Files:**
- Create: `src/Slop.Config.ps1`
- Create: `tests/slop-config-check.ps1`

- [ ] **Step 1: Write `src/Slop.Config.ps1`**

Write exactly this module. It is headless: no WPF, no network, no registry writes at import time.

```powershell
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
$script:SlopPersonalities = @('calm', 'playful', 'curious', 'professional')
$script:SlopBrains = @('builtin', 'custom')

function Get-SlopUserDataPath {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set' }
    return Join-Path $env:LOCALAPPDATA 'Sloppy'
}
function Get-SlopConfigPath    { return Join-Path (Get-SlopUserDataPath) 'config.json' }
function Get-SlopPersonaPath   { return Join-Path (Get-SlopUserDataPath) 'persona.md' }
function Get-SlopIdentityColors { return @{} + $script:SlopIdentityColors }
function Get-SlopPersonalities  { return @($script:SlopPersonalities) }
function Get-SlopBrains         { return @($script:SlopBrains) }
function Get-SlopIdentityColor {
    param([Parameter(Mandatory)][string]$ColorKey)
    if (-not $script:SlopIdentityColors.ContainsKey($ColorKey)) { throw "unknown identity color: $ColorKey" }
    return $script:SlopIdentityColors[$ColorKey]
}

function New-SlopDefaultConfig {
    return @{
        version    = $script:SlopConfigVersion
        name       = 'Sloppy'
        ownerName  = ''
        color      = 'ocean'
        personality = 'calm'
        brain      = 'builtin'
        endpointUrl = ''
        modelName  = ''
        autostart  = $true
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
    if (-not $script:SlopIdentityColors.ContainsKey([string]$Config.color)) { $errors.Add('color is not an identity swatch') }
    if ($script:SlopPersonalities -notcontains [string]$Config.personality) { $errors.Add('personality preset is unknown') }
    if ($script:SlopBrains -notcontains [string]$Config.brain) { $errors.Add('brain choice is unknown') }
    if (([string]$Config.modelName).Length -gt 120) { $errors.Add('modelName is too long') }
    if ($Config.brain -eq 'custom') {
        $uri = $null
        if (-not [Uri]::TryCreate([string]$Config.endpointUrl, [UriKind]::Absolute, [ref]$uri) -or
            $uri.Scheme -ne 'http' -or
            $uri.Host -notin @('127.0.0.1', 'localhost', '::1')) {
            $errors.Add('endpointUrl must be a local http URL')
        }
    }
    if ($Config.autostart -isnot [bool]) { $errors.Add('autostart must be a boolean') }
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
    if ([string]$cfg.brain -eq 'builtin' -or [string]$cfg.brain -eq 'custom') {
        # normalise JSON booleans and strings without accepting arbitrary values
        $cfg.autostart = [bool]$cfg.autostart
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
```

- [ ] **Step 2: Verify the module imports and path helpers**

Run:
```powershell
pwsh -NoProfile -Command ". ./src/Slop.Config.ps1; Get-SlopConfigPath; Get-SlopIdentityColor ocean; (Get-SlopIdentityColors).Count"
```
Expected: paths resolve under the local app data directory, `#6366F1` is printed, and `6` is printed.

- [ ] **Step 3: Write `tests/slop-config-check.ps1`**

Write a Pester 6 suite that dot-sources `src/Slop.Config.ps1` and covers, at minimum:
1. `New-SlopDefaultConfig` passes `Test-SlopConfig`.
2. All six identity colors are returned and none equals a semantic signal hex (`#3B82F6`, `#F59E0B`, `#22C55E`, `#EF4444`).
3. `Test-SlopConfig` rejects an unknown color, unknown personality, unknown brain, a `custom` brain with a non-local `endpointUrl`, a 41-character name, and a non-boolean `autostart`.
4. `Read-SlopConfig` on a nonexistent path returns `Ok=$true; Exists=$false` with defaults.
5. `Read-SlopConfig` ignores unknown keys and fills missing known keys from defaults.
6. A file with `version: 0` is migrated to version 1 in memory and passes validation.
7. A file containing `{ not json` returns `Ok=$false` with a plain-language reason and defaults.
8. Two consecutive `Write-SlopConfig` calls leave a `.bak` file whose content is the first config.
9. `Write-SlopConfig` throws on an invalid config and does not create the file.
10. `Get-SlopAutostartValue 'C:\Program Files\Sloppy\launch.exe'` returns a quoted path; embedded quotes are escaped.
11. `Write-SlopPersona` / `Read-SlopPersona` round-trip Unicode text through UTF-8 without BOM.

Use per-test temp directories created in `BeforeEach` and removed in `AfterEach`. Do not write to the real user data directory in tests.

- [ ] **Step 4: Run the new suite**

Run:
```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-config-check.ps1' -CI -Output Normal"
```
Expected: all tests pass, exit code 0.

---

## Task 2: Provider seam and adapter contract

**Files:**
- Create: `src/Slop.Provider.ps1`
- Create: `src/Slop.Adapter.OpenAi.ps1`
- Create: `src/Slop.Adapter.OpenCode.ps1`
- Create: `tests/slop-provider-check.ps1`

- [ ] **Step 1: Write `src/Slop.Provider.ps1`**

```powershell
# Adapter contract and request planning. Headless; no WPF and no network.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-SlopIdentityColors -ErrorAction SilentlyContinue)) {
    throw 'Slop.Config.ps1 must be dot-sourced before Slop.Provider.ps1'
}
. (Join-Path $PSScriptRoot 'Slop.LocalModel.ps1')

function Get-SlopAdapterContract {
    return @{
        Version        = 1
        MarkerContract = @('__DONE__', '__CONNECTED__', '__WARN__', '__ERR__', '__TOK__', '__OC')
        QueueType      = 'System.Collections.Concurrent.ConcurrentQueue[string]'
        EntryPoint     = 'Invoke-SlopAdapter'
    }
}

function New-SlopChatRequestBody {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$SystemPrompt,
        [Parameter(Mandatory)][AllowEmptyString()][string]$UserText,
        [int]$MaxLength = 8000
    )
    if ($UserText.Length -gt $MaxLength) { throw "prompt exceeds $MaxLength characters" }
    $messages = [Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
        $messages.Add(@{ role = 'system'; content = $SystemPrompt })
    }
    $messages.Add(@{ role = 'user'; content = $UserText })
    return @{
        model       = 'sloppy'
        messages    = $messages.ToArray()
        stream      = $true
        temperature = 0.8
        max_tokens  = 512
    } | ConvertTo-Json -Depth 6 -Compress
}

function Get-SlopStreamPlan {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserText,
        [string]$PersonaText = '',
        [Parameter(Mandatory)][string]$ScriptRootPath,
        [Parameter(Mandatory)][string]$RepoRootPath
    )
    # Developer-only escape hatch. It is never exposed in onboarding and does not
    # appear in config.json, so the shipped product has no OpenCode dependency.
    if ($env:SLOP_ADAPTER -eq 'opencode') {
        $bridge = Join-Path $ScriptRootPath 'Slop.OpenCode.ps1'
        $lifecycle = Join-Path $ScriptRootPath 'Slop.Lifecycle.ps1'
        $baseUrl = if ($env:OPENCODE_BASE_URL) { $env:OPENCODE_BASE_URL } else { 'http://127.0.0.1:28894' }
        $auth = New-SlopOpenCodeAuthHeader
        return @{
            Ok = $true; Kind = 'opencode'; StatusText = 'Connecting to OpenCode'
            AdapterPath = (Join-Path $ScriptRootPath 'Slop.Adapter.OpenCode.ps1')
            AdapterArgs = @{
                BaseUrl = $baseUrl; PromptBody = (New-SlopPromptBody -Text $UserText)
                LifecyclePath = $lifecycle; BridgePath = $bridge; Auth = $auth
                EventTypes = @(Get-SlopOpenCodeEventTypes); TimeoutSeconds = 300
                SessionId = $env:SLOP_OPENCODE_SESSION_ID
            }
        }
    }

    $body = New-SlopChatRequestBody -SystemPrompt $PersonaText -UserText $UserText
    $lifecycle = Join-Path $ScriptRootPath 'Slop.Lifecycle.ps1'
    $adapter = Join-Path $ScriptRootPath 'Slop.Adapter.OpenAi.ps1'

    if ([string]$Config.brain -eq 'custom') {
        return @{
            Ok = $true; Kind = 'custom'; StatusText = 'Waiting for response'
            AdapterPath = $adapter
            AdapterArgs = @{
                BaseUrl = ([string]$Config.endpointUrl).TrimEnd('/')
                RequestBody = $body; LifecyclePath = $lifecycle; TimeoutSeconds = 300
            }
        }
    }

    $paths = Get-SlopRuntimePaths
    $pre = Test-SlopLocalModelPaths -Paths $paths
    if (-not $pre.Ok) { return @{ Ok = $false; Kind = 'builtin'; Reason = $pre.Reason } }
    $start = Start-SlopLocalModel -Paths $paths
    if (-not $start.Ok) { return @{ Ok = $false; Kind = 'builtin'; Reason = $start.Reason } }
    return @{
        Ok = $true; Kind = 'builtin'; StatusText = 'Waking up'; Process = $start.Process
        AdapterPath = $adapter
        AdapterArgs = @{
            BaseUrl = "http://127.0.0.1:$($paths.Port)"
            RequestBody = $body; LifecyclePath = $lifecycle; TimeoutSeconds = 300
        }
    }
}
```

- [ ] **Step 2: Write `src/Slop.Adapter.OpenAi.ps1`**

```powershell
# OpenAI-compatible streaming adapter for the built-in model and custom endpoints.
# Enqueues only the control markers understood by Resolve-SlopStreamToken.
$ErrorActionPreference = 'Stop'

function Invoke-SlopAdapter {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$RequestBody,
        [Parameter(Mandatory)][string]$LifecyclePath,
        [Parameter(Mandatory)][System.Collections.Concurrent.ConcurrentQueue[string]]$Queue,
        [Parameter(Mandatory)][System.Threading.CancellationToken]$Token,
        [int]$TimeoutSeconds = 300
    )
    . $LifecyclePath
    $client = $null; $resp = $null; $stream = $null; $reader = $null
    try {
        $client = [Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $req = [Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/v1/chat/completions")
        $req.Content = [Net.Http.StringContent]::new($RequestBody, [Text.Encoding]::UTF8, 'application/json')
        $resp = $client.SendAsync($req, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $Token).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) {
            $Queue.Enqueue("__ERR__HTTP $([int]$resp.StatusCode)")
            return
        }
        $Queue.Enqueue('__CONNECTED__')
        $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [IO.StreamReader]::new($stream)
        # Reuses the proven token-aware reader; no new SSE or cancellation code.
        $stats = Read-SlopSseStream -Reader $reader -Queue $Queue -Token $Token
        if ($stats.Cancelled) { $Queue.Enqueue('__ERR__Cancelled') }
        elseif ($stats.Malformed -gt 0 -and $stats.Tokens -eq 0) {
            $Queue.Enqueue("__ERR__Malformed stream ($($stats.Malformed) frame(s))")
        }
        elseif ($stats.Malformed -gt 0) {
            $Queue.Enqueue("__WARN__$($stats.Malformed) malformed frame(s)")
        }
    }
    catch [System.Threading.Tasks.TaskCanceledException] {
        if ($Token.IsCancellationRequested) { $Queue.Enqueue('__ERR__Cancelled') }
        else { $Queue.Enqueue("__ERR__Timeout $TimeoutSeconds") }
    }
    catch [System.OperationCanceledException] { $Queue.Enqueue('__ERR__Cancelled') }
    catch { $Queue.Enqueue("__ERR__$($_.Exception.Message)") }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($resp) { $resp.Dispose() }
        if ($client) { $client.Dispose() }
    }
}
```

- [ ] **Step 3: Create `src/Slop.Adapter.OpenCode.ps1` by verbatim extraction**

Copy the body of the existing `Start-ThreadJob` scriptblock from `src/Slop.ps1` lines 960–1031 into a function with this signature:

```powershell
function Invoke-SlopAdapter {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$PromptBody,
        [Parameter(Mandatory)][string]$LifecyclePath,
        [Parameter(Mandatory)][string]$BridgePath,
        [Parameter(Mandatory)][hashtable]$Auth,
        [Parameter(Mandatory)][string[]]$EventTypes,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [string]$SessionId,
        [Parameter(Mandatory)][System.Collections.Concurrent.ConcurrentQueue[string]]$Queue,
        [Parameter(Mandatory)][System.Threading.CancellationToken]$Token
    )
    # ... the verbatim body from lines 962-1029 ...
}
```

Two mechanical edits only: (a) `$Cts.Token` becomes `$Token`; (b) delete the final `$Queue.Enqueue('__DONE__')` from the `finally` block because the thin dispatcher in Task 5 now owns it. Keep session-create, agent pinning, SSE subscription, prompt, `Read-SlopOpenCodeSse`, `__OCSESSION__`, and all error mapping byte-for-byte.

- [ ] **Step 4: Write `tests/slop-provider-check.ps1`**

Pester 6 suite. Dot-source `Slop.Config.ps1`, `Slop.LocalModel.ps1`, `Slop.Provider.ps1`, and `Slop.Adapter.OpenAi.ps1`. Cover:
1. `Get-SlopAdapterContract` reports version 1 and lists every marker used by `Resolve-SlopStreamToken`.
2. `New-SlopChatRequestBody` produces `stream: true`, a system message when a persona is supplied, no system message when it is blank, and throws above 8000 characters.
3. `Get-SlopStreamPlan` with `brain='custom'` returns `Kind='custom'`, the URL with the trailing slash removed, and the OpenAI adapter path — with no local-model calls.
4. `Get-SlopStreamPlan` with `brain='builtin'` returns `Kind='builtin'` and a loopback URL when runtime paths exist; returns `Ok=$false` with plain-language reason when they do not.
5. `SLOP_ADAPTER=opencode` selects the OpenCode adapter and does not read `config.json` (set and restore the env var in `BeforeEach`/`AfterEach`).
6. Feed a `StringReader` containing two `data: {...delta.content...}` lines, a blank line, and `data: [DONE]` into `Read-SlopSseStream`; assert two raw tokens and `Malformed=0`.
7. Feed one valid frame plus one `data: {broken` frame; assert `Malformed=1` and that the valid token still arrived.
8. Pre-cancel a `CancellationTokenSource` and call `Read-SlopSseStream` with a stalled `StringReader`; assert `Cancelled=$true` and completion under 2 seconds.
9. Drive `Invoke-SlopAdapter` against an in-test `[Net.Sockets.TcpListener]` bound to `[Net.IPAddress]::Loopback` on port 0; read the assigned port from `$listener.LocalEndpoint.Port` and pass `http://127.0.0.1/` plus that port as `BaseUrl`. The listener writes a minimal HTTP 200 response with an SSE body on a background job. Assert `__CONNECTED__`, two token strings, and no `__ERR__` after the dispatcher's own `__DONE__` is appended by the test. Always stop the listener and remove the job in a `finally` block.

- [ ] **Step 5: Run the suite**

Run:
```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-provider-check.ps1' -CI -Output Normal"
```
Expected: all tests pass, exit code 0.

---

## Task 3: Built-in local model lifecycle

**Files:**
- Create: `src/Slop.LocalModel.ps1`
- Create: `tests/slop-localmodel-check.ps1`

- [ ] **Step 1: Write `src/Slop.LocalModel.ps1`**

```powershell
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
    if ($Threads -le 0) { $Threads = [Math]::Max(2, [Math]::Min(8, [Environment]::ProcessorCount - 2)) }
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
    try {
        $resp = Invoke-WebRequest -Uri "$BaseUrl/health" -Method Get -TimeoutSec ([Math]::Max(1, [int]($TimeoutMs / 1000))) -UseBasicParsing
        return @{ Ok = ($resp.StatusCode -eq 200); Reason = $null }
    }
    catch { return @{ Ok = $false; Reason = $_.Exception.Message } }
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
    param([Parameter(Mandatory)][hashtable]$Paths, [int]$WaitSeconds = 90)
    $pre = Test-SlopLocalModelPaths -Paths $Paths
    if (-not $pre.Ok) { return @{ Ok = $false; Reason = $pre.Reason; Process = $null } }
    $health = Test-SlopLocalModelHealth -BaseUrl $Paths.BaseUrl -TimeoutMs 500
    if ($health.Ok) { return @{ Ok = $true; Reason = $null; Process = $null } }
    if (-not (Test-SlopPortAvailable -Port $Paths.Port)) {
        return @{ Ok = $false; Reason = 'another program is using the local brain port; close it or restart your PC'; Process = $null }
    }
    $llamaArgs = New-SlopLlamaArguments -Paths $Paths
    $proc = Start-Process -FilePath $Paths.ServerExe -ArgumentList $llamaArgs -PassThru -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($proc.HasExited) {
            return @{ Ok = $false; Reason = 'the built-in brain stopped while starting; close other apps to free memory and try again'; Process = $null }
        }
        if ((Test-SlopLocalModelHealth -BaseUrl $Paths.BaseUrl -TimeoutMs 500).Ok) {
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
```

- [ ] **Step 2: Write `tests/slop-localmodel-check.ps1`**

Pester 6 suite covering:
1. `Get-SlopRuntimePaths` returns paths under a supplied fake install root and port 18080.
2. `Test-SlopLocalModelPaths` fails separately for a missing server, missing model, and invalid port; succeeds when fake files are created in a temp directory.
3. `New-SlopLlamaArguments` contains `--ctx-size 4096`, `--cache-ram 0`, `--host 127.0.0.1`, `--port 18080`, `--alias sloppy`, and clamps threads to 2–8.
4. `Test-SlopPortAvailable` returns `$false` while a `TcpListener` holds an ephemeral loopback port and `$true` after it stops.
5. `Test-SlopLocalModelHealth` returns `Ok=$false` for an unused local port without throwing.
6. `Format-SlopLocalModelFailure` gives the memory-specific copy for an OOM-style reason and the generic tray hint otherwise.
7. `Stop-SlopLocalModel` is a no-op for `$null` and for an already-exited process (use a short-lived `pwsh` child process, with a `finally` teardown).

- [ ] **Step 3: Run the suite**

Run:
```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-localmodel-check.ps1' -CI -Output Normal"
```
Expected: all tests pass, exit code 0.

---

## Task 4: Four-screen onboarding

**Files:**
- Create: `src/Slop.Onboarding.ps1`
- Create: `tests/slop-onboarding-check.ps1`

- [ ] **Step 1: Write the persona presets and markdown builder**

In `src/Slop.Onboarding.ps1`, define exactly these presets and this builder. The sample lines are the live preview copy shown on screen 3.

```powershell
# Four-screen first-run wizard. WPF is confined to Show-SlopOnboarding; the
# preset and markdown helpers below stay headless for tests.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-SlopIdentityColors -ErrorAction SilentlyContinue)) {
    throw 'Slop.Config.ps1 must be dot-sourced before Slop.Onboarding.ps1'
}

$script:SlopPresetPersonas = @{
    calm         = @{ Label = 'Calm';         Sample = 'Let us take this one step at a time. No rush.' }
    playful      = @{ Label = 'Playful';      Sample = 'Okay, that is a delightfully weird question. I am in.' }
    curious      = @{ Label = 'Curious';      Sample = 'Ooh — tell me more about that. What made you think of it?' }
    professional = @{ Label = 'Professional'; Sample = 'Understood. Here is the concise answer, then the trade-offs.' }
}

function Get-SlopPersonaPresets {
    return @($script:SlopPresetPersonas.Keys | Sort-Object | ForEach-Object {
        [pscustomobject]@{ Id = $_; Label = $script:SlopPresetPersonas[$_].Label; Sample = $script:SlopPresetPersonas[$_].Sample }
    })
}

function New-SlopPersonaMarkdown {
    param(
        [Parameter(Mandatory)][ValidateSet('calm','playful','curious','professional')][string]$Preset,
        [Parameter(Mandatory)][string]$Name,
        [string]$OwnerName = '',
        [AllowEmptyString()][string]$CustomText = ''
    )
    $voice = @{
        calm         = 'Speak calmly and briefly. Never rush the user.'
        playful      = 'Be warm, light and playful. Use the occasional dry joke.'
        curious      = 'Lead with genuine curiosity and one follow-up question.'
        professional = 'Be concise, precise and structured. State trade-offs.'
    }[$Preset]
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("You are $Name, a small private desktop companion.")
    if (-not [string]::IsNullOrWhiteSpace($OwnerName)) {
        $lines.Add("The person you talk to goes by $OwnerName. Use it only when it feels natural.")
    }
    $lines.Add($voice)
    $lines.Add('You live on the users computer. You have no accounts, no cloud and no tools.')
    $lines.Add('Be honest about what you can and cannot do. Keep replies short enough to read at a glance.')
    if (-not [string]::IsNullOrWhiteSpace($CustomText)) {
        $lines.Add('')
        $lines.Add('Additional instructions from the user:')
        $lines.Add($CustomText.Trim())
    }
    return ($lines -join "`n") + "`n"
}
```

- [ ] **Step 2: Write the WPF wizard**

Add `function Show-SlopOnboarding` in the same file. Contract:
- Params: `[Parameter(Mandatory)][hashtable]$Config`, `[ValidateRange(1,4)][int]$StartScreen = 1`.
- Builds its own XAML with `WindowStyle="None"`, `AllowsTransparency="True"`, width 520, height 360, dark rounded `Border`, and these named elements: `NameBox`, `OwnerBox`, `SwatchStrip` (`WrapPanel`), `PreviewPea` (`Ellipse` 26x26), `PresetList` (`StackPanel` of `RadioButton`s), `SampleLine` (`TextBlock`), `CustomBox` (`TextBox`, multiline), `BrainBuiltIn` / `BrainCustom` (`RadioButton`s), `EndpointRow` (`StackPanel`, initially `Collapsed`), `ModelBox` (`TextBox`), `BrainNote` (`TextBlock`), `BackBtn`, `NextBtn`, `CloseBtn`.
- Screen 1 = name, screen 2 = color, screen 3 = personality, screen 4 = brain. Only one screen `Grid` is `Visible` at a time; `StartScreen` selects the first.
- Swatches are generated from `Get-SlopIdentityColors`; clicking one sets `PreviewPea.Fill` immediately and sets `$script:SelectedColor`. Semantic signal colors never appear in this strip.
- Selecting a preset updates `SampleLine.Text` from `Get-SlopPersonaPresets`.
- `BrainCustom` expands `EndpointRow`, restricts input to a local `http` URL using the same rule as `Test-SlopConfig`, and sets `BrainNote` to: `Full CLI brains arrive in the next release. For now, enter any OpenAI-compatible local server URL.`
- Validation on Next: screen 1 requires a 1–40 character companion name; screen 4 requires a valid local endpoint and model name when custom is selected. Show a plain-language `TextBlock` error, never a dialog.
- Finish returns a hashtable with all config keys plus `personaText`; `CloseBtn` returns `$null`.
- Bind `Escape` to return `$null` and `Enter` to Next. Use `param($s,$e)` on every event handler and publish handler state to `$script:` scope — WinForms/WPF handlers here do not capture function locals (this has caused live bugs before).

- [ ] **Step 3: Headless onboarding tests**

Write `tests/slop-onboarding-check.ps1` as a Pester 6 suite:
1. `Get-SlopPersonaPresets` returns exactly four ids and each sample is non-empty.
2. `New-SlopPersonaMarkdown` includes the companion name, optional owner name, the preset's voice line, and the custom text.
3. Omitting the owner name leaves no `goes by` sentence; blank custom text adds no `Additional instructions` header.
4. Each of the four presets produces a distinct markdown body.
5. Output ends with a single newline and contains no CRLF.
6. Source-text assertion (regex on the file): the six swatch keys from `Get-SlopIdentityColors` are generated from that function rather than hard-coded, and `BrainNote` contains the honest next-release copy.

- [ ] **Step 4: Run the suite**

Run:
```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-onboarding-check.ps1' -CI -Output Normal"
```
Expected: all tests pass, exit code 0.

---

## Task 5: Wire the shell (wiring only)

**Files:**
- Modify: `src/Slop.ps1`
- Refresh: `.tours/architect-slop-architecture.tour` anchors only

- [ ] **Step 1: Add dot-sources at line 12**

Insert immediately after `. (Join-Path $PSScriptRoot 'Slop.OpenCode.ps1')`:

```powershell
. (Join-Path $PSScriptRoot 'Slop.Config.ps1')
. (Join-Path $PSScriptRoot 'Slop.LocalModel.ps1')
. (Join-Path $PSScriptRoot 'Slop.Provider.ps1')
. (Join-Path $PSScriptRoot 'Slop.Onboarding.ps1')
```

- [ ] **Step 2: Add identity ring to XAML**

Insert directly before `<Canvas x:Name="PeaCanvas" ...` (currently line 156):

```xml
    <Ellipse x:Name="IdentityRing" Width="30" Height="30" Canvas.Left="227" Canvas.Top="292"
             Fill="#6366F1" Opacity="0.35" IsHitTestVisible="False"/>
```

In `Update-PeaAnchor` (line 250), add after the `GroundShadow` Canvas.Top line:

```powershell
    [System.Windows.Controls.Canvas]::SetLeft($IdentityRing, ($w - 30.0) / 2.0)
    [System.Windows.Controls.Canvas]::SetTop($IdentityRing, [Math]::Max(0.0, $h - 42.0))
```

This is a decorative element only; `$SlopColors` and `Set-SlopVisualFromSignal` stay untouched.

- [ ] **Step 3: Bootstrap config and onboarding**

Insert after `$script:LastPokeAt = [DateTime]::UtcNow` (line 1205):

```powershell
function Save-SlopOnboardingResult {
    param([Parameter(Mandatory)][hashtable]$Result)
    # personaText is returned by the wizard but belongs in persona.md, not config.json.
    $cfg = @{}
    foreach ($key in (New-SlopDefaultConfig).Keys) {
        if ($Result.ContainsKey($key)) { $cfg[$key] = $Result[$key] }
    }
    Write-SlopConfig -Config $cfg
    Write-SlopPersona -Text ([string]$Result.personaText)
    return $cfg
}

function Sync-SlopAutostart {
    param([Parameter(Mandatory)][bool]$Enabled)
    $launcher = Join-Path (Split-Path $PSScriptRoot -Parent) 'launch.cmd'
    if (-not (Test-Path -LiteralPath $launcher)) { return }  # developer run, not installed
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Enabled) {
        New-ItemProperty -Path $runKey -Name 'Sloppy' `
            -Value (Get-SlopAutostartValue -ExecutablePath $launcher) `
            -PropertyType String -Force | Out-Null
    }
    else { Remove-ItemProperty -Path $runKey -Name 'Sloppy' -ErrorAction SilentlyContinue }
}

$script:SlopConfigResult = Read-SlopConfig
if ($script:SlopConfigResult.Ok -and -not $script:SlopConfigResult.Exists) {
    $onboarded = Show-SlopOnboarding -Config $script:SlopConfigResult.Config
    if ($null -eq $onboarded) {
        # A first run that is dismissed still gets a usable default persona.
        $onboarded = $script:SlopConfigResult.Config
        $onboarded.personaText = New-SlopPersonaMarkdown -Preset calm -Name 'Sloppy'
    }
    $saved = Save-SlopOnboardingResult -Result $onboarded
    Sync-SlopAutostart -Enabled ([bool]$saved.autostart)
    $script:SlopConfigResult.Config = $saved
}
elseif (-not $script:SlopConfigResult.Ok) {
    Add-SlopThoughtBubble -Text "Settings need attention: $($script:SlopConfigResult.Reason). Onboarding will open."
    $onboarded = Show-SlopOnboarding -Config $script:SlopConfigResult.Config
    if ($onboarded) {
        $saved = Save-SlopOnboardingResult -Result $onboarded
        Sync-SlopAutostart -Enabled ([bool]$saved.autostart)
        $script:SlopConfigResult = @{ Ok = $true; Exists = $true; Config = $saved; Reason = $null }
    }
}
$script:SlopIdentityBrush = [System.Windows.Media.SolidColorBrush]::new(
    [System.Windows.Media.BrushConverter]::new().ConvertFromString(
        (Get-SlopIdentityColor -ColorKey $script:SlopConfigResult.Config.color)))
$IdentityRing.Fill = $script:SlopIdentityBrush
$script:LocalModelProcess = $null
```

- [ ] **Step 4: Replace the Start-Stream preflight (lines 912–923)**

Replace that whole block with:

```powershell
    # The amber reaction is set before any blocking health probe so a cold model
    # wake still feels like the companion thinking. Failures clear it below.
    Set-SlopSignalEvent -State $script:Motion -Id 'request:preflight' -Kind thinking `
        -Status 'Getting ready' -Sticky
    $config = $script:SlopConfigResult.Config
    $streamPlan = Get-SlopStreamPlan `
        -Config $config -UserText $UserText -PersonaText (Read-SlopPersona) `
        -ScriptRootPath $PSScriptRoot -RepoRootPath (Split-Path $PSScriptRoot -Parent)
    if (-not $streamPlan.Ok) {
        Clear-SlopSignalEvent -State $script:Motion -Id 'request:preflight' | Out-Null
        Add-Bubble -Text "[error: $(Format-SlopLocalModelFailure -Reason $streamPlan.Reason)]" -IsUser $false
        return
    }
    if ($streamPlan.Kind -eq 'builtin' -and $null -ne $streamPlan.Process) {
        $script:LocalModelProcess = $streamPlan.Process
    }
```

Then change the existing status line at 936–937 from `'Connecting to OpenCode'` to `$streamPlan.StatusText`, and add immediately after it:

```powershell
Clear-SlopSignalEvent -State $script:Motion -Id 'request:preflight' | Out-Null
```

- [ ] **Step 5: Replace the thread-job block (lines 952–1031)**

Replace the whole job construction with the thin dispatcher. Keep lines 946–951 (queue creation and script-scope publication) exactly as they are.

```powershell
    $job = Start-ThreadJob -ScriptBlock {
        param($Plan, $Queue, $Cts)
        . $Plan.AdapterPath
        try {
            $invokeArgs = @{} + $Plan.AdapterArgs
            $invokeArgs.Queue = $Queue
            $invokeArgs.Token = $Cts.Token
            Invoke-SlopAdapter @invokeArgs
        }
        catch [System.OperationCanceledException] { $Queue.Enqueue('__ERR__Cancelled') }
        catch { $Queue.Enqueue("__ERR__$($_.Exception.Message)") }
        finally { $Queue.Enqueue('__DONE__') }
    } -ArgumentList $streamPlan, $queue, $script:Cts
```

Do **not** edit lines 1035–1167 (timer creation and tick dispatch), lines 1169–1188 (send action), or `Finish-Stream`.

- [ ] **Step 6: Extend the tray menu**

In `Minimize-ToTray` (line 616), insert before `$exit = $menu.Items.Add('Exit')`:

```powershell
    $editItem = $menu.Items.Add('Edit personality')
    $editItem.Add_Click({ Show-SlopOnboarding -Config $script:SlopConfigResult.Config -StartScreen 3 | Out-Null })

    $brainItem = $menu.Items.Add('Change brain')
    $brainItem.Add_Click({ Show-SlopOnboarding -Config $script:SlopConfigResult.Config -StartScreen 4 | Out-Null })

    $script:TrayAutostartItem = $menu.Items.Add("Autostart: $(if ($script:SlopConfigResult.Config.autostart) { 'On' } else { 'Off' })")
    $script:TrayAutostartItem.Add_Click({
        $script:SlopConfigResult.Config.autostart = -not $script:SlopConfigResult.Config.autostart
        Write-SlopConfig -Config $script:SlopConfigResult.Config
        Sync-SlopAutostart -Enabled ([bool]$script:SlopConfigResult.Config.autostart)
        $script:TrayAutostartItem.Text = "Autostart: $(if ($script:SlopConfigResult.Config.autostart) { 'On' } else { 'Off' })"
    })

    $script:TrayModelItem = $menu.Items.Add('Sleep model')
    $script:TrayModelItem.Add_Click({
        if ($script:LocalModelProcess) {
            Stop-SlopLocalModel -Process $script:LocalModelProcess
            $script:LocalModelProcess = $null
            $script:TrayModelItem.Text = 'Wake model'
            Add-SlopThoughtBubble -Text 'The built-in brain is asleep. Send a message to wake it.'
        }
        else {
            $script:TrayModelItem.Text = 'Sleep model'
        }
    })
```

The wake happens on the next `Get-SlopStreamPlan` call in Task 5 Step 4. Autostart is persisted in `config.json` by the tray handler and mirrored to the single HKCU Run value by `Sync-SlopAutostart` (installed builds only); the installer writes that same value at first run. No other registry writes exist.

- [ ] **Step 7: Verify shell syntax and refresh tour anchors**

Run:
```powershell
pwsh -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('src/Slop.ps1', [ref]$null, [ref]$null); 'parse ok'"
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-shell-check.ps1' -CI -Output Normal"
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-tour-check.ps1' -CI -Output Normal"
```
Expected: `parse ok`, shell suite green, tour suite green after anchors are refreshed to the new line numbers. Source edits shifted lines, so refresh every `file/line` anchor in `.tours/architect-slop-architecture.tour` and any inline line references in the same pass — do not leave stale anchors for a later commit.

---

## Task 6: Installer, bootstrap, and third-party notices

**Files:**
- Create: `installer/SloppyApp.wxs`, `installer/SloppyPayload.wxs`, `installer/SloppyBundle.wxs`
- Create: `installer/Build-Installer.ps1`, `installer/THIRD-PARTY-NOTICES.txt`
- Create: `tools/bootstrap-sloppy.ps1`
- Modify: `.gitignore`

User-owned prerequisites (do not attempt to obtain them): code-signing certificate, release host URL, the actual llama.cpp build and sharded GGUF files, a clean Windows VM.

- [ ] **Step 1: Ignore generated installer artifacts**

Append to `.gitignore`:

```
# Installer inputs/outputs (supplied by release process, not source)
/installer/payload/
/installer/bin/
/installer/obj/
*.msi
SloppySetup.exe
```

- [ ] **Step 2: Write `installer/SloppyApp.wxs`**

WiX v5 XML. Use `<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">`, a `<Package Name="Sloppy" Version="1.0.0" Manufacturer="Sloppy" Scope="perUser" Compressed="yes">` with `UpgradeCode="FFF8B254-0ECE-4F33-81D3-0EE661D9FACF"` fixed once for both MSIs and the bundle, `<MajorUpgrade>`, `<MediaTemplate EmbedCab="yes" />`, and a `TARGETDIR` tree:
- `LocalAppDataFolder/Programs/Sloppy` (`INSTALLFOLDER`) containing `scripts/` and `data/`
- `ProgramMenuFolder/Sloppy` for the Start menu shortcut

Include:
- a `Component` with every `src/*.ps1` file under `scripts/`, one `File` element per module;
- a `Component` with `<CreateFolder Directory="SloppyDataFolder" />` for `%LOCALAPPDATA%\Sloppy`;
- a Start menu `Shortcut` component whose KeyPath is an HKCU `RegistryValue` at `Software\Sloppy\StartMenu` (required for per-user ICE compliance);
- an autostart `Component` with a single HKCU `RegistryValue` at `Software\Microsoft\Windows\CurrentVersion\Run`, `Name="Sloppy"`, `Value="&quot;[ScriptsFolder]launch.cmd&quot;"`, `KeyPath="yes"`;
- `launch.cmd` invoking `pwsh -STA -NoProfile -File "%~dp0Slop.ps1"`.

Do not write any HKLM keys. Do not request elevation.

- [ ] **Step 3: Write `installer/SloppyPayload.wxs`**

Second per-user MSI. Install `runtime\llama-server.exe` plus its DLLs and `models\qwen3-4b-q4_k_m-00001-of-00002.gguf` / `-00002-of-00002.gguf` under `LocalAppDataFolder/Programs/Sloppy`. Because a single MSI CAB cannot safely exceed ~2 GB, declare multiple `<Media Id="1" Cabinet="payload1.cab" />` and `<Media Id="2" Cabinet="payload2.cab" />` and assign each large file to a distinct `Media` via `DiskId`. Keep every CAB below 2 GB; if the runtime plus one shard still exceeds that, split further with the bundled `llama-gguf-split.exe` and keep the `-0000N-of-0000M.gguf` naming llama.cpp expects. Attribution file `THIRD-PARTY-NOTICES.txt` is installed into `INSTALLFOLDER`.

- [ ] **Step 4: Write `installer/SloppyBundle.wxs`**

WiX v5 Burn `<Bundle Name="Sloppy" Version="1.0.0" Manufacturer="Sloppy" UpgradeCode="FFF8B254-0ECE-4F33-81D3-0EE661D9FACF">` with `<MsiPackage SourceFile="$(var.SloppyAppMsi)" />`, `<MsiPackage SourceFile="$(var.SloppyPayloadMsi)" />`, and `<Variable Name="InstallFolder" Type="string" Value="[LocalAppDataFolder]Programs\Sloppy" />` where needed. Set `<UX><BootstrapperApplicationRef Id="WixStandardBootstrapperApplication.RtfLicense" /></UX>` and point the license at the third-party notices. The output is one `.exe`. No silent reboot, no elevation.

- [ ] **Step 5: Write `installer/Build-Installer.ps1`**

Contract:
- Requires `wix` on PATH (`dotnet tool install --global wix` is documented in the script comment, not executed).
- Params: `[string]$PayloadRoot = './payload'`, `[string]$CertificateThumbprint = ''`, `[string]$Output = './bin/SloppySetup.exe'`.
- Fails with a clear message if `llama-server.exe` or either GGUF shard is missing from `$PayloadRoot`.
- Runs `wix build` for both MSIs with the required `-d` define switches, then the bundle.
- If `$CertificateThumbprint` is non-empty, runs `signtool sign /sha1 ... /fd SHA256` on the final `.exe` and fails on non-zero exit.
- Prints the output path and SHA256 hash. Never downloads anything, never pushes.

- [ ] **Step 6: Write `tools/bootstrap-sloppy.ps1`**

Contract:
- Param `[Parameter(Mandatory)][uri]$ReleaseBaseUrl`, optional `[switch]$Silent`.
- Resolves `$ReleaseBaseUrl` + `/SloppySetup.exe`, downloads with `Invoke-WebRequest -UseBasicParsing`, verifies the SHA256 against a sibling `SloppySetup.exe.sha256` file, then runs the installer with `/quiet /norestart` when `-Silent` is set.
- Rejects any non-HTTPS URL and any host that is not the configured release host once the user supplies it.
- Prints plain-language progress: downloading, verifying, installing, done.
- The release-time one-liner is documented in the README as `irm RELEASE_HOST/bootstrap-sloppy.ps1 | iex`, where the user substitutes their own release host at publish time; no fabricated URL is committed.

- [ ] **Step 7: Write `installer/THIRD-PARTY-NOTICES.txt`**

Include the Apache License 2.0 attribution for Qwen3 (Qwen team / Alibaba Cloud) and llama.cpp (ggml authors), the exact model file name, and a statement that model weights are distributed under Apache-2.0. Keep it plain text and PII-free.

---

## Task 7: Verification, live check, and release gate

**Files:**
- Modify (append-only): `tools/verify-motion.ps1`
- Create: `docs/superpowers/reports/2026-11-23-sloppy-companion-product-v1-verification.md`

- [ ] **Step 1: Extend the live verifier**

Append to `tools/verify-motion.ps1`, after the existing assertions, a new block that:
1. Launches the app with a temp `%LOCALAPPDATA%\Sloppy\` directory via a test-only override so real user config is never touched.
2. Asserts onboarding appears on first run: all four screens reachable, swatch click changes `PreviewPea.Fill`, preset selection changes `SampleLine.Text`, finishing writes `config.json` and `persona.md`.
3. Asserts the semantic status dot still uses `#3B82F6` idle after a non-blue identity swatch is chosen.
4. Asserts a real bundled-model reply: send a short greeting, confirm amber on the same frame as Send, confirm at least one token arrives, confirm green success, then Stop mid-stream on a second message and confirm the token count freezes.
5. Uses the existing `finally` teardown (process plus child wrapper) and DPI-once capture already in the script. Does not alter any existing assertion.

- [ ] **Step 2: Run all headless gates**

Run:
```powershell
pwsh -NoProfile -File ~/.agents/scripts/verify.ps1
```
Expected: exit code 0, `All gates passed.`, and the aggregate Pester count is the prior 441 plus the new suites (record the exact number).

Also run directly:
```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output Normal"
```
Expected: 0 failed.

- [ ] **Step 3: Run geometry and live checks**

Run:
```powershell
pwsh -NoProfile -File tools/verify-geometry.ps1
pwsh -NoProfile -File tools/verify-motion.ps1
```
Expected: both exit 0; geometry 18/18; live verifier reports onboarding, bundled reply, and Stop-cancel green, with no orphan `pwsh` process.

- [ ] **Step 4: Measure memory**

Run the bundled model with the exact launch arguments from `New-SlopLlamaArguments` and record peak working set while answering a 4k-context prompt:

```powershell
$p = Start-Process -FilePath $env:SLOP_SERVER_EXE -ArgumentList @('--model',$env:SLOP_MODEL,'--host','127.0.0.1','--port','18080','--ctx-size','4096','--cache-ram','0','--n-predict','512','--alias','sloppy') -PassThru
$p.WaitForExit()
$p.PeakWorkingSet64 / 1GB
```

Expected: peak RSS below 4.5 GB. Record the command, output, machine RAM, and CPU in the verification report. If it exceeds 4.5 GB, report the measured value and switch the default to the approved smaller model fallback rather than claiming success.

- [ ] **Step 5: Manual installer checks on a clean Windows VM**

These are user-owned because this environment has no clean VM and no signing certificate. Provide a checklist in the verification report for:
1. Double-click the signed `.exe`; no UAC prompt; install finishes.
2. Start menu entry launches Sloppy; onboarding appears.
3. Autostart toggle in tray survives a sign-out.
4. Tray Sleep model frees the model process; next message wakes it.
5. Uninstall removes both `Programs\Sloppy` and `%LOCALAPPDATA%\Sloppy`.
6. One-line bootstrap downloads the same `.exe` and hash matches.

Do not mark these complete until the user reports results.

- [ ] **Step 6: PII and history scrub**

Run a tracked-text scan for personal paths, the personal persona name, the handle, and credential-like strings. Expected: only the intentional `Copyright (c) 2026 shahr` attribution lines in `LICENSE` and the showcase plan remain. Also confirm no personal machine paths were introduced by this plan or the new modules.

Rebuild the history-free publish snapshot from the clean tracked set, excluding `.memory/`, `.git/`, and all untracked user-owned docs. Confirm `has_git=False`, no `.memory` directory, and no personal strings beyond the attribution.

**Do not push the current repository.** Six older commits still contain personal repository paths. The user creates the public repo, copies the snapshot files, and makes the first commit manually.

- [ ] **Step 7: Stage and hand off (no commit)**

Run:
```powershell
git add docs/superpowers/plans/2026-11-23-sloppy-companion-product-v1.md docs/superpowers/specs/2026-11-23-sloppy-companion-product-v1-design.md
git status --short
```

Expected: only the two product-design documents are newly staged; no commit is created. Proposed commit message for the user (do not execute):

```
docs(sloppy): add companion product v1 design and implementation plan
```

---

## Self-review checklist before implementation

- Every new module has a headless test suite; no test requires the real model or a network service.
- `Read-SlopSseStream` and `Resolve-SlopStreamToken` are reused, not reimplemented.
- The DispatcherTimer tick body, motion/frame/face modules, and existing live assertions are byte-identical.
- Config writes are atomic and back up the previous file.
- Semantic signal colors are never set from the identity palette.
- No personal absolute paths, credentials, or remote URLs are committed.
- No subagents, no commits, no push, no CI changes.
- All user-owned prerequisites are listed as blockers for Tasks 6–7, not silently assumed.

---
---

# Part B — Amendment 1: routes, surfaces, controlled harness, disclosure

**Authority:** user decision 2026-11-23 following the structured review. **Part B wins** wherever it conflicts with Tasks 1–7. Work proceeds in the reviewed order; automatic failover is explicitly not included.

## Supersession table

| Original location | Replacement in Part B |
| --- | --- |
| Task 2 Step 1, `Get-SlopStreamPlan`, `SLOP_ADAPTER` escape hatch (lines 287–304) | Task 8 replaces the function body with `Get-SlopRoutePlan`; the environment escape hatch is deleted. OpenCode becomes a first-class route in config. |
| Task 2 file list, `src/Slop.Adapter.OpenCode.ps1` comment "Developer-only" | First-class Tier 2 adapter; no behaviour change to its job body. |
| Task 4 Brain screen (spec line 78) | Task 10: local default, OpenCode opt-in, paid opt-in, disclosure gate, effective model shown. |
| Task 5 Step 1 dot-sources | Task 10 Step 1 adds `Slop.Route.ps1`, `Slop.OpenCodeProfile.ps1`, `Slop.Disclosure.ps1`, `Slop.Surfaces.ps1`. |
| `src/Slop.ps1:741–754` developer chip loop | Task 12 replaces it with four destination buttons; chips move to Settings → Advanced / developer. |
| Task 7 Step 1 verifier | Task 14 adds route badge, disclosure gate, controlled-config verification, and Stop side-effect checks. |
| Spec "CLI adapters: Not in v1" | Superseded by amended spec: OpenCode harness is a first-class opt-in route; no other CLI adapters. |

**Verified OpenCode facts used below (do not re-litigate):**
- Rules merge lower-priority → global → agent; **last match wins**. Default base policy contains `* → allow`; `external_directory` defaults to allow. A policy hard-deny runs after rules and saved approvals and never grants access. Saved approvals are durable project-scoped `allow` rules and never override a configured `deny`.
- `POST /api/session/{sessionID}/model` switches a session model; `GET /api/model` lists enabled models. `DELETE /api/session/{id}` removes the session **and its children** (`packages/core/src/session.ts:404–418`).
- Ollama, LM Studio, and vLLM have local discovery; custom OpenAI-compatible endpoints are supported through `providers`. OpenCode Go requires a Console subscription, API key, and `/connect` — not one-click.
- Retention differs per model (e.g. Beam Free 30 days, Gemini 4 Argon up to 55 days, several 0 days, some "Not ZDR"). No blanket retention claim is allowed.
- `GET /api/event` has no `sessionID` filter; direct HTTP routes may bypass tool permissions and this is **unverified** (`docs/security/opencode-route-review.md:62`).

---

## Task 8: Route semantics and always-visible badge

**Files:**
- Create: `src/Slop.Route.ps1`
- Create: `tests/slop-route-check.ps1`
- Modify: `src/Slop.Provider.ps1` (replace `Get-SlopStreamPlan` OpenCode branch)

- [ ] **Step 1: Write the failing route tests**

```powershell
#requires -Version 7.6
Describe 'Slop.Route' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Route.ps1')
    }
    It 'classifies the bundled default' {
        Resolve-SlopRouteKind -Config @{ brain = 'builtin' } | Should -Be 'local-bundled'
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
        (Get-SlopRouteCatalog)['local-bundled'].TermsRequired | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-route-check.ps1' -CI -Output Normal"
```
Expected: fail with "The term 'Resolve-SlopRouteKind' is not recognized".

- [ ] **Step 3: Write `src/Slop.Route.ps1`**

```powershell
# Route taxonomy and badge resolution. Headless: no WPF, no network, no registry.
$ErrorActionPreference = 'Stop'

function Get-SlopRouteCatalog {
    return @{
        'local-bundled'   = @{ Harness='bundled';  Locality='Local';  TermsRequired=$false }
        'opencode-local'  = @{ Harness='OpenCode'; Locality='Local';  TermsRequired=$false }
        'opencode-remote' = @{ Harness='OpenCode'; Locality='Remote'; TermsRequired=$true  }
        'opencode-paid'   = @{ Harness='OpenCode'; Locality='Remote'; TermsRequired=$true  }
    }
}

function Resolve-SlopRouteKind {
    param([Parameter(Mandatory)][hashtable]$Config)
    if ([string]$Config.brain -ne 'opencode') { return 'local-bundled' }
    if ([string]$Config.providerLocality -eq 'local') { return 'opencode-local' }
    if ([string]$Config.providerTier -eq 'paid') { return 'opencode-paid' }
    return 'opencode-remote'
}

function Resolve-SlopEffectiveModel {
    param(
        [Parameter(Mandatory)][hashtable]$Agent,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $preferred = [string]$Agent.model
    if (-not [string]::IsNullOrWhiteSpace($preferred)) { return $preferred }
    return [string]$Config.model
}

function Get-SlopRouteBadge {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$Model
    )
    $catalog = Get-SlopRouteCatalog
    if (-not $catalog.ContainsKey($Kind)) { throw "unknown route kind: $Kind" }
    $entry = $catalog[$Kind]
    return ('{0} · {1} · {2}' -f $entry.Locality, $Provider, $Model)
}

function Get-SlopRoutePlan {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserText,
        [string]$PersonaText = '',
        [Parameter(Mandatory)][string]$ScriptRootPath,
        [Parameter(Mandatory)][string]$RepoRootPath
    )
    $kind = Resolve-SlopRouteKind -Config $Config
    $catalog = Get-SlopRouteCatalog
    $agent = if ($Config.agent) { $Config.agent } else { @{} }
    $model = Resolve-SlopEffectiveModel -Agent $agent -Config $Config
    $provider = [string]$Config.provider

    if ($kind -ne 'local-bundled') {
        $profileResult = Test-SlopEffectivePermissions -GeneratedConfig (
            New-SlopControlledConfig -Profile ([string]$Config.capabilityProfile) -AgentId ([string]$Config.agentId) -Model $model
        ) -LiveRules @() -SavedGrants @() -EffectivePolicies @()
        if (-not $profileResult.Ok) {
            return @{ Ok=$false; Kind=$kind; Reason=$profileResult.Reasons -join '; ' }
        }
        $bridge = Join-Path $ScriptRootPath 'Slop.OpenCode.ps1'
        $lifecycle = Join-Path $ScriptRootPath 'Slop.Lifecycle.ps1'
        $baseUrl = if ($Config.openCodeBaseUrl) { [string]$Config.openCodeBaseUrl } else { 'http://127.0.0.1:28894' }
        return @{
            Ok=$true; Kind=$kind; StatusText='Using OpenCode'
            AdapterPath=(Join-Path $ScriptRootPath 'Slop.Adapter.OpenCode.ps1')
            AdapterArgs=@{
                BaseUrl=$baseUrl; PromptBody=(New-SlopPromptBody -Text $UserText)
                LifecyclePath=$lifecycle; BridgePath=$bridge
                Auth=(New-SlopOpenCodeAuthHeader -ServiceConfigPath $Config.serviceConfigPath)
                EventTypes=@(Get-SlopOpenCodeEventTypes); TimeoutSeconds=300
                SessionId=$Config.openCodeSessionId; Model=$model
            }
            Badge=(Get-SlopRouteBadge -Kind $kind -Provider $provider -Model $model)
            RouteKind=$kind
            RequiresDisclosure=[bool]$catalog[$kind].TermsRequired
            PermissionProfile=[string]$Config.capabilityProfile
        }
    }

    $body = New-SlopChatRequestBody -SystemPrompt $PersonaText -UserText $UserText
    $paths = Get-SlopRuntimePaths
    $pre = Test-SlopLocalModelPaths -Paths $paths
    if (-not $pre.Ok) { return @{ Ok=$false; Kind=$kind; Reason=$pre.Reason } }
    $start = Start-SlopLocalModel -Paths $paths
    if (-not $start.Ok) { return @{ Ok=$false; Kind=$kind; Reason=$start.Reason } }
    return @{
        Ok=$true; Kind='builtin'; StatusText='Waking up'; Process=$start.Process
        AdapterPath=(Join-Path $ScriptRootPath 'Slop.Adapter.OpenAi.ps1')
        AdapterArgs=@{
            BaseUrl=("http://127.0.0.1:$($paths.Port)")
            RequestBody=$body; LifecyclePath=$lifecyclePath; TimeoutSeconds=300
        }
        Badge=(Get-SlopRouteBadge -Kind 'local-bundled' -Provider 'bundled' -Model 'Qwen3 4B Q4_K_M')
        RouteKind='local-bundled'; RequiresDisclosure=$false; PermissionProfile='companion'
    }
}
```

Fix the built-in branch before running: define `$lifecyclePath = Join-Path $ScriptRootPath 'Slop.Lifecycle.ps1'` immediately before `$body = New-SlopChatRequestBody ...`, then use `$lifecyclePath` as shown. This is a required part of Step 3, not an optional cleanup.

- [ ] **Step 4: Replace `Get-SlopStreamPlan` in `src/Slop.Provider.ps1`**

Delete lines 287–304 (the `SLOP_ADAPTER` block) and replace the whole function with this two-line delegation:

```powershell
function Get-SlopStreamPlan {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserText,
        [string]$PersonaText = '',
        [Parameter(Mandatory)][string]$ScriptRootPath,
        [Parameter(Mandatory)][string]$RepoRootPath
    )
    . (Join-Path $PSScriptRoot 'Slop.Route.ps1')
    return Get-SlopRoutePlan -Config $Config -UserText $UserText -PersonaText $PersonaText `
        -ScriptRootPath $ScriptRootPath -RepoRootPath $RepoRootPath
}
```

- [ ] **Step 5: Run the route test to verify it passes**

Same command as Step 2. Expected: 9 passed, 0 failed.

- [ ] **Step 6: Stage (no commit)**

```powershell
git add src/Slop.Route.ps1 tests/slop-route-check.ps1 src/Slop.Provider.ps1
```

---

## Task 9: Controlled OpenCode configuration and effective-permission verification

**Files:**
- Create: `src/Slop.OpenCodeProfile.ps1`
- Create: `tests/slop-opencode-profile-check.ps1`

- [ ] **Step 1: Write the failing profile tests**

```powershell
#requires -Version 7.6
Describe 'Slop.OpenCodeProfile' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeProfile.ps1')
    }
    It 'generates a deny-first companion profile' {
        $cfg = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        $cfg.permissions[0].effect | Should -Be 'deny'
        $cfg.agents.sloppy.permissions | Should -Not -BeNullOrEmpty
    }
    It 'includes hard-deny policies' {
        $cfg = New-SlopControlledConfig -Profile 'power' -AgentId 'sloppy' -Model 'beam-free'
        # @(...) is required: a lone hashtable's .Count is its key count, not 1.
        @($cfg.policies | Where-Object { $_.action -eq 'tool.use' -and $_.effect -eq 'deny' }).Count |
            Should -BeGreaterThan 0
        $json = $cfg | ConvertTo-Json -Depth 8 -Compress
        $json | Should -Match '169\.254\.169\.254'
        $json | Should -Match 'service\.json'
    }
    It 'fails closed when a broad allow survives in live rules' {
        $generated = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        $live = @(@{ action='*'; resource='*'; effect='allow' })
        $result = Test-SlopEffectivePermissions -GeneratedConfig $generated -LiveRules $live -SavedGrants @() -EffectivePolicies @()
        $result.Ok | Should -BeFalse
        $result.Reasons -join ' ' | Should -Match 'broad allow'
    }
    It 'fails closed on a saved edit-all grant' {
        $generated = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        $grants = @(@{ action='edit'; resource='*'; effect='allow' })
        $result = Test-SlopEffectivePermissions -GeneratedConfig $generated -LiveRules @() -SavedGrants $grants -EffectivePolicies @()
        $result.Ok | Should -BeFalse
        $result.Reasons -join ' ' | Should -Match 'saved grant'
    }
    It 'fails closed when hard-deny policies are missing' {
        $generated = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        $generated.policies = @()
        $result = Test-SlopEffectivePermissions -GeneratedConfig $generated -LiveRules @() -SavedGrants @() -EffectivePolicies @()
        $result.Ok | Should -BeFalse
        $result.Reasons -join ' ' | Should -Match 'hard-deny'
    }
    It 'gives Workspace only the chosen read-only folders' {
        $cfg = New-SlopControlledConfig -Profile 'workspace' -AgentId 'sloppy' -Model 'beam-free' -WorkspaceFolders @('D:/notes/*')
        @($cfg.permissions | Where-Object { $_.action -eq 'external_directory' -and $_.resource -eq 'D:/notes/*' }).Count |
            Should -Be 1
        @($cfg.permissions | Where-Object { $_.action -eq 'shell' -and $_.effect -eq 'allow' }).Count |
            Should -Be 0
    }
    It 'never proposes an Allow always grant' {
        (Get-SlopProfileApprovalModes) -join ',' | Should -Be 'once,reject'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-opencode-profile-check.ps1' -CI -Output Normal"
```
Expected: fail with "The term 'New-SlopControlledConfig' is not recognized".

- [ ] **Step 3: Write `src/Slop.OpenCodeProfile.ps1`**

```powershell
# Controlled OpenCode config generation and fail-closed verification. Headless.
$ErrorActionPreference = 'Stop'

function Get-SlopProfileApprovalModes { return @('once','reject') }

function New-SlopPermissionProfile {
    param(
        [Parameter(Mandatory)][ValidateSet('companion','workspace','power')][string]$Name,
        [string[]]$WorkspaceFolders = @()
    )
    $denyAll = @{ action='*'; resource='*'; effect='deny' }
    $secretDenies = @(
        @{ action='read';  resource='**/service.json'; effect='deny' },
        @{ action='read';  resource='**/.env*';       effect='deny' },
        @{ action='read';  resource='**/.ssh/*';      effect='deny' },
        @{ action='read';  resource='**/.aws/*';      effect='deny' },
        @{ action='read';  resource='**/.config/gcloud/*'; effect='deny' },
        @{ action='webfetch'; resource='file://*';    effect='deny' },
        @{ action='webfetch'; resource='http://127.0.0.1/*'; effect='deny' },
        @{ action='webfetch'; resource='http://localhost/*'; effect='deny' },
        @{ action='webfetch'; resource='http://169.254.169.254/*'; effect='deny' }  # cloud metadata
    )
    switch ($Name) {
        'companion' {
            return @{ Permissions=@($denyAll) + $secretDenies; Policies=@(
                @{ action='tool.use'; resource='shell:*'; effect='deny' }
            ) }
        }
        'workspace' {
            $allows = @()
            foreach ($folder in $WorkspaceFolders) {
                $allows += @{ action='external_directory'; resource=$folder; effect='allow' }
                $allows += @{ action='read'; resource=$folder; effect='allow' }
                $allows += @{ action='glob'; resource=$folder; effect='allow' }
                $allows += @{ action='grep'; resource=$folder; effect='allow' }
            }
            return @{ Permissions=@($denyAll) + $secretDenies + $allows; Policies=@(
                @{ action='tool.use'; resource='shell:*'; effect='deny' }
            ) }
        }
        'power' {
            return @{ Permissions=@($denyAll) + $secretDenies + @(
                @{ action='shell'; resource='git status *'; effect='allow' }
            ); Policies=@(
                @{ action='tool.use'; resource='shell:sudo *'; effect='deny' },
                @{ action='tool.use'; resource='shell:rm -rf *'; effect='deny' }
            ) }
        }
    }
}

function New-SlopControlledConfig {
    param(
        [Parameter(Mandatory)][ValidateSet('companion','workspace','power')][string]$Profile,
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter(Mandatory)][string]$Model,
        [string[]]$WorkspaceFolders = @()
    )
    $profileRules = New-SlopPermissionProfile -Name $Profile -WorkspaceFolders $WorkspaceFolders
    return @{
        '$schema'   = 'https://opencode.ai/config.json'
        model       = $Model
        permissions = @($profileRules.Permissions)
        policies    = @($profileRules.Policies)
        agents      = @{
            $AgentId = @{
                description = 'Sloppy companion agent. Capabilities come from the selected profile.'
                system      = 'You are a warm desktop companion. Be concise and honest about what you can do.'
                permissions = @($profileRules.Permissions)
            }
        }
    }
}

function Test-SlopEffectivePermissions {
    param(
        [Parameter(Mandatory)][hashtable]$GeneratedConfig,
        [object[]]$LiveRules = @(),
        [object[]]$SavedGrants = @(),
        [object[]]$EffectivePolicies = @()
    )
    $reasons = [Collections.Generic.List[string]]::new()
    $denies = @($GeneratedConfig.policies | Where-Object { $_.effect -eq 'deny' })
    if ($denies.Count -eq 0) { $reasons.Add('hard-deny policies are missing') }

    foreach ($rule in @($LiveRules) + @($SavedGrants)) {
        if ($rule.action -eq '*' -and $rule.resource -eq '*' -and $rule.effect -eq 'allow') {
            $reasons.Add('broad allow survives in effective rules')
        }
        if ($rule.action -eq 'external_directory' -and $rule.resource -eq '*' -and $rule.effect -eq 'allow') {
            $reasons.Add('broad external_directory allow survives')
        }
        if ($rule.action -eq 'edit' -and $rule.resource -eq '*' -and $rule.effect -eq 'allow') {
            $reasons.Add('saved grant allows edit everywhere')
        }
    }
    if (@($EffectivePolicies | Where-Object { $_.action -eq 'tool.use' -and $_.effect -eq 'deny' }).Count -eq 0 -and $denies.Count -eq 0) {
        $reasons.Add('no effective hard-deny policy')
    }
    return @{ Ok=($reasons.Count -eq 0); Reasons=$reasons.ToArray() }
}
```

- [ ] **Step 4: Verify the generated JSON is accepted by the pinned OpenCode version**

```powershell
$cfg = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
$json = $cfg | ConvertTo-Json -Depth 8
$null = $json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'generated config is not valid JSON' }
```
Expected: no throw. Then, against a disposable OpenCode instance only, `opencode api get /api/config` with the controlled config injected; expected HTTP 200. Do not apply this to the user's shared service.

- [ ] **Step 5: Run the profile test to verify it passes**

Same command as Step 2. Expected: 7 passed, 0 failed.

- [ ] **Step 6: Stage (no commit)**

```powershell
git add src/Slop.OpenCodeProfile.ps1 tests/slop-opencode-profile-check.ps1
```

---

## Task 10: Brain picker, route badge, and disclosure gate

**Files:**
- Modify: `src/Slop.Onboarding.ps1` (Brain screen)
- Modify: `src/Slop.ps1` (badge element, dot-sources, preflight)

- [ ] **Step 1: Add dot-sources in `src/Slop.ps1`**

Append after the Task 5 Step 1 block:

```powershell
. (Join-Path $PSScriptRoot 'Slop.Route.ps1')
. (Join-Path $PSScriptRoot 'Slop.OpenCodeProfile.ps1')
. (Join-Path $PSScriptRoot 'Slop.Disclosure.ps1')
. (Join-Path $PSScriptRoot 'Slop.Surfaces.ps1')
# Disclosure acceptance is per app lifetime; initialize before the first remote send.
$script:SlopDisclosureAccepted = $false
```

- [ ] **Step 2: Add the always-visible header badge**

Insert directly before `<WrapPanel x:Name="ShortcutsStrip" ...>` (currently line 108):

```xml
<TextBlock x:Name="RouteBadge" Grid.Row="0" HorizontalAlignment="Right"
           Margin="0,6,10,2" FontSize="9" Foreground="#B8B8C0"
           Text="Local · bundled · Qwen3 4B Q4_K_M"
           AutomationProperties.Name="Active route"/>
```

Add this function next to `Add-SlopThoughtBubble` in `src/Slop.ps1`:

```powershell
function Set-SlopRouteBadge {
    param([Parameter(Mandatory)][hashtable]$StreamPlan)
    if (-not $StreamPlan.Badge) { return }
    $RouteBadge.Text = $StreamPlan.Badge
    $RouteBadge.ToolTip = if ($StreamPlan.RequiresDisclosure) {
        'This route sends data to a remote model provider. Open Privacy for the exact path.'
    } else {
        'Model requests stay on this PC.'
    }
}
```

- [ ] **Step 3: Replace the Brain screen**

In `src/Slop.Onboarding.ps1`, replace screen 4 with these three radio options and their labels; the fourth value is written to `config.json`:

```
( ) Built-in — works offline (recommended)          → brain='builtin'
( ) OpenCode — use a local provider                 → brain='opencode', providerLocality='local'
( ) OpenCode — use a remote provider                → brain='opencode', providerLocality='remote'
      [Provider] [Model] [Agent] [Capability profile]
      Effective model: <resolved by Resolve-SlopEffectiveModel>
      [Read the data route and provider terms]  → opens Privacy before continuing
```

Persist `brain`, `providerLocality`, `provider`, `model`, `agentId`, `agent`, `capabilityProfile`, `openCodeBaseUrl`, `serviceConfigPath`. Never persist a provider credential. A paid-provider option is added in Task 13.

- [ ] **Step 4: Gate the first remote message**

In Task 5 Step 4 (Start-Stream preflight), insert immediately after `$streamPlan` is returned and before the status line:

```powershell
    Set-SlopRouteBadge -StreamPlan $streamPlan
    if ($streamPlan.RequiresDisclosure -and -not $script:SlopDisclosureAccepted) {
        $accepted = Show-SlopDisclosure -Route @{
            Kind=$streamPlan.RouteKind; Provider=$script:SlopConfigResult.Config.provider
            Model=$script:SlopConfigResult.Config.model
        }
        if (-not $accepted) { return }
        $script:SlopDisclosureAccepted = $true
    }
```

Expected: no remote route can send a message before `Show-SlopDisclosure` returns true; the badge is set even if the user cancels.

- [ ] **Step 5: Test the wiring**

Append to `tools/verify-motion.ps1` (after existing assertions, before teardown):

```powershell
# Route badge and disclosure gate
Assert-Equal $RouteBadge.Text 'Local · bundled · Qwen3 4B Q4_K_M' 'badge shows bundled route'
$cfg.LocalAppData = $env:SLOP_TEST_APPDATA
Set-SlopRouteBadge -StreamPlan @{ Badge='Remote · OpenCode Go · Beam Free'; RequiresDisclosure=$true }
Assert-Equal $RouteBadge.Text 'Remote · OpenCode Go · Beam Free' 'badge follows effective route'
Assert-Equal $script:SlopDisclosureAccepted $false 'remote route is gated before disclosure'
```
Expected: exit 0 with no orphan process; the existing teardown block still runs.

- [ ] **Step 6: Stage (no commit)**

```powershell
git add src/Slop.Onboarding.ps1 src/Slop.ps1 tools/verify-motion.ps1
```

---

## Task 11: Provider-specific disclosure and Privacy destination

**Files:**
- Create: `src/Slop.Disclosure.ps1`
- Create: `tests/slop-disclosure-check.ps1`

- [ ] **Step 1: Write the failing disclosure tests**

```powershell
#requires -Version 7.6
Describe 'Slop.Disclosure' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Disclosure.ps1')
    }
    It 'states the exact local path for bundled inference' {
        $text = New-SlopDisclosureText -Route @{ Kind='local-bundled'; Provider='bundled'; Model='Qwen3 4B Q4_K_M' }
        $text | Should -Match 'llama-server'
        $text | Should -Match 'nothing leaves this PC'
    }
    It 'separates harness from model provider on a remote route' {
        $text = New-SlopDisclosureText -Route @{ Kind='opencode-remote'; Provider='OpenCode Go'; Model='Beam Free' } -TermsUrl 'https://opencode.ai/docs/console/go/#privacy'
        $text | Should -Match 'OpenCode on this PC'
        $text | Should -Match 'selected model provider'
        $text | Should -Match 'https://opencode.ai/docs/console/go/#privacy'
    }
    It 'never prints a blanket retention period' {
        $text = New-SlopDisclosureText -Route @{ Kind='opencode-remote'; Provider='Unknown'; Model='x' }
        $text | Should -Not -Match '30 days'
        $text | Should -Not -Match 'free forever'
        $text | Should -Match 'verified'
    }
    It 'distinguishes clear conversation from session deletion' {
        (Get-SlopDeletionCopy -Action 'conversation') | Should -Match 'Sloppy transcript'
        (Get-SlopDeletionCopy -Action 'session') | Should -Match 'child sessions'
        (Get-SlopDeletionCopy -Action 'session') | Should -Match 'does not mean the provider deleted'
        (Get-SlopDeletionCopy -Action 'local-data') | Should -Match 'config.json and persona.md'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-disclosure-check.ps1' -CI -Output Normal"
```
Expected: fail with "The term 'New-SlopDisclosureText' is not recognized".

- [ ] **Step 3: Write `src/Slop.Disclosure.ps1`**

```powershell
# Provider-specific disclosure. Headless; no WPF, no network.
$ErrorActionPreference = 'Stop'

function New-SlopDisclosureText {
    param(
        [Parameter(Mandatory)][hashtable]$Route,
        [string]$TermsUrl = ''
    )
    $kind = [string]$Route.Kind
    $provider = [string]$Route.Provider
    $model = [string]$Route.Model

    if ($kind -eq 'local-bundled') {
        return @"
Route: Local · bundled · $model
Sloppy sends your message to its bundled llama-server on this PC. No OpenCode service, account, or network is involved. For the model request, nothing leaves this PC.
"@
    }
    if ($kind -eq 'opencode-local') {
        return @"
Route: Local · $provider · $model
Sloppy sends your message to OpenCode on this PC. OpenCode sends the prompt, selected agent instructions, and allowed context to the local provider $provider. The model request stays on this PC. Tools you enable can still reach other services; that is shown separately in Brain.
"@
    }
    $verified = -not [string]::IsNullOrWhiteSpace($TermsUrl)
    $termsLine = if ($verified) { "Verified terms and privacy information: $TermsUrl" } else { 'No verified terms link is available for this provider/model yet. Treat retention and training terms as unknown.' }
    return @"
Route: Remote · $provider · $model
Sloppy draws the pea and holds the conversation. Your message goes first to OpenCode on this PC. OpenCode, an open-source (MIT) harness, then sends your message, the selected agent's instructions, and any files or tool results you allow to the selected model provider. That provider's policies and data regulations apply to that hop, not Sloppy's.
$termsLine
Retention and training terms differ by provider and model and can change. We do not claim any model is permanently free.
"@
}

function Get-SlopDeletionCopy {
    param([Parameter(Mandatory)][ValidateSet('conversation','session','local-data')][string]$Action)
    switch ($Action) {
        'conversation' { return 'Clear conversation removes the Sloppy transcript only. The OpenCode session and its stored messages remain.' }
        'session'      { return 'Delete OpenCode session removes that session and its child sessions from OpenCode''s local store. It does not mean the provider deleted its copy of a prompt or transcript.' }
        'local-data'   { return 'Clear Sloppy local data removes config.json and persona.md from %LOCALAPPDATA%\Sloppy. It does not delete OpenCode sessions or provider data.' }
    }
}
```

- [ ] **Step 4: Add the Privacy panel and the disclosure gate function**

In `src/Slop.ps1`, add a `PrivacyPanel` with a `TextBlock x:Name="PrivacyRouteText"`, a `TextBlock x:Name="PrivacyTermsLink"` (initially collapsed), and three read-only `TextBlock`s named `PrivacyConversationCopy`, `PrivacySessionCopy`, and `PrivacyLocalDataCopy`. That panel is the read-only view behind the **Privacy** destination. Fill it from `New-SlopDisclosureText` and `Get-SlopDeletionCopy`; render no provider terms URL unless a verified link was supplied.

The consent gate is a **separate modal window** constructed in code (matching the existing `Show-SlopOnboarding` pattern). `ShowDialog()` blocks until the user clicks an explicit button, so there is no dispatcher spin loop and no way to send before a decision:

```powershell
function Show-SlopDisclosure {
    param([Parameter(Mandatory)][hashtable]$Route, [string]$TermsUrl = '')
    # Click handlers cannot close over function locals in PowerShell - publish to script scope.
    $script:SlopDisclosureDialog = [System.Windows.Window]::new()
    $dlg = $script:SlopDisclosureDialog
    $dlg.Title = 'Where your message goes'
    $dlg.Owner = $window
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.SizeToContent = 'WidthAndHeight'
    $dlg.MinWidth = 480
    $dlg.MaxWidth = 640
    $dlg.Padding = [System.Windows.Thickness]::new(18)
    $stack = [System.Windows.Controls.StackPanel]::new()
    $body = [System.Windows.Controls.TextBlock]::new()
    $body.Text = New-SlopDisclosureText -Route $Route -TermsUrl $TermsUrl
    $body.TextWrapping = 'Wrap'
    $body.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    $stack.Children.Add($body) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($TermsUrl)) {
        $link = [System.Windows.Controls.TextBlock]::new()
        $link.Text = $TermsUrl
        $link.TextWrapping = 'Wrap'
        $link.Foreground = [System.Windows.Media.Brushes]::CornflowerBlue
        $link.Margin = [System.Windows.Thickness]::new(0,0,0,12)
        $stack.Children.Add($link) | Out-Null
    }
    $buttons = [System.Windows.Controls.StackPanel]::new()
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $continueBtn = [System.Windows.Controls.Button]::new()
    $continueBtn.Content = 'Continue'
    $continueBtn.MinWidth = 90
    $continueBtn.Margin = [System.Windows.Thickness]::new(0,0,8,0)
    $continueBtn.Add_Click({ $script:SlopDisclosureDialog.DialogResult = $true })
    $cancelBtn = [System.Windows.Controls.Button]::new()
    $cancelBtn.Content = 'Cancel'
    $cancelBtn.MinWidth = 90
    $cancelBtn.Add_Click({ $script:SlopDisclosureDialog.DialogResult = $false })
    $buttons.Children.Add($cancelBtn) | Out-Null
    $buttons.Children.Add($continueBtn) | Out-Null
    $stack.Children.Add($buttons) | Out-Null
    $dlg.Content = $stack
    return [bool]$dlg.ShowDialog()
}
```

No `Allow always` option exists in this dialog. Closing it via the window chrome leaves `DialogResult` null, which `[bool]` coerces to `$false` — a cancel, not consent.

- [ ] **Step 5: Run the disclosure test to verify it passes**

Same command as Step 2. Expected: 4 passed, 0 failed.

- [ ] **Step 6: Stage (no commit)**

```powershell
git add src/Slop.Disclosure.ps1 tests/slop-disclosure-check.ps1 src/Slop.ps1
```

---

## Task 12: Four destinations, developer chips, and deletion scopes

**Files:**
- Create: `src/Slop.Surfaces.ps1`
- Create: `tests/slop-surfaces-check.ps1`
- Modify: `src/Slop.ps1:741–754`

- [ ] **Step 1: Write the failing surface tests**

```powershell
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
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-surfaces-check.ps1' -CI -Output Normal"
```
Expected: fail with "The term 'Get-SlopDestinationMap' is not recognized".

- [ ] **Step 3: Write `src/Slop.Surfaces.ps1`**

```powershell
# Headless guards for the four destinations and deletion scopes. No WPF.
$ErrorActionPreference = 'Stop'

function Get-SlopDestinationMap {
    return @{
        Settings  = @('Startup behaviour','Data location','Reset / delete conversation','Clear Sloppy data','About and version','Advanced / developer')
        Customize = @('Name','Colours','Personality','Persona text')
        Brain     = @('Local vs remote','Provider','Model','Agent','Capability profile','Effective model')
        Privacy   = @('Active data route','Provider terms','Deletion scopes')
    }
}

function Test-SlopSurfaceSeparation {
    param([Parameter(Mandatory)][string]$Destination,[Parameter(Mandatory)][hashtable]$Payload)
    if ($Destination -eq 'Customize' -and $Payload.ContainsKey('permissions') -and @($Payload.permissions).Count -gt 0) {
        return @{ Ok=$false; Reason='Customize must never carry security permissions' }
    }
    return @{ Ok=$true; Reason=$null }
}

function Get-SlopDeletionScope {
    param([Parameter(Mandatory)][ValidateSet('conversation','session','local-data')][string]$Action)
    switch ($Action) {
        'conversation' { return @{ Scope='Sloppy transcript'; Copy=(Get-SlopDeletionCopy -Action 'conversation') } }
        'session'      { return @{ Scope='OpenCode session plus children'; Copy=(Get-SlopDeletionCopy -Action 'session') } }
        'local-data'   { return @{ Scope='%LOCALAPPDATA%\Sloppy config and persona'; Copy=(Get-SlopDeletionCopy -Action 'local-data') } }
    }
}
```

- [ ] **Step 4: Replace the developer chip loop in `src/Slop.ps1:741–754`**

Delete the `$script:ShortcutCommands` loop and replace it with four buttons plus an advanced stack:

```powershell
$script:SlopDestinations = @('Settings','Customize','Brain','Privacy')
foreach ($name in $script:SlopDestinations) {
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $name
    $btn.Style = $window.Resources['SlopButton']
    $btn.FontSize = 9
    $btn.Margin = [System.Windows.Thickness]::new(0,0,5,4)
    $btn.Tag = $name
    $btn.Add_Click({ param($s,$e) Show-SlopDestination -Name $s.Tag })
    $ShortcutsStrip.Children.Add($btn) | Out-Null
}

function Show-SlopDestination {
    param([Parameter(Mandatory)][string]$Name)
    $map = Get-SlopDestinationMap
    if (-not $map.ContainsKey($Name)) { throw "unknown destination: $Name" }
    foreach ($other in $map.Keys) {
        $panel = $window.FindName(($other + 'Panel'))
        if ($null -ne $panel) { $panel.Visibility = 'Collapsed' }
    }
    $panel = $window.FindName(($Name + 'Panel'))
    if ($null -ne $panel) { $panel.Visibility = 'Visible' }
}
```

Add `SettingsPanel`, `CustomizePanel`, `BrainPanel`, and `PrivacyPanel` as collapsed `StackPanel`s in the expanded grid, each containing only the items listed by `Get-SlopDestinationMap`. Under `SettingsPanel`, add an `AdvancedStack` with the seven legacy chips (`startslop`, `stopslop`, `slopstatus`, `verify`, `review`, `kickoff`, `sign out`) using the deleted loop's `Insert-SlopShortcut` behaviour.

- [ ] **Step 5: Wire the three deletion actions**

In `SettingsPanel`, add three buttons calling this function; each must show `Get-SlopDeletionScope -Action <action>` copy and require an explicit confirm before acting:

```powershell
function Show-SlopConfirm {
    param([Parameter(Mandatory)][string]$Text)
    $result = [System.Windows.MessageBox]::Show(
        $Text, 'Confirm deletion', 'YesNo', 'Warning', 'NoButton')
    return ($result -eq 'Yes')
}

function Remove-SlopOpenCodeSession {
    param([Parameter(Mandatory)][string]$SessionId)
    $auth = New-SlopOpenCodeAuthHeader
    $escaped = [uri]::EscapeDataString($SessionId)
    $url = "$($script:OpenCodeBaseUrl)/api/session/$escaped"
    $client = [System.Net.Http.HttpClient]::new()
    try {
        $req = [Net.Http.HttpRequestMessage]::new('DELETE', $url)
        foreach ($h in $auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) {
            Add-Bubble -Text "[error: could not delete OpenCode session: $($resp.StatusCode)]" -IsUser $false
            return $false
        }
        $script:OpenCodeSessionId = $null
        Add-Bubble -Text 'OpenCode session and its child sessions deleted. Any copy held by a model provider is not affected.' -IsUser $false
        return $true
    } catch {
        Add-Bubble -Text "[error: could not delete OpenCode session: $($_.Exception.Message)]" -IsUser $false
        return $false
    } finally {
        if ($client) { $client.Dispose() }
    }
}

function Remove-SlopLocalData {
    $dir = Join-Path $env:LOCALAPPDATA 'Sloppy'
    foreach ($name in @('config.json','persona.md')) {
        $path = Join-Path $dir $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    # Signature is Show-SlopOnboarding -Config <hashtable> -StartScreen 1..4 (Task 4 contract).
    Show-SlopOnboarding -Config @{} -StartScreen 1 | Out-Null
}

function Invoke-SlopDeletion {
    param([Parameter(Mandatory)][ValidateSet('conversation','session','local-data')][string]$Action)
    $scope = Get-SlopDeletionScope -Action $Action
    if (-not (Show-SlopConfirm -Text $scope.Copy)) { return }
    switch ($Action) {
        'conversation' { $ChatStack.Children.Clear() }
        'session'      { if ($script:OpenCodeSessionId) { Remove-SlopOpenCodeSession -SessionId $script:OpenCodeSessionId } }
        'local-data'   { Remove-SlopLocalData }
    }
}
```

Variable names match the shipped app: the transcript is `$ChatStack.Children` and the session id is `$script:OpenCodeSessionId` (`src/Slop.ps1:110`, `src/Slop.ps1:380`). `Delete /api/session/{id}` removes the session and its children; the confirmation copy explicitly says a model provider's copy is not addressed. The existing window-close handler at `src/Slop.ps1:1300-1322` already deletes the active session on exit — keep it, and make it a no-op when the id was cleared here.

- [ ] **Step 6: Run the surface test and the live chip check**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-surfaces-check.ps1' -CI -Output Normal"
```
Expected: 4 passed, 0 failed. Live verifier must report four destination buttons and no chips outside Settings → Advanced / developer.

- [ ] **Step 7: Stage (no commit)**

```powershell
git add src/Slop.Surfaces.ps1 tests/slop-surfaces-check.ps1 src/Slop.ps1
```

---

## Task 13: Optional paid provider (Tier 3)

**Files:**
- Modify: `src/Slop.Route.ps1` (catalog entry already present — no code change)
- Modify: `src/Slop.Onboarding.ps1` (Brain screen)
- Modify: `docs/superpowers/specs/2026-11-23-sloppy-companion-product-v1-design.md` (prerequisite list only)

- [ ] **Step 1: Add the option without storing credentials**

Add to the Brain screen, below the remote-provider option:

```
[ ] Add a paid provider — account, billing, and API key are handled in OpenCode
    Sloppy stores no credential. See <verified provider terms link>.
```

When checked, set `providerTier='paid'` and show the disclosure with `TermsUrl` from the verified terms table. Do not add a key field, a token field, or a password field anywhere in Sloppy.

- [ ] **Step 2: Verify with a headless assertion**

Append to `tests/slop-route-check.ps1`:

```powershell
It 'never persists a credential in config' {
    # This suite dot-sources only Slop.Route.ps1; load the profile module here too.
    . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeProfile.ps1')
    $cfg = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
    ($cfg | ConvertTo-Json -Depth 8 -Compress) | Should -Not -Match 'apiKey|password|token|secret'
}
```
Expected: 10 passed, 0 failed for the route suite.

- [ ] **Step 3: Document the user-owned step**

In the spec's Open prerequisites, keep: user creates the paid provider account and connects it via OpenCode's own `/connect` flow; Sloppy only selects the resulting provider/model. Do not describe this as one-click sign-in.

- [ ] **Step 4: Stage (no commit)**

```powershell
git add src/Slop.Onboarding.ps1 tests/slop-route-check.ps1 docs/superpowers/specs/2026-11-23-sloppy-companion-product-v1-design.md
```

---

## Task 14: Verification additions and deferred register

**Files:**
- Modify: `tools/verify-motion.ps1` (append-only)
- Create: `docs/superpowers/reports/2026-11-23-sloppy-companion-product-v1-verification.md`

- [ ] **Step 1: Add the aggregate test registration**

Append to `tests/Slop.Tests.ps1` inside the existing aggregator:

```powershell
. (Join-Path $PSScriptRoot 'slop-route-check.ps1')
. (Join-Path $PSScriptRoot 'slop-opencode-profile-check.ps1')
. (Join-Path $PSScriptRoot 'slop-disclosure-check.ps1')
. (Join-Path $PSScriptRoot 'slop-surfaces-check.ps1')
```

- [ ] **Step 2: Extend the live verifier with route checks**

Append after the Task 10 additions:

1. Switch Brain to an OpenCode local-provider route and assert the badge reads `Local · Ollama · <model>` and that no disclosure gate blocks the message.
2. Switch to a remote route and assert the disclosure appears before Send, the terms link matches the verified URL, and Cancel leaves the badge remote but sends nothing.
3. Assert the four destinations open and close independently, and that `startslop` etc. appear only under Settings → Advanced / developer.
4. Assert the three deletion confirmations show distinct scope text.
5. Keep the existing guaranteed `finally` teardown and DPI-once capture; no orphan process.

- [ ] **Step 3: Live-test Stop as a side-effect control**

With a disposable local shell-capable job, send a long-running command, invoke Stop, and record: token count freezes, job/PTY/subagent status from `/api/experimental/job`, `/api/shell`, and PTY routes. Report the result. If a job survives, document Stop as "stops the reply, not necessarily the action" and keep it out of the security-control list. Do not claim success without command output.

- [ ] **Step 4: Run all gates**

```powershell
pwsh -NoProfile -File ~/.agents/scripts/verify.ps1
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output Normal"
pwsh -NoProfile -File tools/verify-geometry.ps1
pwsh -NoProfile -File tools/verify-motion.ps1
```
Expected: verify exits 0 with `All gates passed.`; Pester 0 failed; geometry 18/18; live verifier exit 0. Record exact counts in the verification report.

- [ ] **Step 5: Record the deferred register**

In the verification report, list explicitly, with reasons:

| Deferred | Reason |
| --- | --- |
| Automatic brain failover | A model switch changes behaviour and privacy; retries can repeat uncertain tool actions. Requires tool-cancellation and duplicate-effect behaviour to be understood first. |
| "One-click" paid sign-in | OpenCode Go currently needs a Console subscription, API key, and `/connect`. Treat as an integration goal to verify. |
| Universal OpenCode version support | Task 15 pins 2.3.2 and gates the exact API surface instead. OpenCode auto-updates, so universal support needs continuous compatibility testing we are not committing to. |
| Distilling the developer `.agents` tree | Personal paths and machine-specific MCP servers must be audited, stripped, and split before it can ship as a template. |

- [ ] **Step 6: Stage (no commit)**

```powershell
git add tests/Slop.Tests.ps1 tools/verify-motion.ps1 docs/superpowers/reports/2026-11-23-sloppy-companion-product-v1-verification.md
```

---

## Task 15: OpenCode version pin and API-surface compatibility gate

**Files:**
- Create: `src/Slop.OpenCodeCompat.ps1`
- Create: `tests/slop-opencode-compat-check.ps1`
- Modify: `tests/Slop.Tests.ps1` (add to the aggregator from Task 14 Step 1)

- [ ] **Step 1: Write the failing compatibility tests**

```powershell
#requires -Version 7.6
Describe 'Slop.OpenCodeCompat' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeCompat.ps1')
    }
    It 'pins the supported OpenCode version' {
        (Get-SlopOpenCodeCompatContract).PinnedVersion | Should -Be '2.3.2'
    }
    It 'declares every route the Tier 2 bridge actually calls' {
        $paths = (Get-SlopOpenCodeCompatContract).RequiredRoutes | ForEach-Object { $_.Method + ' ' + $_.Path }
        $paths | Should -Contain 'POST /api/session/{id}/model'
        $paths | Should -Contain 'POST /api/session/{id}/agent'
        $paths | Should -Contain 'DELETE /api/session/{id}'
        $paths | Should -Contain 'POST /api/session/{id}/permission/{permissionID}/reply'
        $paths | Should -Contain 'GET /api/event?types=...'
    }
    It 'fails closed on a version mismatch' {
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version='9.9.9'; routes=@() }
        $r.Ok | Should -BeFalse
        $r.Reasons -join ' ' | Should -Match 'version'
    }
    It 'fails closed when a required route is missing' {
        $contract = Get-SlopOpenCodeCompatContract
        $routes = @($contract.RequiredRoutes | Where-Object { $_.Path -ne '/api/session/{id}/model' } |
            ForEach-Object { $_.Method + ' ' + $_.Path })
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version=$contract.PinnedVersion; routes=$routes }
        $r.Ok | Should -BeFalse
        $r.Reasons -join ' ' | Should -Match '/api/session/\{id\}/model'
    }
    It 'passes when the pinned version exposes every required route' {
        $contract = Get-SlopOpenCodeCompatContract
        $routes = @($contract.RequiredRoutes | ForEach-Object { $_.Method + ' ' + $_.Path })
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version=$contract.PinnedVersion; routes=$routes }
        $r.Ok | Should -BeTrue
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/slop-opencode-compat-check.ps1' -CI -Output Normal"
```
Expected: fail with "The term 'Get-SlopOpenCodeCompatContract' is not recognized".

- [ ] **Step 3: Write `src/Slop.OpenCodeCompat.ps1`**

```powershell
# Pinned OpenCode version and the exact API surface the Tier 2 bridge depends on. Headless.
$ErrorActionPreference = 'Stop'

function Get-SlopOpenCodeCompatContract {
    return @{
        PinnedVersion  = '2.3.2'
        RequiredRoutes = @(
            @{ Method='GET';    Path='/api/config' }
            @{ Method='GET';    Path='/api/agent' }
            @{ Method='GET';    Path='/api/model' }
            @{ Method='GET';    Path='/api/provider' }
            @{ Method='POST';   Path='/api/session' }
            @{ Method='POST';   Path='/api/session/{id}/agent' }
            @{ Method='POST';   Path='/api/session/{id}/model' }
            @{ Method='POST';   Path='/api/session/{id}/prompt' }
            @{ Method='POST';   Path='/api/session/{id}/interrupt' }
            @{ Method='POST';   Path='/api/session/{id}/permission/{permissionID}/reply' }
            @{ Method='DELETE'; Path='/api/session/{id}' }
            @{ Method='GET';    Path='/api/event?types=...' }
            @{ Method='GET';    Path='/api/permission/saved' }
        )
    }
}

function Test-SlopOpenCodeCompatContract {
    param(
        [Parameter(Mandatory)][hashtable]$Observed,
        [hashtable]$Contract = (Get-SlopOpenCodeCompatContract)
    )
    $reasons = [Collections.Generic.List[string]]::new()
    if ([string]$Observed.version -ne [string]$Contract.PinnedVersion) {
        $reasons.Add("OpenCode version $($Observed.version) is not the supported $($Contract.PinnedVersion)")
    }
    $seen = @($Observed.routes | ForEach-Object { if ($_ -is [hashtable]) { $_.Method + ' ' + $_.Path } else { [string]$_ } })
    foreach ($route in $Contract.RequiredRoutes) {
        $needle = $route.Method + ' ' + $route.Path
        if ($needle -notin $seen) { $reasons.Add("missing route: $needle") }
    }
    return @{ Ok=($reasons.Count -eq 0); Reasons=$reasons.ToArray() }
}
```

- [ ] **Step 4: Probe a disposable OpenCode instance and record the observed surface**

Against a **disposable** service only (never the user's shared service), run a safe GET probe and pass its output to the contract check:

```powershell
$base = 'http://127.0.0.1:<disposable-port>'
$info = Invoke-RestMethod -Uri "$base/api/config" -Headers $auth
$paths = @('/api/config','/api/agent','/api/model','/api/provider','/api/event','/api/permission/saved') |
    ForEach-Object {
        try { $r = Invoke-WebRequest -Uri "$base$_" -Headers $auth -Method Get -UseBasicParsing; "GET $_" }
        catch { "MISSING GET $_" }
    }
$observed = @{ version=[string]$info.version; routes=$paths }
Test-SlopOpenCodeCompatContract -Observed $observed | Format-List
```
Expected: `Ok = True`. Record the exact command and output in the Task 14 verification report. POST/DELETE routes are verified by the existing live bridge tests, not by this read-only probe. Do not apply the controlled config or restart the shared service.

- [ ] **Step 5: Run the compatibility test to verify it passes**

Same command as Step 2. Expected: 5 passed, 0 failed.

- [ ] **Step 6: Stage (no commit)**

```powershell
git add src/Slop.OpenCodeCompat.ps1 tests/slop-opencode-compat-check.ps1 tests/Slop.Tests.ps1
```

## Part B self-review

- Every amended requirement in the spec maps to Task 8, 9, 10, 11, 12, 13, 14, or 15.
- Route badge names locality, provider, and effective model — never just the tier.
- No code path allows a remote route to send before disclosure acceptance.
- No product surface offers `Allow always`; no Sloppy config stores a provider credential.
- Permission verification is fail-closed and tests cover broad allow, saved edit-all, and missing hard-deny.
- Deletion copy never claims a remote provider deleted its copy.
- Automatic failover, one-click sign-in, universal version support, and `.agents` distillation are deferred, not silently assumed.
- No subagents, no commits, no push, no CI changes.

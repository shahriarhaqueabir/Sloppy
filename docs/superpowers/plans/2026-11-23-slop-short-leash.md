# S.L.O.P. Short-Leash OpenCode Bridge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not use paid subagents.

**Goal:** Connect Slop to `opencode serve` with deny-all-by-default tool permissions, explicit `once`/`reject` approval in the chat, and no unattended host access.

**Architecture:** A repo-scoped `.opencode/opencode.jsonc` defines a dedicated `slop-short-leash` primary agent with a deny-all permission baseline and hard policies. A new pure module `src/Slop.OpenCode.ps1` validates config, builds JSON bodies with `ConvertTo-Json`, and filters/normalizes OpenCode SSE events. `src/Slop.ps1` keeps its existing lifecycle, generation guard, dispatcher tick, and signal table; the thread job is swapped from llama.cpp to the OpenCode HTTP/SSE path. No new shapes, colours, or motion.

**Tech Stack:** Windows PowerShell 7 (`pwsh`), WPF via XAML-in-string, `Start-ThreadJob`, `HttpClient`, `ReadLineAsync(CancellationToken)`, `ConcurrentQueue[string]`, `DispatcherTimer`, no Pester — plain assertion scripts.

**Spec:** [`docs/superpowers/specs/2026-11-23-slop-short-leash-design.md`](../specs/2026-11-23-slop-short-leash-design.md). **Review:** [`docs/security/opencode-route-review.md`](../../security/opencode-route-review.md).

Verified against OpenCode v2.3.2 docs and live OpenAPI on 2026-11-23:
- Agent `permissions` is an array of `{action, resource, effect}` with `effect ∈ allow|deny|ask`; `mode: "primary"` is valid.
- Policies are `{action, resource, effect}` with `effect ∈ allow|deny`; `tool.use` resources are `<action>:<value>`; last matching statement wins.
- `.opencode/opencode.jsonc` is a valid project config location. **Policies from broader config are evaluated later** — a global `allow` policy overrides a repo `deny`. The tripwire in Task 1 checks both files.
- `GET /api/event?types=<value>` accepts repeated `types` params; session ID is at `event.data.sessionID` (NOT top level).
- `permission.asked.data`: `id` (request ID), `sessionID`, `action`, `resources[]`. `permission.replied.data`: `requestID`, `reply`.
- `session.text.delta.data.delta` carries the text.
- `POST /api/session` responds with `{ data: { id } }` (confirmed by OpenCode's own `session-create.test.ts`), so the ID must be read from `.data.id`.

---

## File structure

| File | Responsibility |
|---|---|
| `.opencode/opencode.jsonc` | NEW. Deny-all config + `slop-short-leash` primary agent + hard policies. |
| `src/Slop.OpenCode.ps1` | NEW. Pure helpers: config tripwire, JSON bodies, Basic auth header, event filter/normalizer, SSE reader. No WPF, no network calls. |
| `src/Slop.ps1` | MODIFY. Dot-source module; swap thread job to OpenCode; render approval card; reject pending on Stop/Collapse; delete session on close. |
| `tests/slop-opencode-check.ps1` | NEW. Headless assertions for all of the above. |
| `docs/architecture.md` | MODIFY. Correct stale "ask by default" / "TUI handles approval" claims. |
| `tests/slop-lifecycle-check.ps1`, `tests/slop-motion-check.ps1`, `tools/verify-motion.ps1` | UNCHANGED. Must stay green. |

---

## Task 1: Write the RED headless suite

**Files:**
- Create: `tests/slop-opencode-check.ps1`

- [ ] **Step 1: Create the test file with the complete assertion suite**

Follow the pattern of `tests/slop-lifecycle-check.ps1` (plain `Assert-True`, `$script:failures`, exit 1 at end).

```powershell
# Headless checks for the S.L.O.P. short-leash bridge. No WPF, no network, no Pester.
$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '../src/Slop.OpenCode.ps1'
$repoConfig = Join-Path $PSScriptRoot '../.opencode/opencode.jsonc'
$globalConfig = Join-Path $env:USERPROFILE '.config/opencode/opencode.jsonc'
if (Test-Path $module) { . $module }

$script:failures = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { "PASS: $Message" } else { "FAIL: $Message"; $script:failures++ }
}

$required = @(
    'Get-SlopOpenCodeEventTypes', 'Test-SlopOpenCodeConfig', 'New-SlopPromptBody',
    'New-SlopPermissionReply', 'New-SlopOpenCodeAuthHeader',
    'Test-SlopOpenCodeEvent', 'Read-SlopOpenCodeSse'
)
$missing = @($required | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
if ($missing.Count) { throw "missing bridge functions: $($missing -join ', ')" }

# --- allowlist -----------------------------------------------------------
$types = @(Get-SlopOpenCodeEventTypes)
Assert-True ($types.Count -eq 8) 'event allowlist has exactly 8 types'
foreach ($t in @('session.text.delta','session.step.first-token','session.execution.succeeded',
                 'session.execution.failed','session.execution.interrupted','session.idle',
                 'permission.asked','permission.replied')) {
    Assert-True ($t -in $types) "allowlist contains $t"
}

# --- config tripwire -----------------------------------------------------
$cfg = Test-SlopOpenCodeConfig -RepoConfigPath $repoConfig -GlobalConfigPath $globalConfig
Assert-True $cfg.Ok "config tripwire passes ($($cfg.Errors -join '; '))"
$parsed = Get-Content $repoConfig -Raw | ConvertFrom-Json
$agent = $parsed.agents.'slop-short-leash'
Assert-True ($agent.mode -eq 'primary') 'slop-short-leash is a primary agent'
Assert-True ($agent.permissions[0].action -eq '*' -and $agent.permissions[0].resource -eq '*' -and $agent.permissions[0].effect -eq 'deny') 'baseline deny rule is first'
$asks = @($agent.permissions | Where-Object { $_.effect -eq 'ask' } | ForEach-Object { $_.action })
Assert-True ((($asks | Sort-Object) -join ',') -ceq 'glob,grep,read,webfetch,websearch') 'only five read actions are approvable'
Assert-True (@($agent.permissions | Where-Object { $_.effect -eq 'allow' }).Count -eq 0) 'agent has no allow rules'
$policyResources = @($parsed.policies | ForEach-Object { "$($_.action):$($_.resource):$($_.effect)" })
foreach ($needle in @('tool.use:*:deny','tool.use:read:*:allow','tool.use:glob:*:allow',
                      'tool.use:grep:*:allow','tool.use:websearch:*:allow','tool.use:webfetch:*:allow',
                      'tool.use:shell:*:deny','tool.use:edit:*:deny','tool.use:write:*:deny',
                      'tool.use:patch:*:deny','tool.use:external_directory:*:deny',
                      'tool.use:subagent:*:deny','mcp.use:*:deny','skill.use:*:deny',
                      'plugin.use:*:deny')) {
    Assert-True ($needle -in $policyResources) "hard policy present: $needle"
}
Assert-True ($parsed.policies[0].action -eq 'tool.use' -and $parsed.policies[0].resource -eq '*' -and $parsed.policies[0].effect -eq 'deny') 'broad tool deny is the first policy'

# global policy override is the tripwire's job; assert it is detected with a fixture
$badGlobal = Join-Path $PSScriptRoot 'fixtures/global-allow.jsonc'
New-Item -ItemType Directory -Force (Split-Path $badGlobal) | Out-Null
Set-Content $badGlobal '{"policies":[{"action":"tool.use","resource":"shell:*","effect":"allow"}]}'
$badResult = Test-SlopOpenCodeConfig -RepoConfigPath $repoConfig -GlobalConfigPath $badGlobal
Assert-True (-not $badResult.Ok -and ($badResult.Errors -match 'global').Count -gt 0) 'global tool allow is rejected as a policy override'
Remove-Item $badGlobal -Force

# --- prompt body (injection) --------------------------------------------
$payload = 'x","files":[{"path":"C:\\Users\\example\\.ssh\\id_ed25519"}]'
$body = New-SlopPromptBody -Text $payload
$decoded = $body | ConvertFrom-Json
Assert-True (($decoded.PSObject.Properties.Name -join ',') -ceq 'text') 'prompt body has only a text field'
Assert-True ($decoded.text -ceq $payload) 'injection payload stays verbatim inside text'
Assert-True ($null -eq $decoded.files) 'no injected files field'
$threw = $false; try { New-SlopPromptBody -Text ('a' * 8001) | Out-Null } catch { $threw = $true }
Assert-True $threw 'oversized prompt throws'

# --- permission reply ----------------------------------------------------
Assert-True ((New-SlopPermissionReply -Decision once) -eq '{"decision":"once"}') 'once reply body'
Assert-True ((New-SlopPermissionReply -Decision reject) -eq '{"decision":"reject"}') 'reject reply body'
foreach ($bad in @('always','ALWAYS','')) {
    $threw = $false; try { New-SlopPermissionReply -Decision $bad | Out-Null } catch { $threw = $true }
    Assert-True $threw "decision '$bad' is rejected"
}

# --- auth header ---------------------------------------------------------
$old = $env:OPENCODE_PASSWORD
try {
    Remove-Item Env:OPENCODE_PASSWORD -ErrorAction SilentlyContinue
    $threw = $false; try { New-SlopOpenCodeAuthHeader | Out-Null } catch { $threw = $true }
    Assert-True $threw 'missing OPENCODE_PASSWORD throws (fail closed)'
    $env:OPENCODE_PASSWORD = 'hunter2-not-a-real-password'
    $h = New-SlopOpenCodeAuthHeader
    $plain = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($h.Authorization.Substring(6)))
    Assert-True ($plain -ceq 'opencode:hunter2-not-a-real-password') 'Basic auth header decodes to opencode:<password>'
} finally {
    if ($null -eq $old) { Remove-Item Env:OPENCODE_PASSWORD -ErrorAction SilentlyContinue } else { $env:OPENCODE_PASSWORD = $old }
}

# --- event classifier ----------------------------------------------------
$evt = @{ type='session.text.delta'; data=@{ sessionID='sess_abc'; delta='hi'; ordinal=0; assistantMessageID='msg_1' } } | ConvertTo-Json -Depth 6 -Compress
$ok = Test-SlopOpenCodeEvent -Json $evt -SessionID 'sess_abc' -AllowedTypes $types
Assert-True ($ok.Accepted -and $ok.Type -eq 'session.text.delta' -and $ok.Text -eq 'hi') 'valid text delta accepted'
$wrong = Test-SlopOpenCodeEvent -Json $evt -SessionID 'sess_other' -AllowedTypes $types
Assert-True (-not $wrong.Accepted) 'wrong sessionID rejected'
$prefix = Test-SlopOpenCodeEvent -Json $evt -SessionID 'sess_ab' -AllowedTypes $types
Assert-True (-not $prefix.Accepted) 'prefix sessionID rejected (exact equality)'
$badType = Test-SlopOpenCodeEvent -Json ($evt -replace 'session.text.delta','credential.updated') -SessionID 'sess_abc' -AllowedTypes $types
Assert-True (-not $badType.Accepted) 'type outside allowlist rejected'
$malformed = Test-SlopOpenCodeEvent -Json '{not-json' -SessionID 'sess_abc' -AllowedTypes $types
Assert-True (-not $malformed.Accepted) 'malformed JSON rejected'
$ask = @{ type='permission.asked'; data=@{ id='prm_1'; sessionID='sess_abc'; action='read'; resources=@('C:\\tmp\\a.txt') } } | ConvertTo-Json -Depth 6 -Compress
$a = Test-SlopOpenCodeEvent -Json $ask -SessionID 'sess_abc' -AllowedTypes $types
Assert-True ($a.Accepted -and $a.RequestID -eq 'prm_1' -and $a.Action -eq 'read' -and $a.Resources.Count -eq 1) 'permission.asked fields extracted'
$delta = @{ type='session.text.delta'; data=@{ sessionID='sess_abc'; delta='second'; ordinal=1; assistantMessageID='msg_1' } } | ConvertTo-Json -Depth 6 -Compress
$reader = [IO.StringReader]::new("`n`n`n" + $delta + "`n`n")
$out = [Collections.Concurrent.ConcurrentQueue[string]]::new()
$stats = Read-SlopOpenCodeSse -Reader $reader -Queue $out -SessionID 'sess_abc' -AllowedTypes $types -Cts ([Threading.CancellationTokenSource]::new())
$tok = $null
Assert-True ($out.TryDequeue([ref]$tok) -and $tok -ceq '__TOK__second') 'SSE reader normalizes delta to __TOK__ token'
Assert-True ($stats.Events -eq 1 -and $stats.Malformed -eq 0) 'SSE reader counts events and malformed lines'

if ($script:failures -gt 0) { "`n$($script:failures) FAILURE(S)"; exit 1 }
"ALL OPENCODE CHECKS PASSED"
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -File tests/slop-opencode-check.ps1`
Expected: exit code 1, message `missing bridge functions: Get-SlopOpenCodeEventTypes, ...`

- [ ] **Step 3: Commit RED**

```powershell
git add tests/slop-opencode-check.ps1
git commit -m "test: add RED suite for short-leash bridge"
```

---

## Task 2: Create the repo-scoped control plane

**Files:**
- Create: `.opencode/opencode.jsonc`

- [ ] **Step 1: Write strict JSON (no comments, so tests parse it directly)**

```json
{
  "$schema": "https://opencode.ai/config.json",
  "agents": {
    "slop-short-leash": {
      "description": "Read-only, approval-gated agent for the Slop bridge",
      "mode": "primary",
      "system": "You are Slop's research voice. Answer from what you can read or fetch. If a capability is blocked by configuration policy, say so plainly and do not work around it.",
      "permissions": [
        { "action": "*", "resource": "*", "effect": "deny" },
        { "action": "read", "resource": "*", "effect": "ask" },
        { "action": "glob", "resource": "*", "effect": "ask" },
        { "action": "grep", "resource": "*", "effect": "ask" },
        { "action": "websearch", "resource": "*", "effect": "ask" },
        { "action": "webfetch", "resource": "*", "effect": "ask" },
        { "action": "webfetch", "resource": "*127.0.0.1*", "effect": "deny" },
        { "action": "webfetch", "resource": "*localhost*", "effect": "deny" },
        { "action": "webfetch", "resource": "*169.254.169.254*", "effect": "deny" },
        { "action": "webfetch", "resource": "*file://*", "effect": "deny" }
      ]
    }
  },
  "policies": [
    { "action": "tool.use", "resource": "*", "effect": "deny" },
    { "action": "tool.use", "resource": "read:*", "effect": "allow" },
    { "action": "tool.use", "resource": "glob:*", "effect": "allow" },
    { "action": "tool.use", "resource": "grep:*", "effect": "allow" },
    { "action": "tool.use", "resource": "websearch:*", "effect": "allow" },
    { "action": "tool.use", "resource": "webfetch:*", "effect": "allow" },
    { "action": "tool.use", "resource": "webfetch:*127.0.0.1*", "effect": "deny" },
    { "action": "tool.use", "resource": "webfetch:*localhost*", "effect": "deny" },
    { "action": "tool.use", "resource": "webfetch:*169.254.169.254*", "effect": "deny" },
    { "action": "tool.use", "resource": "webfetch:*file://*", "effect": "deny" },
    { "action": "tool.use", "resource": "external_directory:*", "effect": "deny" },
    { "action": "tool.use", "resource": "shell:*", "effect": "deny" },
    { "action": "tool.use", "resource": "edit:*", "effect": "deny" },
    { "action": "tool.use", "resource": "write:*", "effect": "deny" },
    { "action": "tool.use", "resource": "patch:*", "effect": "deny" },
    { "action": "tool.use", "resource": "subagent:*", "effect": "deny" },
    { "action": "mcp.use", "resource": "*", "effect": "deny" },
    { "action": "skill.use", "resource": "*", "effect": "deny" },
    { "action": "plugin.use", "resource": "*", "effect": "deny" }
  ]
}
```

Do NOT add `provider.use`, `integration.use`, or `websearch.use` denies — they would remove the model or search provider the bridge needs. Do NOT add `always` anywhere.

- [ ] **Step 2: Sanity-check the config parses**

Run: `pwsh -NoProfile -Command "Get-Content .opencode/opencode.jsonc -Raw | ConvertFrom-Json | Out-Null; 'config parses'"`
Expected: `config parses`

- [ ] **Step 3: Commit**

```powershell
git add .opencode/opencode.jsonc
git commit -m "feat: add repo-scoped deny-all Slop agent config"
```

---

## Task 3: Create the pure bridge module and turn the suite green

**Files:**
- Create: `src/Slop.OpenCode.ps1`

- [ ] **Step 1: Write the module**

```powershell
# S.L.O.P. OpenCode bridge helpers: pure config, JSON, event and SSE logic. No WPF, no HTTP.
$ErrorActionPreference = 'Stop'

$script:SlopOpenCodeEventTypes = @(
    'session.text.delta',
    'session.step.first-token',
    'session.execution.succeeded',
    'session.execution.failed',
    'session.execution.interrupted',
    'session.idle',
    'permission.asked',
    'permission.replied'
)

function Get-SlopOpenCodeEventTypes { return @($script:SlopOpenCodeEventTypes) }

function Test-SlopOpenCodeConfig {
    param(
        [Parameter(Mandatory)][string]$RepoConfigPath,
        [string]$GlobalConfigPath
    )
    $errors = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path $RepoConfigPath)) { $errors.Add('repo config missing'); return @{ Ok = $false; Errors = $errors.ToArray() } }
    try { $repo = Get-Content $RepoConfigPath -Raw | ConvertFrom-Json } catch { $errors.Add('repo config invalid JSON'); return @{ Ok = $false; Errors = $errors.ToArray() } }

    $agent = $repo.agents.'slop-short-leash'
    if (-not $agent) { $errors.Add('slop-short-leash agent missing') }
    else {
        if ($agent.mode -ne 'primary') { $errors.Add('agent is not primary') }
        $rules = @($agent.permissions)
        if ($rules.Count -eq 0 -or $rules[0].action -ne '*' -or $rules[0].resource -ne '*' -or $rules[0].effect -ne 'deny') { $errors.Add('baseline deny rule missing') }
        $asks = @($rules | Where-Object { $_.effect -eq 'ask' } | ForEach-Object { $_.action } | Sort-Object) -join ','
        if ($asks -ne 'glob,grep,read,webfetch,websearch') { $errors.Add("approvable set changed: $asks") }
        if (@($rules | Where-Object { $_.effect -eq 'allow' }).Count -gt 0) { $errors.Add('agent has allow rules') }
        foreach ($p in @('*127.0.0.1*','*localhost*','*169.254.169.254*','*file://*')) {
            if (@($rules | Where-Object { $_.action -eq 'webfetch' -and $_.resource -ceq $p -and $_.effect -eq 'deny' }).Count -eq 0) { $errors.Add("agent private webfetch deny missing: $p") }
        }
    }

    $pol = @($repo.policies)
    if ($pol.Count -eq 0 -or $pol[0].action -ne 'tool.use' -or $pol[0].resource -ne '*' -or $pol[0].effect -ne 'deny') { $errors.Add('broad tool deny policy missing or not first') }
    $need = @(
        @{a='tool.use';r='read:*';e='allow'}, @{a='tool.use';r='glob:*';e='allow'},
        @{a='tool.use';r='grep:*';e='allow'}, @{a='tool.use';r='websearch:*';e='allow'},
        @{a='tool.use';r='webfetch:*';e='allow'},
        @{a='tool.use';r='webfetch:*127.0.0.1*';e='deny'}, @{a='tool.use';r='webfetch:*localhost*';e='deny'},
        @{a='tool.use';r='webfetch:*169.254.169.254*';e='deny'}, @{a='tool.use';r='webfetch:*file://*';e='deny'},
        @{a='tool.use';r='external_directory:*';e='deny'}, @{a='tool.use';r='shell:*';e='deny'},
        @{a='tool.use';r='edit:*';e='deny'}, @{a='tool.use';r='write:*';e='deny'},
        @{a='tool.use';r='patch:*';e='deny'}, @{a='tool.use';r='subagent:*';e='deny'},
        @{a='mcp.use';r='*';e='deny'}, @{a='skill.use';r='*';e='deny'}, @{a='plugin.use';r='*';e='deny'}
    )
    foreach ($n in $need) {
        if (@($pol | Where-Object { $_.action -ceq $n.a -and $_.resource -ceq $n.r -and $_.effect -ceq $n.e }).Count -eq 0) { $errors.Add("policy missing: $($n.a):$($n.r):$($n.e)") }
    }

    # Policies from broader config are evaluated later and override repo policies.
    if ($GlobalConfigPath -and (Test-Path $GlobalConfigPath)) {
        try { $globalCfg = Get-Content $GlobalConfigPath -Raw | ConvertFrom-Json }
        catch { $globalCfg = $null; $errors.Add('global config invalid JSON') }
        if ($globalCfg) {
            $overrides = @($globalCfg.policies | Where-Object {
                $_.effect -eq 'allow' -and $_.action -in @('tool.use','mcp.use','skill.use','plugin.use')
            })
            if ($overrides.Count -gt 0) { $errors.Add('global policy allow overrides the repo deny (authority inversion)') }
        }
    }
    return @{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function New-SlopPromptBody {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$MaxLength = 8000
    )
    if ($Text.Length -gt $MaxLength) { throw "prompt exceeds $MaxLength characters" }
    return @{ text = $Text } | ConvertTo-Json -Depth 4 -Compress
}

function New-SlopPermissionReply {
    param([Parameter(Mandatory)][ValidateSet('once','reject')][string]$Decision)
    return @{ decision = $Decision } | ConvertTo-Json -Depth 4 -Compress
}

function New-SlopOpenCodeAuthHeader {
    $password = $env:OPENCODE_PASSWORD
    if ([string]::IsNullOrEmpty($password)) { throw 'OPENCODE_PASSWORD is not set' }
    $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("opencode:$password"))
    return @{ Authorization = "Basic $token" }
}

function Test-SlopOpenCodeEvent {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$SessionID,
        [Parameter(Mandatory)][string[]]$AllowedTypes
    )
    $reject = @{ Accepted = $false; Type = $null; Text = $null; RequestID = $null; Action = $null; Resources = @() }
    try { $evt = $Json | ConvertFrom-Json } catch { return $reject }
    if (-not $evt.type -or $evt.type -notin $AllowedTypes) { return $reject }
    if (-not $evt.data -or -not $evt.data.sessionID -or $evt.data.sessionID -cne $SessionID) { return $reject }
    $result = @{ Accepted = $true; Type = $evt.type; Text = $null; RequestID = $null; Action = $null; Resources = @() }
    switch ($evt.type) {
        'session.text.delta' {
            if ($null -eq $evt.data.delta) { return $reject }
            $result.Text = [string]$evt.data.delta
        }
        'permission.asked' {
            if (-not $evt.data.id -or -not $evt.data.action) { return $reject }
            $result.RequestID = [string]$evt.data.id
            $result.Action = [string]$evt.data.action
            if ($evt.data.resources) { $result.Resources = @($evt.data.resources | ForEach-Object { [string]$_ }) }
        }
    }
    return $result
}

function Read-SlopOpenCodeSse {
    param(
        [Parameter(Mandatory)][IO.TextReader]$Reader,
        [Parameter(Mandatory)][Collections.Concurrent.ConcurrentQueue[string]]$Queue,
        [Parameter(Mandatory)][string]$SessionID,
        [Parameter(Mandatory)][string[]]$AllowedTypes,
        [Parameter(Mandatory)][Threading.CancellationTokenSource]$Cts
    )
    $events = 0; $malformed = 0
    while (-not $Cts.IsCancellationRequested) {
        # Token-aware read inherited from Slop.Lifecycle.ps1 — a stalled server cannot hold the UI.
        $line = $Reader.ReadLineAsync($Cts.Token).GetAwaiter().GetResult()
        if ($null -eq $line) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not $line.StartsWith('data:')) { $malformed++; continue }
        $payload = $line.Substring(5).Trim()
        if (-not $payload) { continue }
        $ev = Test-SlopOpenCodeEvent -Json $payload -SessionID $SessionID -AllowedTypes $AllowedTypes
        if (-not $ev.Accepted) { continue }
        $events++
        switch ($ev.Type) {
            'session.text.delta'   { if ($ev.Text) { $Queue.Enqueue("__TOK__$($ev.Text)") } }
            'permission.asked'     { $Queue.Enqueue("__OCASK__$($ev.RequestID)|$($ev.Action)|$(($ev.Resources -join ',') -replace '\|',' ')") }
            'permission.replied'   { $Queue.Enqueue('__OCREPLIED__') }
            'session.execution.succeeded'    { $Queue.Enqueue('__OCSUCCESS__') }
            'session.execution.failed'       { $Queue.Enqueue('__ERR__OpenCode execution failed') }
            'session.execution.interrupted'  { $Queue.Enqueue('__ERR__Cancelled') }
            'session.idle'                   { $Queue.Enqueue('__DONE__') }
        }
    }
    return @{ Events = $events; Malformed = $malformed; Cancelled = $Cts.IsCancellationRequested }
}
```

Note: `__OCASK__` carries only request ID, action and a pipe-sanitized resource summary — never a raw event payload. The dispatcher tick reads it to build the card.

- [ ] **Step 2: Run the suite**

Run: `pwsh -NoProfile -File tests/slop-opencode-check.ps1`
Expected: `ALL OPENCODE CHECKS PASSED`, exit 0. If a specific assertion fails, fix the module — do not weaken the assertion.

- [ ] **Step 3: Run the existing suites to prove no regression**

```powershell
pwsh -NoProfile -File tests/slop-lifecycle-check.ps1
pwsh -NoProfile -File tests/slop-motion-check.ps1
```
Expected: `ALL LIFECYCLE CHECKS PASSED` and the motion suite's own success line, both exit 0.

- [ ] **Step 4: Commit**

```powershell
git add src/Slop.OpenCode.ps1
git commit -m "feat: add pure short-leash bridge helpers"
```

---

## Task 4: Wire the bridge into the WPF app

**Files:**
- Modify: `src/Slop.ps1`

- [ ] **Step 0: Fail closed before touching streaming state**

At the very top of `Start-Stream` (line 445), immediately after `if ($script:IsStreaming) { return }`, add:

```powershell
    try { $auth = New-SlopOpenCodeAuthHeader }
    catch {
        Add-Bubble -Text '[error: OPENCODE_PASSWORD is not set]' -IsUser $false
        return
    }
```

This must run **before** `Start-SlopRequest`, the `IsStreaming = $true` assignment, or the dispatcher timer is created — otherwise the app enters streaming state with no timer to drain the error queue. The `$auth` hashtable is then reused in Step 4.

- [ ] **Step 1: Dot-source the module**

After line 21 (`. (Join-Path $PSScriptRoot 'Slop.Lifecycle.ps1')`), add:

```powershell
. (Join-Path $PSScriptRoot 'Slop.OpenCode.ps1')
```

- [ ] **Step 2: Add bridge script state near the other script-scope state (around line 192)**

```powershell
$script:OpenCodeSessionId = $null
$script:OpenCodePending = @{}          # requestID -> generation, for the in-chat approval cards
$script:OpenCodeBaseUrl = $(if ($env:OPENCODE_BASE_URL) { $env:OPENCODE_BASE_URL } else { 'http://127.0.0.1:28894' })
$script:OpenCodeSideJobs = [Collections.Generic.List[object]]::new()
```

Never put the password in `$script:OpenCodeBaseUrl` or any URL. Add this helper beside the approval functions:

```powershell
function Remove-SlopCompletedSideJobs {
    foreach ($j in @($script:OpenCodeSideJobs)) {
        if ($j.State -eq 'Completed' -or $j.State -eq 'Failed') {
            Remove-Job $j -Force -ErrorAction SilentlyContinue
            $script:OpenCodeSideJobs.Remove($j) | Out-Null
        }
    }
}
```

Do not use `Register-ObjectEvent -Action` to clean up jobs: its scriptblock runs in a separate runspace and cannot see the job variable. Poll completion in `Finish-Stream` and `Add_Closed` instead.

- [ ] **Step 3: Add the approval-card functions next to `Add-Bubble` (after line 443)**

```powershell
function Add-SlopApprovalCard {
    param([string]$RequestId, [string]$Action, [string]$Resources, [int]$Generation)
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $border.Padding = [System.Windows.Thickness]::new(8)
    $border.Margin = [System.Windows.Thickness]::new(0,0,40,6)
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2AFFFFFF')
    $border.HorizontalAlignment = 'Left'

    $stack = New-Object System.Windows.Controls.StackPanel
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = "Approve $Action : $Resources"
    $label.Foreground = [System.Windows.Media.Brushes]::White
    $label.TextWrapping = 'Wrap'
    $label.FontSize = 12
    $stack.Children.Add($label) | Out-Null
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = [System.Windows.Thickness]::new(0,6,0,0)
    foreach ($spec in @(@('Allow once','once'), @('Reject','reject'))) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $spec[0]
        $btn.Style = $window.Resources['SlopButton']
        $btn.Margin = [System.Windows.Thickness]::new(0,0,8,0)
        $btn.Padding = [System.Windows.Thickness]::new(8,4,8,4)
        $btn.Add_Click({
            # Add_Click handlers do not close over function locals — read everything
            # from $this.Tag, which is owned by the control that fired the event.
            $tag = $this.Tag
            if ($script:RequestState.Generation -ne $tag.Generation) { return }
            $script:OpenCodePending.Remove($tag.RequestId) | Out-Null
            $tag.Stack.Children.Remove($tag.Row) | Out-Null
            Send-SlopPermissionReply -RequestId $tag.RequestId -Decision $tag.Decision -Generation $tag.Generation
        })
        $btn.Tag = @{ Decision = $spec[1]; RequestId = $RequestId; Generation = $Generation; Stack = $stack; Row = $row }
        $row.Children.Add($btn) | Out-Null
    }
    $stack.Children.Add($row) | Out-Null
    $border.Child = $stack
    $ChatStack.Children.Add($border) | Out-Null
    $ChatScroll.ScrollToEnd()
    $script:OpenCodePending[$RequestId] = @{ Generation = $Generation; Element = $border }
}

function Send-SlopPermissionReply {
    param([string]$RequestId, [string]$Decision, [int]$Generation)
    if (-not $script:OpenCodeSessionId) { return }
    $body = New-SlopPermissionReply -Decision $Decision
    $session = [uri]::EscapeDataString($script:OpenCodeSessionId)
    $reqId = [uri]::EscapeDataString($RequestId)
    $url = "$($script:OpenCodeBaseUrl)/api/session/$session/permission/$reqId/reply"
    $job = Start-ThreadJob -ScriptBlock {
        param($Url, $Body, $Auth)
        try {
            $client = New-Object System.Net.Http.HttpClient
            $content = New-Object System.Net.Http.StringContent($Body, [Text.Encoding]::UTF8, 'application/json')
            $req = [Net.Http.HttpRequestMessage]::new('POST', $Url)
            $req.Content = $content
            foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
            $client.SendAsync($req).GetAwaiter().GetResult() | Out-Null
        } catch { } finally { if ($client) { $client.Dispose() } }
    } -ArgumentList $url, $body, (New-SlopOpenCodeAuthHeader)
    $script:OpenCodeSideJobs.Add($job)
}

function Reject-SlopPendingApprovals {
    param([int]$Generation)
    foreach ($entry in @($script:OpenCodePending.GetEnumerator())) {
        if ($entry.Value.Generation -ne $Generation) { continue }
        $script:OpenCodePending.Remove($entry.Key) | Out-Null
        if ($entry.Value.Element) { $ChatStack.Children.Remove($entry.Value.Element) | Out-Null }
        Send-SlopPermissionReply -RequestId $entry.Key -Decision 'reject' -Generation $Generation
    }
}
```

The approved decision is always `once` or `reject` via `ValidateSet`; `always` is unreachable.

- [ ] **Step 4: Replace the thread-job body in `Start-Stream`**

Replace lines 475–530 (messages JSON → `Start-ThreadJob ... -ArgumentList ...`) with the OpenCode path. Keep everything before (UI state, bubbles, queue, CTS) and after (`$script:CurrentJob`, timer) unchanged.

```powershell
    $promptBody = New-SlopPromptBody -Text $UserText
    $url = $script:OpenCodeBaseUrl
    $script:Cts = New-Object System.Threading.CancellationTokenSource
    $lifecyclePath = Join-Path $PSScriptRoot 'Slop.Lifecycle.ps1'
    $bridgePath = Join-Path $PSScriptRoot 'Slop.OpenCode.ps1'
    $auth = New-SlopOpenCodeAuthHeader   # guarded at the top of Start-Stream (see note below)
    $types = @(Get-SlopOpenCodeEventTypes)

    $job = Start-ThreadJob -ScriptBlock {
        param($BaseUrl, $PromptBody, $Queue, $Cts, $LifecyclePath, $BridgePath, $Auth, $EventTypes, $TimeoutSeconds, $ExistingSessionId)
        . $LifecyclePath
        . $BridgePath
        $sessionId = $ExistingSessionId
        $client = $null; $resp = $null; $stream = $null; $reader = $null
        try {
            $client = New-Object System.Net.Http.HttpClient
            $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

            # 1. create a session only on the first turn; reuse it afterwards
            if (-not $sessionId) {
                $req = [Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/api/session")
                $req.Content = [Net.Http.StringContent]::new('{}', [Text.Encoding]::UTF8, 'application/json')
                foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
                $resp = $client.SendAsync($req, $Cts.Token).GetAwaiter().GetResult()
                if (-not $resp.IsSuccessStatusCode) { $Queue.Enqueue("__ERR__HTTP $([int]$resp.StatusCode)"); return }
                # POST /api/session returns { data: { id, ... } } — not a bare session object.
                $sessionJson = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
                $sessionId = $sessionJson.data.id
                if (-not $sessionId) { $Queue.Enqueue('__ERR__OpenCode session create returned no id'); return }
                $Queue.Enqueue("__OCSESSION__$sessionId")
                $resp.Dispose(); $resp = $null
            }

            # 2. pin the dedicated agent — fail closed if the switch does not succeed
            $agentBody = @{ agent = 'slop-short-leash' } | ConvertTo-Json -Depth 4 -Compress
            $req = [Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/api/session/$([uri]::EscapeDataString($sessionId))/agent")
            $req.Content = [Net.Http.StringContent]::new($agentBody, [Text.Encoding]::UTF8, 'application/json')
            foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
            $resp = $client.SendAsync($req, $Cts.Token).GetAwaiter().GetResult()
            if (-not $resp.IsSuccessStatusCode) { $Queue.Enqueue('__ERR__OpenCode agent switch failed'); return }

            # 3. subscribe BEFORE prompting — SSE has no replay
            $qs = ($EventTypes | ForEach-Object { "types=$([uri]::EscapeDataString($_))" }) -join '&'
            $req = [Net.Http.HttpRequestMessage]::new('GET', "$BaseUrl/api/event?$qs")
            foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
            $resp = $client.SendAsync($req, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $Cts.Token).GetAwaiter().GetResult()
            if (-not $resp.IsSuccessStatusCode) { $Queue.Enqueue("__ERR__HTTP $([int]$resp.StatusCode)"); return }
            $Queue.Enqueue('__CONNECTED__')
            $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $reader = New-Object IO.StreamReader($stream)

            # 4. prompt (only new user text — no 12-message resend)
            if (-not $PromptBody.StartsWith('{')) { throw 'prompt body is not JSON' }
            $req = [Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/api/session/$([uri]::EscapeDataString($sessionId))/prompt")
            $req.Content = [Net.Http.StringContent]::new($PromptBody, [Text.Encoding]::UTF8, 'application/json')
            foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
            $promptResp = $client.SendAsync($req, $Cts.Token).GetAwaiter().GetResult()
            if (-not $promptResp.IsSuccessStatusCode) { $Queue.Enqueue("__ERR__HTTP $([int]$promptResp.StatusCode)"); return }
            $promptResp.Dispose()

            # 5. normalized event loop (token-aware ReadLineAsync lives in the module)
            $stats = Read-SlopOpenCodeSse -Reader $reader -Queue $Queue -SessionID $sessionId -AllowedTypes $EventTypes -Cts $Cts
            if ($stats.Cancelled) { $Queue.Enqueue('__ERR__Cancelled') }
            elseif ($stats.Malformed -gt 0 -and $stats.Events -eq 0) { $Queue.Enqueue("__ERR__Malformed stream ($($stats.Malformed) event(s))") }
            elseif ($stats.Malformed -gt 0) { $Queue.Enqueue("__WARN__$($stats.Malformed) malformed event(s)") }
        }
        catch [System.Threading.Tasks.TaskCanceledException] {
            if ($Cts.IsCancellationRequested) { $Queue.Enqueue('__ERR__Cancelled') } else { $Queue.Enqueue("__ERR__Timeout $TimeoutSeconds") }
        }
        catch [System.OperationCanceledException] { $Queue.Enqueue('__ERR__Cancelled') }
        catch { $Queue.Enqueue("__ERR__$($_.Exception.Message)") }
        finally {
            if ($reader) { $reader.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($resp) { $resp.Dispose() }
            if ($client) { $client.Dispose() }
            $Queue.Enqueue('__DONE__')
        }
    } -ArgumentList $url, $promptBody, $queue, $script:Cts, $lifecyclePath, $bridgePath, $auth, $types, $script:RequestTimeoutSeconds, $script:OpenCodeSessionId
```

On the first turn `$script:OpenCodeSessionId` is `$null`, so the job creates a session and enqueues `__OCSESSION__<id>`; the dispatcher tick records the ID on the UI thread (Step 6). Later turns reuse it. `opencode serve` must be started separately with the Slop repo as its working directory so it discovers `.opencode/opencode.jsonc` — the bridge only speaks HTTP and does not spawn the server.

- [ ] **Step 5: Extend `Request-StopStream` (line 319) to interrupt and reject**

Insert after `$script:Cts.Cancel()`:

```powershell
    Reject-SlopPendingApprovals -Generation $gen
    if ($script:OpenCodeSessionId) {
        $session = [uri]::EscapeDataString($script:OpenCodeSessionId)
        $url = "$($script:OpenCodeBaseUrl)/api/session/$session/interrupt"
        $job = Start-ThreadJob -ScriptBlock {
            param($Url, $Auth)
            try {
                $client = New-Object System.Net.Http.HttpClient
                $req = [Net.Http.HttpRequestMessage]::new('POST', $Url)
                foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
                $client.SendAsync($req).GetAwaiter().GetResult() | Out-Null
            } catch { } finally { if ($client) { $client.Dispose() } }
        } -ArgumentList $url, (New-SlopOpenCodeAuthHeader)
        $script:OpenCodeSideJobs.Add($job)
    }
```

Do not reintroduce `CancellationToken.Register([Action]{...})` — it fails in PowerShell with "There is no Runspace available to run scripts in this thread."

- [ ] **Step 6: Handle the new markers in the dispatcher tick `switch` (around line 552)**

In the `while ($q.TryDequeue([ref]$tok))` loop, insert this block **before** the line `$ev = Resolve-SlopStreamToken -Token $tok`. `Resolve-SlopStreamToken` treats any token it does not recognise as a plain text token, so bridge markers must be intercepted first:

```powershell
                if ($tok.StartsWith('__OC')) {
                    if ($tok.StartsWith('__OCSESSION__')) { $script:OpenCodeSessionId = $tok.Substring(13) }
                    elseif ($tok.StartsWith('__OCASK__')) {
                        $parts = $tok.Substring(9) -split '\|', 3
                        if ($parts.Count -eq 3) {
                            Add-SlopApprovalCard -RequestId $parts[0] -Action $parts[1] -Resources $parts[2] -Generation $gen
                        }
                    }
                    elseif ($tok -eq '__OCSUCCESS__') {
                        Set-SlopSignal -State $script:Motion -Color 'success' -Shape 'square' -HoldSeconds 1.5
                    }
                    # '__OCREPLIED__' needs no UI action.
                    continue
                }
```

`'__OCSESSION__'` is 13 characters, so `Substring(13)` returns the session ID verbatim. The existing `'token'`, `'cancelled'`, `'timeout'`, `'http'`, `'error'`, `'done'`, `'warning'` and `'connected'` cases stay exactly as they are. `Resolve-SlopStreamToken` already handles `__TOK__` → `token`.

- [ ] **Step 7: Delete the session on teardown**

In the `$window.Add_Closed` handler (line 691), before the existing closes:

```powershell
    Reject-SlopPendingApprovals -Generation $script:RequestState.Generation
    if ($script:OpenCodeSessionId) {
        $session = [uri]::EscapeDataString($script:OpenCodeSessionId)
        $url = "$($script:OpenCodeBaseUrl)/api/session/$session"
        $job = Start-ThreadJob -ScriptBlock {
            param($Url, $Auth)
            try {
                $client = New-Object System.Net.Http.HttpClient
                $req = [Net.Http.HttpRequestMessage]::new('DELETE', $Url)
                foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
                $client.SendAsync($req).GetAwaiter().GetResult() | Out-Null
            } catch { } finally { if ($client) { $client.Dispose() } }
        } -ArgumentList $url, (New-SlopOpenCodeAuthHeader)
        $script:OpenCodeSideJobs.Add($job)
    }
    Remove-SlopCompletedSideJobs
    $script:OpenCodeSessionId = $null
```

Add `Remove-SlopCompletedSideJobs` at the top of `Finish-Stream` (line 358) as well, so short helper jobs do not accumulate during a long-running tray session. Keep the OpenCode session across `Collapse-Chat` (the user may reopen the same conversation) and delete it only on window close.

- [ ] **Step 8: Prove the app still starts headlessly (no WPF construct in the module)**

```powershell
pwsh -NoProfile -File tests/slop-opencode-check.ps1
pwsh -NoProfile -File tests/slop-lifecycle-check.ps1
pwsh -NoProfile -File tests/slop-motion-check.ps1
```
Expected: all three exit 0. Then do a short manual launch with `pwsh -STA -File src/Slop.ps1` and confirm the pea appears, the chat expands, and — if `opencode serve` is running — a test prompt produces an approval card rather than a script exception. Terminate with `Stop-Process` on the exact PID — never leave the app running (an orphaned topmost process holds inherited stdout handles and hangs piped callers).

- [ ] **Step 9: Commit**

```powershell
git add src/Slop.ps1
git commit -m "feat: wire short-leash OpenCode bridge and approval card"
```

---

## Task 5: Correct the architecture document

**Files:**
- Modify: `docs/architecture.md`

- [ ] **Step 1: Replace the stale permissions section (lines 190–208) with the short-leash truth**

Replace the three tier bullets and the closing paragraph with:

```markdown
The shipped posture is deny-all by default, enforced by `.opencode/opencode.jsonc`
in this repo. It defines a dedicated `slop-short-leash` primary agent:

- **Read** — `read`, `glob`, `grep`, `websearch`, `webfetch` → `ask`, answerable only
  from the in-chat approval card with `once` or `reject`.
- **Everything else** — `shell`, `edit`, `write`, `patch`, `external_directory`,
  `subagents`, MCP servers, skills, plugins → hard `deny` via `tool.use` / `mcp.use`
  / `skill.use` / `plugin.use` policies. No approval path exists for these.
- Private and link-local fetch targets are hard-denied by wildcard policy.

A headless `opencode serve` has no TUI, so a dangling `ask` would hang until the
request timeout. The bridge subscribes to `permission.asked`, renders the card,
and replies with `once` or `reject` only — never `always`, which would persist an
approval. Collapse, Stop, generation change, or disconnect rejects all pending
requests. Tool permissions are defence in depth; the loopback bind and Basic-auth
password remain the primary barrier because several HTTP routes (shell, fs,
credential) bypass the agent tool layer.
```

- [ ] **Step 2: Update the event table row at line 152**

Change:
`| permission.asked / permission.replied | approval surface (deferred; initially the OpenCode TUI handles it) |`
to:
`| permission.asked / permission.replied | in-chat approval card with Allow once / Reject; no new signal state |`

- [ ] **Step 3: Update the roadmap (lines 238–243)**

Set Phase 1 to `in progress` (bridge wired, live checks pending) and Phase 2 to `done for the short-leash slice` (dedicated agent + deny-all config shipped). Phase 3 stays `planned`.

- [ ] **Step 4: Commit**

```powershell
git add docs/architecture.md
git commit -m "docs: correct architecture to short-leash deny-all reality"
```

---

## Task 6: Full verification, including live checks

- [ ] **Step 1: Headless gates**

```powershell
pwsh -NoProfile -File tests/slop-opencode-check.ps1
pwsh -NoProfile -File tests/slop-lifecycle-check.ps1
pwsh -NoProfile -File tests/slop-motion-check.ps1
pwsh -File "$env:USERPROFILE\.agents\scripts\verify.ps1" -ProjectPath (Get-Location).Path
```
Expected: exit 0 for all four. The verify gate currently has no detected test runner for this repo, so the three explicit suites are the real gate — do not skip them.

- [ ] **Step 2: Live checks against `opencode serve`**

Preconditions: `opencode serve` running from the Slop repo root on `127.0.0.1` with `OPENCODE_PASSWORD` set in the environment for both the app and any probe. Re-check port/PID first (`opencode service status`; `Get-NetTCPConnection -State Listen | Where-Object LocalPort -eq 28894`). The llama backend on 8081 is unrelated.

For each check, launch `pwsh -STA -File src/Slop.ps1`, drive it with focus-checked physical input, and `Stop-Process` the exact PID afterward:

1. Send "list the files in this repo" → an approval card appears. `Reject` → no file content, chat returns to idle.
2. Send the same request → card appears again. `Allow once` → content appears; a repeat request asks again (proof `always` was never persisted).
3. Send "run git status" → no card; the assistant reports the action is blocked by configuration policy.
4. Start a request, click Stop before the card is answered → card is removed, pending approval is rejected, `phase=finalized`, and the next request completes cleanly.
5. Confirm the signal glyph never changes shape or colour for an approval card, and that >3 s to first token still shows the amber rectangle.

If check 4 shows side effects surviving Stop, record it as a separate finding — do not silently widen this slice.

- [ ] **Step 3: Review gate**

Run the `review` skill / `~/.agents/scripts/review.ps1`. Confirm no TODO/FIXME placeholders, no raw event logging, no password in argv/logs/URLs, and no `always` decision path.

- [ ] **Step 4: Final commit of any live-fix deltas**

```powershell
git add -A
git commit -m "fix: address short-leash live verification findings"
git status --short
```
Expected status: only the three pre-existing untracked notes (`notesfront.md`, `notesfront2.md`, `src/Slop.md`). Nothing pushed.

---

## Terminal state

`docs/security/opencode-route-review.md` and the short-leash spec exist; `.opencode/opencode.jsonc`, `src/Slop.OpenCode.ps1`, `tests/slop-opencode-check.ps1` exist; `src/Slop.ps1` uses the OpenCode transport with in-chat approvals; `docs/architecture.md` no longer claims "ask by default" or TUI-mediated approvals; all headless suites and live checks pass; commits are local only.

---

## Execution record (2026-11-23)

Deviations from the written plan, all intentional and verified:

1. **Top-level `policies` are muted.** The original config applied `tool.use:* deny`
   to every agent in the repo, including the development session, and a `deny`
   has no approval path. The user renamed the file; the active
   `.opencode/opencode.jsonc` now contains only the `slop-short-leash` agent with
   its deny-all baseline and five `ask` reads. The original policy layer is kept
   verbatim at `.opencode/opencode.jsonc.muted`. `Test-SlopOpenCodeConfig` fails
   closed if repo-wide policies are ever re-enabled in the active file, and still
   rejects a global `allow` that would invert authority.
2. **The config tripwire is wired into `Start-Stream`**, not just tested. A prompt
   is refused before any streaming state or timer is created if config validation
   or the password check fails.
3. **Two plan defects corrected during Task 1/3:** `POST /api/session` responds
   with `{ data: { id } }`, so the session ID is read from `.data.id`; and the SSE
   fixture must prefix lines with `data:` — raw JSON lines are counted malformed.
   Also, `@($null).Count` is 1 in PowerShell, so the muted-policy check tests for
   `$null` explicitly.
4. **Two additional specs were written for future planning**, verbatim from the
   user's documents: `docs/superpowers/specs/2026-11-23-sloppy-settings-control-panel.md`
   and `docs/superpowers/specs/2026-11-23-sloppy-provider-security-architecture.md`.
   They are planning inputs only; no settings UI or provider adapters were built
   in this slice.
5. **Live authentication:** the already-running `opencode serve` on 28894 has no
   `OPENCODE_PASSWORD` in the development shell, so authenticated checks use a
   throwaway instance on 28895 started from the repo root with a test password.
   A no-password launch was also probed to prove the app fails closed with a chat
   bubble and no stderr output; the app was terminated with `Stop-Process`.
6. **Two live-found defects fixed after wiring.** (a) The approval card's Reject
   button removed only its button row, leaving the question label in chat; it now
   removes the whole border element. (b) A raw event dump against v2.3.2 showed
   `permission.replied` → `session.execution.interrupted` with **no** following
   `session.idle`, so the SSE reader never finished and Send stayed disabled for
   the full request timeout. All execution-terminal events now queue their signal,
   then `__DONE__`, and stop reading. (c) The bridge's `__TOK__` delta marker was
   being rendered literally; `Resolve-SlopStreamToken` now strips it.
7. **Live probes passed:** no-password fail-closed bubble; approval card shown and
   fully cleared on Reject; Send re-enabled within 15 s; Allow once produces an
   answer and the next prompt asks again (no `always` persistence); Stop rejects a
   pending card, leaves the app idle, and the following prompt answers cleanly
   with no error bubble. Every probe killed its own app with `Stop-Process`, and
   stderr was empty.

Headless results: `tests/slop-opencode-check.ps1`,
`tests/slop-lifecycle-check.ps1`, `tests/slop-motion-check.ps1` all exit 0.
Review gate is advisory only; the single "TODO" hit is the word `TodoWrite` in a
documentation table, and the `*.Tests.ps1` coverage hint does not match this
repo's `tests/*-check.ps1` convention.

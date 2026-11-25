# S.L.O.P. Request Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pure, headlessly testable request-lifecycle module to Slop and wire it into the existing WPF app so cancellation, timeout, malformed events, empty responses, and partial responses are all handled without late events corrupting new requests.

**Architecture:** `src/Slop.Lifecycle.ps1` owns phase state, generation guards, SSE parsing, and error formatting. It is dot-sourced by `src/Slop.ps1` alongside `Slop.Motion.ps1`. The background thread job and the UI dispatcher timer both carry the request generation; every event is checked against it before mutating UI state. No shape, color, size, or animation changes.

**Tech Stack:** Windows PowerShell 7 (`pwsh`), WPF via XAML-in-string, `Start-ThreadJob`, `System.Net.Http.HttpClient`, `ConcurrentQueue[string]`, `DispatcherTimer`, no Pester — plain assertion scripts.

---

## File structure

| File | Responsibility |
|---|---|
| `src/Slop.Lifecycle.ps1` | NEW. Pure lifecycle functions. No WPF, no backend. |
| `src/Slop.ps1` | MODIFY. Dot-source module, hold request state, pass generation into job and timer, handle markers. |
| `tests/slop-lifecycle-check.ps1` | ALREADY COMMITTED (RED). Headless assertions. Extend in Task 2. |
| `tests/slop-motion-check.ps1` | UNCHANGED. Must stay green. |
| `tools/verify-motion.ps1` | UNCHANGED. Live WPF verifier. Must stay green. |

---

### Task 1: Create the lifecycle module and turn the RED suite green

**Files:**
- Create: `src/Slop.Lifecycle.ps1`
- Test: `tests/slop-lifecycle-check.ps1` (already committed and confirmed RED at `83e41bf`)

- [ ] **Step 1: Confirm the RED gate**

Run: `pwsh -NoProfile -File tests/slop-lifecycle-check.ps1`
Expected: exit code 1, message `missing lifecycle functions: New-SlopRequestState, Start-SlopRequest, ...`

- [ ] **Step 2: Write the complete module**

Create `src/Slop.Lifecycle.ps1` with exactly this content:

```powershell
# S.L.O.P. request lifecycle: pure state, parsing and formatting. No WPF, no backend.
$ErrorActionPreference = 'Stop'

$SlopActivePhases = @('initiated', 'connected', 'streaming')

function New-SlopRequestState {
    return @{
        Generation        = 0
        Phase             = 'idle'
        StartedAt         = $null
        ConnectedAt       = $null
        FirstTokenAt      = $null
        LastTokenAt       = $null
        PreviousTokenAt   = $null
        CompletedAt       = $null
        FinalizedAt       = $null
        FailureReason     = $null
        MalformedCount    = 0
        TokenCount        = 0
        LastInterTokenGap = $null
    }
}

function Test-SlopRequestGeneration {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation
    )
    return ($State.Generation -eq $Generation -and $State.Phase -in $SlopActivePhases)
}

function Start-SlopRequest {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if ($State.Phase -in $SlopActivePhases) { return $false }
    $State.Generation++
    $State.Phase = 'initiated'
    $State.StartedAt = $Now
    $State.ConnectedAt = $null
    $State.FirstTokenAt = $null
    $State.LastTokenAt = $null
    $State.PreviousTokenAt = $null
    $State.CompletedAt = $null
    $State.FinalizedAt = $null
    $State.FailureReason = $null
    $State.MalformedCount = 0
    $State.TokenCount = 0
    $State.LastInterTokenGap = $null
    return $true
}

function Set-SlopRequestConnected {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    $State.Phase = 'connected'
    $State.ConnectedAt = $Now
    return $true
}

function Set-SlopRequestFirstToken {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    $State.Phase = 'streaming'
    $State.FirstTokenAt = $Now
    $State.LastTokenAt = $Now
    $State.PreviousTokenAt = $null
    $State.TokenCount = 1
    $State.LastInterTokenGap = $null
    return $true
}

function Set-SlopRequestToken {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    if ($null -eq $State.FirstTokenAt) {
        return Set-SlopRequestFirstToken -State $State -Generation $Generation -Now $Now
    }
    $State.PreviousTokenAt = $State.LastTokenAt
    $State.LastTokenAt = $Now
    if ($null -ne $State.PreviousTokenAt) {
        $State.LastInterTokenGap = ($Now - $State.PreviousTokenAt).TotalSeconds
    }
    $State.TokenCount++
    return $true
}

function Set-SlopRequestCompleted {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    $State.Phase = 'completed'
    $State.CompletedAt = $Now
    return $true
}

function Set-SlopRequestFailed {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [Parameter(Mandatory)][string]$Reason,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    $State.Phase = 'failed'
    $State.FailureReason = $Reason
    return $true
}

function Set-SlopRequestFinalized {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if ($State.Generation -ne $Generation) { return $false }
    $State.Phase = 'finalized'
    $State.FinalizedAt = $Now
    return $true
}

function Get-SlopRequestTiming {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [datetime]$Now = [DateTime]::UtcNow
    )
    $ttft = $null
    if ($null -ne $State.FirstTokenAt -and $null -ne $State.StartedAt) {
        $ttft = ($State.FirstTokenAt - $State.StartedAt).TotalSeconds
    }
    $since = $null
    if ($null -ne $State.LastTokenAt) { $since = ($Now - $State.LastTokenAt).TotalSeconds }
    $elapsed = $null
    if ($null -ne $State.StartedAt) { $elapsed = ($Now - $State.StartedAt).TotalSeconds }
    return @{
        Ttft           = $ttft
        InterTokenGap  = $State.LastInterTokenGap
        SinceLastToken = $since
        Elapsed        = $elapsed
    }
}

function Read-SlopSseStream {
    param(
        [Parameter(Mandatory)][System.IO.TextReader]$Reader,
        [Parameter(Mandatory)][System.Collections.Concurrent.ConcurrentQueue[string]]$Queue
    )
    $malformed = 0
    $tokens = 0
    while ($null -ne ($line = $Reader.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not $line.StartsWith('data:')) { continue }
        $data = $line.Substring(5).Trim()
        if ($data -eq '[DONE]') { break }
        try {
            $obj = $data | ConvertFrom-Json -ErrorAction Stop
            $delta = $obj.choices[0].delta.content
            if ($delta) {
                $Queue.Enqueue([string]$delta)
                $tokens++
            }
        } catch {
            $malformed++
        }
    }
    return @{ Malformed = $malformed; Tokens = $tokens }
}

function Resolve-SlopStreamToken {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Token)
    if ($Token -eq '__DONE__') { return @{ Kind = 'done'; Reason = $null; Text = $null } }
    if ($Token -eq '__CONNECTED__') { return @{ Kind = 'connected'; Reason = $null; Text = $null } }
    if ($Token.StartsWith('__WARN__')) {
        return @{ Kind = 'warning'; Reason = $Token.Substring(8); Text = $null }
    }
    if ($Token.StartsWith('__ERR__')) {
        $reason = $Token.Substring(7)
        $kind = if ($reason -eq 'Cancelled') { 'cancelled' }
                elseif ($reason -like 'Timeout*') { 'timeout' }
                elseif ($reason -like 'HTTP *') { 'http' }
                else { 'error' }
        return @{ Kind = $kind; Reason = $reason; Text = $null }
    }
    return @{ Kind = 'token'; Reason = $null; Text = $Token }
}

function Format-SlopStreamFailure {
    param(
        [string]$PartialText,
        [Parameter(Mandatory)][ValidateSet('cancelled', 'timeout', 'http', 'error')][string]$Kind,
        [string]$Reason
    )
    $label = switch ($Kind) {
        'cancelled' { '[cancelled]' }
        'timeout' {
            $secs = 300
            if ($Reason -match 'Timeout\s+(\d+)') { $secs = [int]$Matches[1] }
            "[timeout after ${secs}s]"
        }
        'http' { "[error: $Reason]" }
        'error' { "[error: $Reason]" }
    }
    if ([string]::IsNullOrWhiteSpace($PartialText)) { return $label }
    return $PartialText.TrimEnd() + "`n" + $label
}

function Format-SlopEmptyResponse {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '[empty response]' }
    return $null
}
```

- [ ] **Step 3: Run the headless suite and verify GREEN**

Run: `pwsh -NoProfile -File tests/slop-lifecycle-check.ps1`
Expected: 40+ `PASS:` lines and final line `ALL LIFECYCLE CHECKS PASSED`, exit code 0.

- [ ] **Step 4: Run the existing motion suite**

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: `ALL MOTION CHECKS PASSED`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/Slop.Lifecycle.ps1
git commit -m "feat: add pure slop request lifecycle module"
```

---

### Task 2: Extend the reproducer for connection and warning markers

**Files:**
- Modify: `tests/slop-lifecycle-check.ps1` (insert before the final `if ($script:failures -gt 0)` line)
- Modify: `src/Slop.Lifecycle.ps1` (only if a case fails — the implementation in Task 1 already covers these)

- [ ] **Step 1: Add the failing assertions**

Insert immediately before the final failure check in `tests/slop-lifecycle-check.ps1`:

```powershell
# 15. connection and warning markers are classified
$co = Resolve-SlopStreamToken -Token '__CONNECTED__'
$wa = Resolve-SlopStreamToken -Token '__WARN__3 malformed event(s)'
Assert-True ($co.Kind -eq 'connected' -and $wa.Kind -eq 'warning') `
    'connection and warning markers classified'
Assert-True ($wa.Reason -eq '3 malformed event(s)') 'warning reason preserved'
```

- [ ] **Step 2: Run to confirm these assertions pass against Task 1 code**

Run: `pwsh -NoProfile -File tests/slop-lifecycle-check.ps1`
Expected: `ALL LIFECYCLE CHECKS PASSED` with the two new `PASS:` lines present.

Note: these assertions are a regression guard for markers added in Task 1. If they fail, fix `Resolve-SlopStreamToken` before continuing.

- [ ] **Step 3: Commit the test extension**

```bash
git add tests/slop-lifecycle-check.ps1
git commit -m "test: cover connection and warning markers"
```

---

### Task 3: Wire the module and request state into Slop.ps1

**Files:**
- Modify: `src/Slop.ps1:20` (import)
- Modify: `src/Slop.ps1:153-164` (state block)

- [ ] **Step 1: Add the import**

Change line 20 from:

```powershell
. (Join-Path $PSScriptRoot 'Slop.Motion.ps1')
```

to:

```powershell
. (Join-Path $PSScriptRoot 'Slop.Motion.ps1')
. (Join-Path $PSScriptRoot 'Slop.Lifecycle.ps1')
```

- [ ] **Step 2: Add request state and timeout configuration**

Insert immediately after `$script:Cts = $null` in the state block:

```powershell
$script:RequestState = New-SlopRequestState
$script:RequestTimeoutSeconds = 300
if ($env:SLOP_REQUEST_TIMEOUT_SECONDS) {
    [int]$parsedTimeout = 0
    if ([int]::TryParse($env:SLOP_REQUEST_TIMEOUT_SECONDS, [ref]$parsedTimeout) -and $parsedTimeout -gt 0) {
        $script:RequestTimeoutSeconds = $parsedTimeout
    }
}
```

- [ ] **Step 3: Verify the app still parses**

Run: `pwsh -NoProfile -Command { $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile('src/Slop.ps1',[ref]$null,[ref]$errors) | Out-Null; 'Parser errors: ' + $errors.Count }`
Expected: `Parser errors: 0`

- [ ] **Step 4: Commit**

```bash
git add src/Slop.ps1
git commit -m "feat: import lifecycle module in slop"
```

---

### Task 4: Rewrite Start-Stream around the lifecycle module

**Files:**
- Modify: `src/Slop.ps1:299-311` (`Finish-Stream`)
- Modify: `src/Slop.ps1:383-492` (`Start-Stream` and its timer)
- Modify: `src/Slop.ps1:502` (Stop button — unchanged behavior, retained deliberately)

- [ ] **Step 1: Add the generation parameter to Finish-Stream**

Change the function signature at line 299 from:

```powershell
function Finish-Stream {
```

to:

```powershell
function Finish-Stream {
    param([Parameter(Mandatory)][int]$Generation)
```

and insert as the first statement in the function body:

```powershell
    Set-SlopRequestFinalized -State $script:RequestState -Generation $Generation | Out-Null
```

- [ ] **Step 2: Open a lifecycle request at the top of Start-Stream**

Immediately after `if ($script:IsStreaming) { return }` insert:

```powershell
    if (-not (Start-SlopRequest -State $script:RequestState)) { return }
    $generation = $script:RequestState.Generation
```

- [ ] **Step 3: Replace the request args and thread job block**

Replace lines 409-446 (from `$script:Cts = New-Object ...` through the closing `} -ArgumentList ...`) with:

```powershell
    $script:Cts = New-Object System.Threading.CancellationTokenSource
    $lifecyclePath = Join-Path $PSScriptRoot 'Slop.Lifecycle.ps1'

    $job = Start-ThreadJob -ScriptBlock {
        param($Url, $MessagesJson, $Queue, $Cts, $Generation, $TimeoutSeconds, $LifecyclePath)
        . $LifecyclePath
        $client = $null
        $resp = $null
        $stream = $null
        $reader = $null
        try {
            $body = @{ model = 'default'; messages = ($MessagesJson | ConvertFrom-Json); stream = $true; chat_template_kwargs = @{ enable_thinking = $false } } | ConvertTo-Json -Depth 6 -Compress
            $client = New-Object System.Net.Http.HttpClient
            $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
            $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, 'application/json')
            $req = [System.Net.Http.HttpRequestMessage]::new('POST', $Url)
            $req.Content = $content
            $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $Cts.Token).GetAwaiter().GetResult()
            if (-not $resp.IsSuccessStatusCode) {
                $Queue.Enqueue("__ERR__HTTP $([int]$resp.StatusCode)")
                return
            }
            $Queue.Enqueue('__CONNECTED__')
            $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $reader = New-Object System.IO.StreamReader($stream)
            $stats = Read-SlopSseStream -Reader $reader -Queue $Queue
            if ($stats.Malformed -gt 0 -and $stats.Tokens -eq 0) {
                $Queue.Enqueue("__ERR__Malformed stream ($($stats.Malformed) event(s))")
            }
            elseif ($stats.Malformed -gt 0) {
                $Queue.Enqueue("__WARN__$($stats.Malformed) malformed event(s)")
            }
        }
        catch [System.Threading.Tasks.TaskCanceledException] {
            if ($Cts.IsCancellationRequested) { $Queue.Enqueue('__ERR__Cancelled') }
            else { $Queue.Enqueue("__ERR__Timeout $TimeoutSeconds") }
        }
        catch [System.OperationCanceledException] {
            $Queue.Enqueue('__ERR__Cancelled')
        }
        catch {
            $Queue.Enqueue("__ERR__$($_.Exception.Message)")
        }
        finally {
            if ($reader) { $reader.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($resp) { $resp.Dispose() }
            if ($client) { $client.Dispose() }
            $Queue.Enqueue('__DONE__')
        }
    } -ArgumentList $url, $messagesJson, $script:TokenQueue, $script:Cts, $generation, $script:RequestTimeoutSeconds, $lifecyclePath
```

- [ ] **Step 4: Replace the timer body**

Replace the `$timer.Add_Tick({ ... })` block (lines 452-489) with:

```powershell
    $timer.Add_Tick({
        if (-not (Test-SlopRequestGeneration -State $script:RequestState -Generation $generation)) { return }
        $script:StalledNow = $script:IsStreaming -and `
            ((([DateTime]::UtcNow) - $script:LastTokenAt).TotalSeconds -gt 3)
        Set-SlopBaseCondition -State $script:Motion -Streaming $script:IsStreaming `
            -ChatOpen $script:Expanded -Stalled $script:StalledNow
        $tok = $null
        while ($script:TokenQueue.TryDequeue([ref]$tok)) {
            if (-not (Test-SlopRequestGeneration -State $script:RequestState -Generation $generation)) { return }
            $ev = Resolve-SlopStreamToken -Token $tok
            switch ($ev.Kind) {
                'connected' {
                    Set-SlopRequestConnected -State $script:RequestState -Generation $generation | Out-Null
                }
                'warning' {
                    $script:CurrentAssistantText += "`n[$($ev.Reason)]"
                    $script:CurrentAssistantBlock.Child.Text = $script:CurrentAssistantText
                }
                'cancelled' {
                    $script:Failed = $true
                    Set-SlopRequestFailed -State $script:RequestState -Generation $generation -Reason 'Cancelled' | Out-Null
                    $script:CurrentAssistantBlock.Child.Text = Format-SlopStreamFailure -PartialText $script:CurrentAssistantText -Kind 'cancelled' -Reason 'Cancelled'
                    Set-SlopSignal -State $script:Motion -Color 'error' -Shape 'rect' -HoldSeconds 2.0
                }
                'timeout' {
                    $script:Failed = $true
                    Set-SlopRequestFailed -State $script:RequestState -Generation $generation -Reason $ev.Reason | Out-Null
                    $script:CurrentAssistantBlock.Child.Text = Format-SlopStreamFailure -PartialText $script:CurrentAssistantText -Kind 'timeout' -Reason $ev.Reason
                    Set-SlopSignal -State $script:Motion -Color 'error' -Shape 'rect' -HoldSeconds 2.0
                }
                'http' {
                    $script:Failed = $true
                    Set-SlopRequestFailed -State $script:RequestState -Generation $generation -Reason $ev.Reason | Out-Null
                    $script:CurrentAssistantBlock.Child.Text = Format-SlopStreamFailure -PartialText $script:CurrentAssistantText -Kind 'http' -Reason $ev.Reason
                    Set-SlopSignal -State $script:Motion -Color 'error' -Shape 'rect' -HoldSeconds 2.0
                }
                'error' {
                    $script:Failed = $true
                    Set-SlopRequestFailed -State $script:RequestState -Generation $generation -Reason $ev.Reason | Out-Null
                    $script:CurrentAssistantBlock.Child.Text = Format-SlopStreamFailure -PartialText $script:CurrentAssistantText -Kind 'error' -Reason $ev.Reason
                    Set-SlopSignal -State $script:Motion -Color 'error' -Shape 'rect' -HoldSeconds 2.0
                }
                'done' {
                    if (-not $script:Failed) {
                        $emptyLabel = Format-SlopEmptyResponse -Text $script:CurrentAssistantText
                        if ($emptyLabel) {
                            $script:CurrentAssistantBlock.Child.Text = $emptyLabel
                            $script:CurrentAssistantText = $emptyLabel
                        }
                        else {
                            $script:Messages.Add(@{ role = 'assistant'; content = $script:CurrentAssistantText })
                            Trim-History
                            Set-SlopSignal -State $script:Motion -Color 'success' -Shape 'square' -HoldSeconds 1.5
                        }
                    }
                    Set-SlopRequestCompleted -State $script:RequestState -Generation $generation | Out-Null
                    Finish-Stream -Generation $generation
                    return
                }
                'token' {
                    if ($null -eq $script:RequestState.FirstTokenAt) {
                        Set-SlopRequestFirstToken -State $script:RequestState -Generation $generation | Out-Null
                    }
                    else {
                        Set-SlopRequestToken -State $script:RequestState -Generation $generation | Out-Null
                    }
                    $script:CurrentAssistantText += $ev.Text
                    $script:LastTokenAt = [DateTime]::UtcNow
                    $script:StalledNow = $false
                    Set-SlopBaseCondition -State $script:Motion -Streaming $true `
                        -ChatOpen $script:Expanded -Stalled $false
                    $tb = $script:CurrentAssistantBlock.Child
                    if (-not $script:StreamTextSpring) {
                        $script:StreamTextSpring = New-SlopSpring 0.70 240 24
                        $script:StreamTextSpring.Target = 1.0
                    }
                    $tb.Text = $script:CurrentAssistantText
                    $ChatScroll.ScrollToEnd()
                }
            }
        }
    })
```

- [ ] **Step 5: Confirm the Stop button still cancels the real request**

Verify line 502 remains:

```powershell
$StopBtn.Add_Click({ if ($script:Cts) { $script:Cts.Cancel() } })
```

No change required. The job now distinguishes cancellation from timeout using `$Cts.IsCancellationRequested`.

- [ ] **Step 6: Verify parser and headless suites**

Run: `pwsh -NoProfile -Command { $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile('src/Slop.ps1',[ref]$null,[ref]$errors) | Out-Null; 'Parser errors: ' + $errors.Count }`
Expected: `Parser errors: 0`

Run: `pwsh -NoProfile -File tests/slop-lifecycle-check.ps1`
Expected: `ALL LIFECYCLE CHECKS PASSED`

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: `ALL MOTION CHECKS PASSED`

- [ ] **Step 7: Commit**

```bash
git add src/Slop.ps1
git commit -m "feat: wire lifecycle state into slop streaming"
```

---

### Task 5: Full verification

**Files:** none changed.

- [ ] **Step 1: Run the live WPF verifier**

Run: `pwsh -NoProfile -File tools/verify-motion.ps1`
Expected: `SIGNAL chat-open ...`, `SIGNAL thinking ...`, `SIGNAL success ...`, `DRAG moved=...`, empty `APP OUT:`/`APP ERR:`, and the verifier terminates its own app process.

- [ ] **Step 2: Run the verify gate**

Run: the `verify` skill / `<agent-home>/scripts/verify.ps1`
Expected: `=== VERIFY COMPLETE === All gates passed.`

- [ ] **Step 3: Run the review gate**

Run: the `review` skill / `<agent-home>/scripts/review.ps1`
Expected: advisory pass; note the existing `source changed but no *.Tests.ps1 found` warning is expected because this repo uses `*check.ps1` names.

- [ ] **Step 4: Confirm clean branch state**

Run: `git status --short`
Expected: only the pre-existing untracked `notesfront.md`, `notesfront2.md`, `src/Slop.md`; no modified tracked files.

---

## Self-review notes

Spec coverage: state model and all 14 public functions (Task 1); generation guard (Tasks 1 and 4); disposal in finally (Task 4 Step 3); timeout vs cancel (Task 4 Step 3); malformed and empty handling (Task 4 Step 3 and Step 4); partial preservation (Task 4 Step 4); visual invariance (no visual edits anywhere); verification (Task 5).

Placeholder scan: no TBD, TODO, or "similar to" steps. Every code step contains complete code.

Type consistency: `Generation` is `[int]` everywhere; `Now` is `[datetime]` everywhere; marker spellings are `__DONE__`, `__CONNECTED__`, `__WARN__`, `__ERR__` in both the module and the job/closure; `Finish-Stream` is called with `-Generation` only from the timer.

Known constraint: do not dispatch subagents for this plan — the user has an explicit cost constraint. Execute inline with `executing-plans`.


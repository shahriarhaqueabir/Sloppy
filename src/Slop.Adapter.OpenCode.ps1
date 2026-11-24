# OpenCode harness adapter. Body extracted verbatim from the proven thread job;
# only the token plumbing and the dispatcher-owned __DONE__ were changed.
$ErrorActionPreference = 'Stop'

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
        [string]$AgentId = 'sloppy',
        [string]$ProviderId,
        [string]$Model,
        [bool]$PermissionProfileVerified = $false,
        [Parameter(Mandatory)][System.Collections.Concurrent.ConcurrentQueue[string]]$Queue,
        [Parameter(Mandatory)][System.Threading.CancellationToken]$Token
    )
    . $LifecyclePath
    . $BridgePath
    if (-not $PermissionProfileVerified) {
        $Queue.Enqueue('__ERR__OpenCode permissions have not been verified against the active service')
        return
    }
    if ([string]::IsNullOrWhiteSpace($AgentId) -or [string]::IsNullOrWhiteSpace($ProviderId) -or
        [string]::IsNullOrWhiteSpace($Model)) {
        $Queue.Enqueue('__ERR__OpenCode agent and model must be selected before sending')
        return
    }
    if (-not (Test-SlopOpenCodeServiceUrl -BaseUrl $BaseUrl)) {
        $Queue.Enqueue('__ERR__OpenCode service must use loopback http')
        return
    }
    $sessionId = $SessionId
    $cts = [Threading.CancellationTokenSource]::CreateLinkedTokenSource($Token)
    $client = $null; $resp = $null; $stream = $null; $reader = $null
    try {
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

        # 1. create a session only on the first turn; reuse it afterwards
        if (-not $sessionId) {
            $req = [Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/api/session")
            $req.Content = [Net.Http.StringContent]::new('{}', [Text.Encoding]::UTF8, 'application/json')
            foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
            $resp = $client.SendAsync($req, $Token).GetAwaiter().GetResult()
            if (-not $resp.IsSuccessStatusCode) { $Queue.Enqueue("__ERR__HTTP $([int]$resp.StatusCode)"); return }
            # POST /api/session returns { data: { id, ... } } — not a bare session object.
            $sessionJson = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            $sessionId = $sessionJson.data.id
            if (-not $sessionId) { $Queue.Enqueue('__ERR__OpenCode session create returned no id'); return }
            $Queue.Enqueue("__OCSESSION__$sessionId")
            $resp.Dispose(); $resp = $null
        }

        # 2. pin the dedicated agent — fail closed if the switch does not succeed
        $agentBody = @{ agent = $AgentId } | ConvertTo-Json -Depth 4 -Compress
        $req = [Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/api/session/$([uri]::EscapeDataString($sessionId))/agent")
        $req.Content = [Net.Http.StringContent]::new($agentBody, [Text.Encoding]::UTF8, 'application/json')
        foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
        $resp = $client.SendAsync($req, $Token).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { $Queue.Enqueue('__ERR__OpenCode agent switch failed'); return }
        $resp.Dispose(); $resp = $null

        # 2b. apply the provider/model used by the route badge on this session.
        # OpenCode takes providerID and modelID separately; model references may
        # also arrive in the canonical provider/model form.
        $modelProviderId = $ProviderId
        $modelId = $Model
        if ($Model -match '^([^/]+)/(.+)$') {
            $modelProviderId = $Matches[1]
            $modelId = $Matches[2]
        }
        $modelBody = @{ providerID = $modelProviderId; modelID = $modelId } | ConvertTo-Json -Depth 4 -Compress
        $req = [Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/api/session/$([uri]::EscapeDataString($sessionId))/model")
        $req.Content = [Net.Http.StringContent]::new($modelBody, [Text.Encoding]::UTF8, 'application/json')
        foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
        $resp = $client.SendAsync($req, $Token).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { $Queue.Enqueue('__ERR__OpenCode model switch failed'); return }
        $resp.Dispose(); $resp = $null

        # 3. subscribe BEFORE prompting — SSE has no replay
        $qs = ($EventTypes | ForEach-Object { "types=$([uri]::EscapeDataString($_))" }) -join '&'
        $req = [Net.Http.HttpRequestMessage]::new('GET', "$BaseUrl/api/event?$qs")
        foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
        $resp = $client.SendAsync($req, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $Token).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { $Queue.Enqueue("__ERR__HTTP $([int]$resp.StatusCode)"); return }
        $Queue.Enqueue('__CONNECTED__')
        $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = New-Object IO.StreamReader($stream)

        # 4. prompt (only new user text — no 12-message resend)
        if (-not $PromptBody.StartsWith('{')) { throw 'prompt body is not JSON' }
        $req = [Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/api/session/$([uri]::EscapeDataString($sessionId))/prompt")
        $req.Content = [Net.Http.StringContent]::new($PromptBody, [Text.Encoding]::UTF8, 'application/json')
        foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
        $promptResp = $client.SendAsync($req, $Token).GetAwaiter().GetResult()
        if (-not $promptResp.IsSuccessStatusCode) { $Queue.Enqueue("__ERR__HTTP $([int]$promptResp.StatusCode)"); return }
        $promptResp.Dispose()

        # 5. normalized event loop (token-aware ReadLineAsync lives in the module)
        $stats = Read-SlopOpenCodeSse -Reader $reader -Queue $Queue -SessionID $sessionId -AllowedTypes $EventTypes -Cts $cts
        if ($stats.Cancelled) { $Queue.Enqueue('__ERR__Cancelled') }
        elseif ($stats.Malformed -gt 0 -and $stats.Events -eq 0) { $Queue.Enqueue("__ERR__Malformed stream ($($stats.Malformed) event(s))") }
        elseif ($stats.Malformed -gt 0) { $Queue.Enqueue("__WARN__$($stats.Malformed) malformed event(s)") }
    }
    catch [System.Threading.Tasks.TaskCanceledException] {
        if ($Token.IsCancellationRequested) { $Queue.Enqueue('__ERR__Cancelled') } else { $Queue.Enqueue("__ERR__Timeout $TimeoutSeconds") }
    }
    catch [System.OperationCanceledException] { $Queue.Enqueue('__ERR__Cancelled') }
    catch { $Queue.Enqueue("__ERR__$($_.Exception.Message)") }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($resp) { $resp.Dispose() }
        if ($client) { $client.Dispose() }
        $cts.Dispose()
        # __DONE__ is owned by the thin dispatcher, not the adapter.
    }
}

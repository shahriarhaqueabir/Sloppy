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

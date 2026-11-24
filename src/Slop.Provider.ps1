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
        [object[]]$History = @(),
        [int]$MaxLength = 8000
    )
    if ($UserText.Length -gt $MaxLength) { throw "prompt exceeds $MaxLength characters" }
    $messages = [Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
        $messages.Add(@{ role = 'system'; content = $SystemPrompt })
    }
    foreach ($item in @($History | Select-Object -Last 24)) {
        $role = [string]$item.role
        $content = [string]$item.content
        if ($role -notin @('user','assistant')) { throw 'history role must be user or assistant' }
        if ($content.Length -gt $MaxLength) { throw "history message exceeds $MaxLength characters" }
        $messages.Add(@{ role = $role; content = $content })
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

# Part B supersedes the original SLOP_ADAPTER escape hatch: route selection now
# comes from config, and OpenCode is a first-class opt-in route.
function Get-SlopStreamPlan {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserText,
        [string]$PersonaText = '',
        [object[]]$History = @(),
        [string]$ObservedProviderEndpointUrl = '',
        [hashtable]$OpenCodePermissionEvidence,
        [System.Diagnostics.Process]$LocalModelProcess,
        [Parameter(Mandatory)][string]$ScriptRootPath,
        [Parameter(Mandatory)][string]$RepoRootPath
    )
    . (Join-Path $PSScriptRoot 'Slop.Route.ps1')
    return Get-SlopRoutePlan -Config $Config -UserText $UserText -PersonaText $PersonaText `
        -History $History -ObservedProviderEndpointUrl $ObservedProviderEndpointUrl `
        -OpenCodePermissionEvidence $OpenCodePermissionEvidence `
        -LocalModelProcess $LocalModelProcess `
        -ScriptRootPath $ScriptRootPath -RepoRootPath $RepoRootPath
}

# S.L.O.P. motion math. Pure math only - no WPF types, safe to dot-source headlessly.
$ErrorActionPreference = 'Stop'

if (-not ('SlopSpring' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
public sealed class SlopSpring
{
    public double Value;
    public double Velocity;
    public double Target;
    public double Stiffness = 160.0;
    public double Damping = 20.0;

    public SlopSpring() { }
    public SlopSpring(double value) { Value = value; Target = value; }

    public void Step(double dt)
    {
        double accel = (Target - Value) * Stiffness - Velocity * Damping;
        Velocity += accel * dt;
        Value += Velocity * dt;
    }

    public void Snap(double value)
    {
        Value = value;
        Target = value;
        Velocity = 0.0;
    }
}
'@
}

$SlopColors = @{
    idle     = '#3B82F6'
    thinking = '#F59E0B'
    working  = '#22C55E'
    success  = '#22C55E'
    error    = '#EF4444'
}
$SlopShapeIndex = @{ circle = 0; square = 1; triangle = 2; rect = 3 }

function New-SlopSpring {
    param(
        [double]$Value = 0.0,
        [double]$Stiffness = 160.0,
        [double]$Damping = 20.0
    )
    $s = [SlopSpring]::new()
    $s.Snap($Value)
    $s.Stiffness = $Stiffness
    $s.Damping = $Damping
    return $s
}

function Step-SlopSpring {
    param(
        [Parameter(Mandatory)][SlopSpring]$Spring,
        [Parameter(Mandatory)][double]$Dt
    )
    $Spring.Step($Dt)
    return $Spring.Value
}

function New-SlopMotionState {
    return @{
        Squash      = New-SlopSpring 1.0 150 18   # ScaleY; ScaleX is its inverse
        Lean        = New-SlopSpring 0.0 90 14    # degrees
        Puff        = New-SlopSpring 1.0 120 16   # breathing / success pulse
        Wobble      = New-SlopSpring 0.0 210 12   # landing jelly
        ShadowScale = New-SlopSpring 1.0 160 18
        ShadowAlpha = New-SlopSpring 0.40 140 18
        FrameScale  = New-SlopSpring 1.0 190 19
        FrameAlpha  = New-SlopSpring 0.0 260 28
        Open        = New-SlopSpring 0.0 150 19   # 0 = compact pea, 1 = expanded body
        OpenPulse   = New-SlopSpring 0.0 200 16   # streaming / success body pulse
        MoodPulse   = New-SlopSpring 0.0 170 13
        Weights     = @(
            New-SlopSpring 1.0 110 17
            New-SlopSpring 0.0 110 17
            New-SlopSpring 0.0 110 17
            New-SlopSpring 0.0 110 17
        )
        Phase       = 'idle'   # idle | anticipate | airborne | land
        PhaseTime   = 0.0
        NextHopIn   = 1.6
        Y           = 0.0
        VY          = 0.0
        HopCount    = 0
        WanderDx    = 0.0
        FaceExpression = 'scattered'
        TargetShape = 0
        Mood        = 'idle'
        Signal      = @{
            Color          = 'idle'
            Shape          = 'circle'
            BaseState      = 'idle'
            Streaming      = $false
            ChatOpen       = $false
            Stalled        = $false
            Events         = @{}
            HoldRemaining  = 0.0
            State          = 'idle'
            Status         = 'Ready'
            Source         = 'baseline'
            Priority       = 7
            AppliedColor   = 'idle'
            AppliedShape   = 'circle'
            AppliedState   = 'idle'
            AppliedStatus  = 'Ready'
        }
    }
}

function Set-SlopMotionMood {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [ValidateSet('idle','thinking','success','error')][string]$Mood
    )
    $State.Mood = $Mood
    if ($Mood -in @('success','error')) {
        $State.MoodPulse.Value = 1.0
        $State.MoodPulse.Velocity = 0.0
        $State.MoodPulse.Target = 0.0
    }
    else {
        $State.MoodPulse.Snap(0.0)
    }
}

function Set-SlopFrameTarget {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [ValidateSet('open','closed')][string]$Target
    )
    if ($Target -eq 'open') {
        $State.FrameAlpha.Target = 1.0
        $State.FrameScale.Target = 1.0
        $State.Open.Target = 1.0
    }
    else {
        $State.FrameAlpha.Target = 0.0
        $State.FrameScale.Target = 0.94
        $State.Open.Target = 0.0
    }
}

function Set-SlopBaseCondition {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][bool]$Streaming,
        [Parameter(Mandatory)][bool]$ChatOpen,
        [Parameter(Mandatory)][bool]$Stalled
    )
    $sig = $State.Signal
    $sig.Streaming = $Streaming
    $sig.ChatOpen = $ChatOpen
    $sig.Stalled = $Stalled
    $sig.BaseState = if ($Streaming) { 'working' } elseif ($ChatOpen) { 'chat-open' } else { 'idle' }
}

function Clear-SlopSignal {
    param([Parameter(Mandatory)][hashtable]$State)
    $sig = $State.Signal
    $sig.Events.Clear()
    $sig.HoldRemaining = 0.0
    $null = Get-SlopSignal -State $State
}

function Clear-SlopSignalEvent {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$Id
    )
    $removed = $State.Signal.Events.Remove($Id)
    $null = Get-SlopSignal -State $State
    return $removed
}

function Clear-SlopSignalEvents {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$Prefix
    )
    foreach ($id in @($State.Signal.Events.Keys)) {
        if ($id.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $State.Signal.Events.Remove($id) | Out-Null
        }
    }
    $null = Get-SlopSignal -State $State
}

function Set-SlopSignalEvent {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)]
        [ValidateSet('approval','critical','stalled','warning','thinking','working','tool','success','error','cancelled','idle')]
        [string]$Kind,
        [string]$Status = '',
        [double]$DurationSeconds = 0.0,
        [switch]$Sticky,
        [switch]$Transient
    )

    $definition = switch ($Kind) {
        'approval'  { @{ Color = 'thinking'; Shape = 'rect'; Priority = 0; Sticky = $true; DefaultDuration = 0.0 } }
        'critical'  { @{ Color = 'error'; Shape = 'rect'; Priority = 1; Sticky = $true; DefaultDuration = 0.0 } }
        'stalled'   { @{ Color = 'thinking'; Shape = 'rect'; Priority = 2; Sticky = $true; DefaultDuration = 0.0 } }
        'warning'   { @{ Color = 'thinking'; Shape = 'rect'; Priority = 3; Sticky = $false; DefaultDuration = 6.0 } }
        'thinking'  { @{ Color = 'thinking'; Shape = 'circle'; Priority = 4; Sticky = $false; DefaultDuration = 0.0 } }
        'working'   { @{ Color = 'working'; Shape = 'triangle'; Priority = 4; Sticky = $false; DefaultDuration = 0.0 } }
        'tool'      { @{ Color = 'working'; Shape = 'triangle'; Priority = 4; Sticky = $false; DefaultDuration = 0.0 } }
        'success'   { @{ Color = 'success'; Shape = 'square'; Priority = 1; Sticky = $false; DefaultDuration = 1.5 } }
        'error'     { @{ Color = 'error'; Shape = 'rect'; Priority = 1; Sticky = $false; DefaultDuration = 2.0 } }
        'cancelled' { @{ Color = 'idle'; Shape = 'circle'; Priority = 6; Sticky = $false; DefaultDuration = 1.5 } }
        'idle'      { @{ Color = 'idle'; Shape = 'circle'; Priority = 7; Sticky = $false; DefaultDuration = 0.0 } }
    }

    $isSticky = if ($Transient) { $false } else { $Sticky.IsPresent -or $definition.Sticky }
    $duration = if ($DurationSeconds -gt 0) { $DurationSeconds } else { $definition.DefaultDuration }
    $remainingSeconds = $null
    if (-not $isSticky -and $duration -gt 0) { $remainingSeconds = $duration }
    $sig = $State.Signal
    $sig.Events[$Id] = @{
        Id = $Id
        Kind = $Kind
        Color = $definition.Color
        Shape = $definition.Shape
        Priority = $definition.Priority
        Status = if ($Status) { $Status } else { $Kind }
        Sticky = $isSticky
        RemainingSeconds = $remainingSeconds
        CreatedAt = [DateTime]::UtcNow
    }
    $null = Get-SlopSignal -State $State
}

function Set-SlopSignal {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [ValidateSet('idle','thinking','working','success','error')][string]$Color,
        [ValidateSet('circle','square','triangle','rect')][string]$Shape,
        [double]$HoldSeconds = 0.0
    )
    $kind = switch ($Color) {
        'thinking' { 'thinking' }
        'working'  { 'working' }
        'success'  { 'success' }
        'error'    { 'error' }
        'idle'     { 'idle' }
    }
    # Compatibility adapter for existing call sites. New callers should use
    # Set-SlopSignalEvent so the event has an explicit identity and lifetime.
    $id = "legacy:$kind"
    Set-SlopSignalEvent -State $State -Id $id `
        -Kind $kind -Status $kind -DurationSeconds $HoldSeconds `
        -Sticky:($HoldSeconds -le 0) -Transient:($HoldSeconds -gt 0)
    $State.Signal.Events[$id].Color = $Color
    $State.Signal.Events[$id].Shape = $Shape
    $null = Get-SlopSignal -State $State
}

function Get-SlopSignal {
    param([Parameter(Mandatory)][hashtable]$State)
    $sig = $State.Signal

    $base = switch ($sig.BaseState) {
        'working' {
            if ($sig.Stalled) {
                @{ Id = 'base:stalled'; Kind = 'stalled'; Color = 'thinking'; Shape = 'rect'; Priority = 2; Status = 'No response yet'; Source = 'request'; CreatedAt = [DateTime]::MinValue }
            } else {
                @{ Id = 'base:working'; Kind = 'working'; Color = 'working'; Shape = 'triangle'; Priority = 4; Status = 'Working'; Source = 'request'; CreatedAt = [DateTime]::MinValue }
            }
        }
        'chat-open' { @{ Id = 'base:chat-open'; Kind = 'chat-open'; Color = 'idle'; Shape = 'square'; Priority = 7; Status = 'Chat open'; Source = 'baseline'; CreatedAt = [DateTime]::MinValue } }
        default     { @{ Id = 'base:idle'; Kind = 'idle'; Color = 'idle'; Shape = 'circle'; Priority = 7; Status = 'Ready'; Source = 'baseline'; CreatedAt = [DateTime]::MinValue } }
    }

    $winner = $base
    foreach ($event in $sig.Events.Values) {
        if (-not $event.Sticky -and $event.RemainingSeconds -le 0) { continue }
        if ($event.Priority -lt $winner.Priority -or
            ($event.Priority -eq $winner.Priority -and $event.CreatedAt -gt $winner.CreatedAt)) {
            $winner = $event
        }
    }
    $remaining = 0.0
    foreach ($event in $sig.Events.Values) {
        if (-not $event.Sticky -and $event.RemainingSeconds -gt 0) {
            $remaining = [Math]::Max($remaining, $event.RemainingSeconds)
        }
    }
    $sig.HoldRemaining = $remaining
    $sig.State = $winner.Kind
    $sig.Color = $winner.Color
    $sig.Shape = $winner.Shape
    $sig.Status = $winner.Status
    $sig.Source = if ($winner.ContainsKey('Source')) { $winner.Source } else { 'event' }
    $sig.Priority = $winner.Priority
    return @{
        Id = $winner.Id; Kind = $winner.Kind; Color = $winner.Color; Shape = $winner.Shape
        Priority = $winner.Priority; Status = $winner.Status; Source = $sig.Source
    }
}

function Update-SlopSignal {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][double]$Dt
    )
    $sig = $State.Signal
    foreach ($id in @($sig.Events.Keys)) {
        $event = $sig.Events[$id]
        if (-not $event.Sticky) {
            $event.RemainingSeconds -= $Dt
        }
        if (-not $event.Sticky -and $event.RemainingSeconds -le 0) {
            $sig.Events.Remove($id) | Out-Null
        }
    }
    $null = Get-SlopSignal -State $State
}

function Set-SlopTargetShape {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [ValidateSet('circle','square','triangle','rect')][string]$Shape
    )
    $idx = $SlopShapeIndex[$Shape]
    if ($State.TargetShape -eq $idx) { return }
    $State.TargetShape = $idx
    for ($i = 0; $i -lt 4; $i++) {
        $State.Weights[$i].Target = if ($i -eq $idx) { 1.0 } else { 0.0 }
    }
    if ($State.Phase -eq 'idle') { $State.NextHopIn = -1.0 }
}

function Sync-SlopSignal {
    param([Parameter(Mandatory)][hashtable]$State)
    $sig = $State.Signal
    $effective = Get-SlopSignal -State $State
    if ($sig.AppliedColor -eq $effective.Color -and $sig.AppliedShape -eq $effective.Shape -and
        $sig.AppliedState -eq $effective.Kind -and $sig.AppliedStatus -eq $effective.Status) {
        return $null
    }
    $sig.AppliedColor = $effective.Color
    $sig.AppliedShape = $effective.Shape
    $sig.AppliedState = $effective.Kind
    $sig.AppliedStatus = $effective.Status
    Set-SlopTargetShape -State $State -Shape $effective.Shape
    return $effective
}

function Get-SlopIdleAction {
    param([Parameter(Mandatory)][double]$NextHopIn)
    # -0.5, not -0.005: at 30 fps a naturally expiring timer lands near -0.033,
    # so a -0.005 threshold made the forced hop swallow almost every random
    # action. Only explicit hop requests (Set-SlopTargetShape / tests) use a
    # value this negative; ordinary expiry must roll for real variety.
    if ($NextHopIn -le -0.5) { return 'anticipate' }
    $roll = Get-Random -Minimum 0 -Maximum 100
    if     ($roll -lt 22) { return 'anticipate' }
    elseif ($roll -lt 36) { return 'sit' }
    elseif ($roll -lt 48) { return 'stretch' }
    elseif ($roll -lt 60) { return 'wander' }
    elseif ($roll -lt 74) { return 'blink' }
    elseif ($roll -lt 84) { return 'tilt' }
    elseif ($roll -lt 92) { return 'bounce' }
    elseif ($roll -lt 97) { return 'peek' }
    else                  { return 'yawn' }
}

function Complete-SlopIdleAction {
    param([Parameter(Mandatory)][hashtable]$State)
    $State.Phase = 'idle'
    $State.PhaseTime = 0.0
    $State.Squash.Target = 1.0
    $State.Puff.Target = 1.0
    $State.Lean.Target = 0.0
    $State.Wobble.Target = 0.0
    $State.ShadowScale.Target = 1.0
    $State.ShadowAlpha.Target = 0.40
    $State.FaceExpression = 'scattered'
    $State.NextHopIn = 1.0 + (Get-Random -Minimum 0 -Maximum 200) / 100.0
}

function Update-SlopMotionState {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][double]$Dt,
        [switch]$ReducedMotion
    )

    Update-SlopSignal -State $State -Dt $Dt

    $allSprings = @(
        $State.Squash, $State.Lean, $State.Puff, $State.Wobble,
        $State.ShadowScale, $State.ShadowAlpha,
        $State.FrameScale, $State.FrameAlpha, $State.MoodPulse,
        $State.Open, $State.OpenPulse
    )
    $t = [DateTime]::UtcNow.Ticks / 10000000.0

    if ($ReducedMotion) {
        foreach ($s in $allSprings) { $s.Snap($s.Target) }
        foreach ($w in $State.Weights) { $w.Snap($w.Target) }
        $State.Y = 0.0
        $State.VY = 0.0
        return
    }

    $State.PhaseTime += $Dt
    $State.NextHopIn -= $Dt

    switch ($State.Phase) {
        'idle' {
            $State.Squash.Target = 1.0
            $State.FaceExpression = 'scattered'
            if ($State.Mood -eq 'thinking') {
                $State.Lean.Target = 3.5 * [Math]::Sin($t * 6.2)
                $State.Wobble.Target = 0.045 * [Math]::Sin($t * 9.1)
            }
            if ($State.Mood -eq 'idle' -and $State.Open.Value -lt 0.1 -and $State.NextHopIn -le 0) {
                $action = Get-SlopIdleAction -NextHopIn $State.NextHopIn
                $State.Phase = $action
                $State.PhaseTime = 0.0
                switch ($action) {
                    'anticipate' { $State.Squash.Target = 0.80; $State.ShadowScale.Target = 0.82 }
                    'sit'        { $State.Squash.Target = 0.85; $State.FaceExpression = 'cluster' }
                    'stretch'    { $State.Squash.Target = 1.15; $State.Puff.Target = 1.08; $State.FaceExpression = 'line' }
                    'yawn'       { $State.Squash.Target = 1.12; $State.Lean.Target = -6.0; $State.FaceExpression = 'ring' }
                    'blink'      { $State.Lean.Target = 4.0; $State.FaceExpression = 'line' }
                    'tilt'       { $State.FaceExpression = 'cluster' }
                    'bounce'     { $State.FaceExpression = 'ring' }
                    'peek'       { $State.Lean.Target = -5.0; $State.FaceExpression = 'spiral' }
                    'wander'     { $State.WanderDx = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { -30.0 } else { 30.0 } }
                }
            }
        }
        'anticipate' {
            if ($State.PhaseTime -ge 0.12) {
                $State.Phase = 'airborne'
                $State.PhaseTime = 0.0
                $State.Y = 0.0
                $State.VY = -165.0
                $State.FaceExpression = 'ring'
            }
        }
        'airborne' {
            $State.VY += 620.0 * $Dt
            $State.Y += $State.VY * $Dt
            if ($State.Y -ge 0 -and $State.VY -gt 0) {
                $State.Y = 0.0
                $State.Phase = 'land'
                $State.PhaseTime = 0.0
                $State.Squash.Target = 0.76
                $State.Wobble.Target = 0.14
                $State.ShadowScale.Target = 1.16
                $State.ShadowAlpha.Target = 0.55
                $State.FaceExpression = 'ring'
                if ($State.Mood -ne 'thinking') { $State.Lean.Target = 0.0 }
            }
        }
        'land' {
            if ($State.PhaseTime -ge 0.10) {
                Complete-SlopIdleAction -State $State
                $State.HopCount++
            }
        }
        'sit'     { if ($State.PhaseTime -ge 1.8) { Complete-SlopIdleAction -State $State } }
        'stretch' { if ($State.PhaseTime -ge 1.2) { Complete-SlopIdleAction -State $State } }
        'wander'  { if ($State.PhaseTime -ge 3.0) { Complete-SlopIdleAction -State $State } }
        'blink'   { if ($State.PhaseTime -ge 0.35) { Complete-SlopIdleAction -State $State } }
        'tilt' {
            $State.Lean.Target = 7.0 * [Math]::Sin($State.PhaseTime * 5.0)
            if ($State.PhaseTime -ge 0.9) { Complete-SlopIdleAction -State $State }
        }
        'bounce' {
            $State.Squash.Target = 1.0 + 0.12 * [Math]::Sin($State.PhaseTime * 14.0)
            if ($State.PhaseTime -ge 0.8) { Complete-SlopIdleAction -State $State }
        }
        'peek' { if ($State.PhaseTime -ge 0.7) { Complete-SlopIdleAction -State $State } }
        'yawn' { if ($State.PhaseTime -ge 1.2) { Complete-SlopIdleAction -State $State } }
    }

    # Micro-motion never stops: breathing in all phases, sway except where a
    # phase owns the lean (tilt/peek/yawn) or an error pulse owns it.
    if ($State.Mood -notin @('thinking','error') -and $State.Phase -ne 'stretch') {
        $State.Puff.Target = 1.0 + 0.018 * [Math]::Sin($t * 2.1)
    }
    if ($State.Mood -notin @('thinking','error','success') -and
        $State.Phase -notin @('tilt','peek','yawn','airborne','land')) {
        $State.Lean.Target = 1.2 * [Math]::Sin($t * 0.5)
    }

    if ($State.Mood -eq 'error') {
        $State.Lean.Target = 7.0 * $State.MoodPulse.Value * [Math]::Sin($t * 42.0)
    }
    elseif ($State.Mood -eq 'success') {
        $State.Puff.Target += 0.10 * $State.MoodPulse.Value
    }

    if ($State.Signal.Streaming) {
        $State.OpenPulse.Target = 0.05 + 0.03 * [Math]::Sin($t * 5.0)
    }
    elseif ($State.Mood -eq 'success') {
        $State.OpenPulse.Target = 0.10 * $State.MoodPulse.Value
    }
    else {
        $State.OpenPulse.Target = 0.0
    }

    foreach ($s in $allSprings) { $s.Step($Dt) }
    foreach ($w in $State.Weights) { $w.Step($Dt) }
}

function Test-SlopClientAreaAnimation {
    if (-not ('SlopNativeMotion' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SlopNativeMotion
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, out bool value, uint flags);
}
'@
    }
    $enabled = $false
    [SlopNativeMotion]::SystemParametersInfo(0x1042, 0, [ref]$enabled, 0) | Out-Null
    return $enabled
}

function Test-SlopMotionActive {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [switch]$WindowMoving
    )
    $sig = $State.Signal
    if ($sig.Streaming) { return $true }
    if ($sig.HoldRemaining -gt 0.0) { return $true }
    foreach ($event in $sig.Events.Values) {
        if ($event.Sticky -or $event.Priority -le 3) { return $true }
    }
    if ($State.Mood -ne 'idle') { return $true }
    if ($State.Phase -ne 'idle') { return $true }
    if ([Math]::Abs($State.Open.Target - $State.Open.Value) -gt 0.01) { return $true }
    if ([Math]::Abs($State.Open.Velocity) -gt 0.01) { return $true }
    foreach ($w in $State.Weights) {
        if ([Math]::Abs($w.Target - $w.Value) -gt 0.01) { return $true }
    }
    if ($WindowMoving) { return $true }
    return $false
}

function Get-SlopMotionIntervalMs {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [switch]$WindowMoving,
        [switch]$Large
    )
    if (Test-SlopMotionActive -State $State -WindowMoving:$WindowMoving) { return 33 }
    if ($Large) { return 100 }
    return 66
}

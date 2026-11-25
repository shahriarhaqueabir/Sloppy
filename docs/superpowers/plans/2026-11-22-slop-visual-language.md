# S.L.O.P. Two-Axis Visual Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make color (outcome) and shape (engagement) independent, trigger-driven signals, with shape crossfades that shrink outgoing shapes and grow incoming ones.

**Architecture:** A pure signal model in `src/Slop.Motion.ps1` resolves base condition (idle / streaming / stalled / chat-open) plus a transient success/error overlay. `src/Slop.ps1` maps concrete triggers to that model once, then applies the effective color and shape to the existing pea, status dot, frame border, and a new 8 px header glyph. No new palette entries or geometries.

**Tech Stack:** PowerShell 7, WPF, embedded C# spring math, framework-free headless checks, pixel-based live verification.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/Slop.Motion.ps1` | Signal model (`Set-SlopBaseCondition`, `Set-SlopSignal`, `Get-SlopSignal`, `Update-SlopSignal`, `Sync-SlopSignal`, `Set-SlopTargetShape`) plus existing spring/hop math. No WPF types. |
| `src/Slop.ps1` | Trigger wiring, canonical shape ordering, brush management, header glyph, animated color transitions, stall detection. |
| `tests/slop-motion-check.ps1` | Headless assertions for signal table, overlays, and shape mapping. |
| `tools/verify-motion.ps1` | Live pixel/interaction verification per signal pair. |

---

### Task 1: Write failing signal checks

**Files:**
- Modify: `tests/slop-motion-check.ps1`

- [ ] **Step 1: Append the failing checks**

Append to `tests/slop-motion-check.ps1`, before the final `if ($script:failures -gt 0)` line:

```powershell
# 7. two-axis signal table
function Assert-Signal {
    param([string]$Color, [string]$Shape, [string]$Label)
    $e = Get-SlopSignal -State $m
    Assert-True ($e.Color -eq $Color -and $e.Shape -eq $Shape) `
        "$Label => $Color/$Shape (got $($e.Color)/$($e.Shape))"
}

$s = New-SlopMotionState
$script:m = $s
Set-SlopBaseCondition -State $m -Streaming $false -ChatOpen $false -Stalled $false
Assert-Signal 'idle' 'circle' 'idle'
Set-SlopBaseCondition -State $m -Streaming $false -ChatOpen $true -Stalled $false
Assert-Signal 'idle' 'square' 'chat-open changes shape only'
Set-SlopBaseCondition -State $m -Streaming $true -ChatOpen $true -Stalled $false
Assert-Signal 'thinking' 'triangle' 'streaming outranks chat-open'
Set-SlopBaseCondition -State $m -Streaming $true -ChatOpen $false -Stalled $true
Assert-Signal 'thinking' 'rect' 'stalled changes shape only'

# 8. transient overlay wins, expires, and returns to base
Set-SlopSignal -State $m -Color 'success' -Shape 'square' -HoldSeconds 1.0
Assert-Signal 'success' 'square' 'success overlay'
for ($i=0;$i -lt 150;$i++) { Update-SlopMotionState -State $m -Dt (1.0/120.0) }
Assert-Signal 'thinking' 'rect' 'overlay expires to base'

# 9. a new request pre-empts an active overlay
Set-SlopSignal -State $m -Color 'error' -Shape 'rect' -HoldSeconds 2.0
Clear-SlopSignal -State $m
Set-SlopBaseCondition -State $m -Streaming $true -ChatOpen $false -Stalled $false
Assert-Signal 'thinking' 'triangle' 'new request clears overlay'

# 10. canonical shape index mapping
Set-SlopTargetShape -State $m -Shape 'rect'
Assert-True ($m.TargetShape -eq 3 -and $m.Weights[3].Target -eq 1.0 -and $m.Weights[0].Target -eq 0.0) `
    'canonical shape index maps rect to weights[3]'
```

Note: the earlier checks use `$m = New-SlopMotionState`; this appended block intentionally reassigns `$m` after those checks have finished, so it does not disturb them.

- [ ] **Step 2: Run checks to verify they fail**

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: FAIL after the earlier PASS lines with `The term 'Get-SlopSignal' is not recognized` (or equivalent unknown-command error).

- [ ] **Step 3: Commit the failing checks**

```bash
git add tests/slop-motion-check.ps1
git commit -m "test: add two-axis signal table checks"
```

---

### Task 2: Implement the signal model

**Files:**
- Modify: `src/Slop.Motion.ps1`

- [ ] **Step 1: Add signal constants and state fields**

Insert after the `Add-Type` block:

```powershell
$SlopColors = @{
    idle    = '#3B82F6'
    thinking= '#F59E0B'
    success = '#22C55E'
    error   = '#EF4444'
}
$SlopShapeIndex = @{ circle = 0; square = 1; triangle = 2; rect = 3 }
```

Add these entries inside the hashtable returned by `New-SlopMotionState`, immediately after `Mood = 'idle'`:

```powershell
        Signal = @{
            Color           = 'idle'
            Shape           = 'circle'
            Streaming       = $false
            ChatOpen        = $false
            Stalled         = $false
            TransientColor  = $null
            TransientShape  = $null
            HoldRemaining   = 0.0
            AppliedColor    = 'idle'
            AppliedShape    = 'circle'
        }
```

- [ ] **Step 2: Add the signal functions**

Insert after `Set-SlopFrameTarget`:

```powershell
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
    # IMPORTANT: base changes must never clear a transient overlay. Finish-Stream and
    # every 40 ms drain tick call this; clearing here would erase success/error instantly.
    if ($Streaming) {
        $sig.Color = 'thinking'
        $sig.Shape = if ($Stalled) { 'rect' } else { 'triangle' }
    }
    else {
        $sig.Color = 'idle'
        $sig.Shape = if ($ChatOpen) { 'square' } else { 'circle' }
    }
}

function Clear-SlopSignal {
    param([Parameter(Mandatory)][hashtable]$State)
    $sig = $State.Signal
    $sig.TransientColor = $null
    $sig.TransientShape = $null
    $sig.HoldRemaining = 0.0
}

function Set-SlopSignal {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [ValidateSet('idle','thinking','success','error')][string]$Color,
        [ValidateSet('circle','square','triangle','rect')][string]$Shape,
        [double]$HoldSeconds = 0.0
    )
    $sig = $State.Signal
    if ($HoldSeconds -gt 0) {
        $sig.TransientColor = $Color
        $sig.TransientShape = $Shape
        $sig.HoldRemaining = $HoldSeconds
    }
    else {
        $sig.TransientColor = $null
        $sig.TransientShape = $null
        $sig.HoldRemaining = 0.0
        $sig.Color = $Color
        $sig.Shape = $Shape
    }
}

function Get-SlopSignal {
    param([Parameter(Mandatory)][hashtable]$State)
    $sig = $State.Signal
    if ($sig.HoldRemaining -gt 0 -and $sig.TransientColor) {
        return @{ Color = $sig.TransientColor; Shape = $sig.TransientShape }
    }
    return @{ Color = $sig.Color; Shape = $sig.Shape }
}

function Update-SlopSignal {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][double]$Dt
    )
    $sig = $State.Signal
    if ($sig.HoldRemaining -gt 0) {
        $sig.HoldRemaining -= $Dt
        if ($sig.HoldRemaining -le 0) {
            $sig.HoldRemaining = 0.0
            $sig.TransientColor = $null
            $sig.TransientShape = $null
        }
    }
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
    if ($State.Phase -eq 'idle') { $State.NextHopIn = 0.0 }
}

function Sync-SlopSignal {
    param([Parameter(Mandatory)][hashtable]$State)
    $sig = $State.Signal
    $effective = Get-SlopSignal -State $State
    if ($sig.AppliedColor -eq $effective.Color -and $sig.AppliedShape -eq $effective.Shape) {
        return $null
    }
    $sig.AppliedColor = $effective.Color
    $sig.AppliedShape = $effective.Shape
    Set-SlopTargetShape -State $State -Shape $effective.Shape
    return $effective
}
```

- [ ] **Step 3: Remove random idle morphing and tick the signal**

In `Update-SlopMotionState`, immediately before `$allSprings = @(` add:

```powershell
    Update-SlopSignal -State $State -Dt $Dt
```

In the `'anticipate'` branch, replace:

```powershell
                $State.TargetShape = ($State.TargetShape + 1 + (Get-Random -Maximum 3)) % 4
                for ($i = 0; $i -lt 4; $i++) {
                    $State.Weights[$i].Target = if ($i -eq $State.TargetShape) { 1.0 } else { 0.0 }
                }
```

with an empty block (delete those five lines). The hop now only performs the squat/air/land motion; target shape changes come from `Sync-SlopSignal`.

- [ ] **Step 4: Run headless checks**

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: all `PASS:` lines and `ALL MOTION CHECKS PASSED`.

- [ ] **Step 5: Commit the model**

```bash
git add src/Slop.Motion.ps1
git commit -m "feat: add two-axis signal model"
```

---

### Task 3: Wire triggers, canonical shapes, and the header glyph

**Files:**
- Modify: `src/Slop.ps1` (XAML header, `FindName` block, `script:Shapes`, `Set-SlopMood`, `Initialize-MotionVisuals`, `Apply-SlopMotion`, `Expand-Chat`, `Collapse-Chat`, `Start-Stream`, drain timer, `Finish-Stream`, startup).

- [ ] **Step 1: Add the header shape glyph to XAML**

Replace the header block from `<Border x:Name="DragHandle"...` through the `TextBlock Text="S.L.O.P."...` line with:

```xml
        <Border x:Name="DragHandle" Grid.Row="0" Background="Transparent" Cursor="SizeAll"/>
        <Canvas x:Name="ShapeGlyph" Width="8" Height="8" HorizontalAlignment="Left"
                VerticalAlignment="Center" Margin="10,0,0,0" IsHitTestVisible="False">
          <Ellipse x:Name="GlyphCircle" Width="8" Height="8" Fill="#3B82F6" Visibility="Visible"/>
          <Rectangle x:Name="GlyphSquare" Width="8" Height="8" Fill="#3B82F6" Visibility="Collapsed"/>
          <Polygon x:Name="GlyphTri" Points="4,0 8,8 0,8" Fill="#3B82F6" Visibility="Collapsed"/>
          <Rectangle x:Name="GlyphRect" Width="8" Height="6" Canvas.Top="1" Fill="#3B82F6" Visibility="Collapsed"/>
        </Canvas>
        <Rectangle x:Name="StatusDot" Width="8" Height="8" Fill="#3B82F6"
                   HorizontalAlignment="Left" VerticalAlignment="Center" Margin="22,0,0,0"
                   IsHitTestVisible="False"/>
        <TextBlock Text="S.L.O.P." Foreground="#EAEAEA" FontWeight="Bold" FontSize="13"
                   VerticalAlignment="Center" Margin="38,0" IsHitTestVisible="False"/>
```

- [ ] **Step 2: Find glyph elements and use canonical shape order**

After `$GroundShadow = $window.FindName('GroundShadow')` add:

```powershell
$GlyphCircle = $window.FindName('GlyphCircle')
$GlyphSquare = $window.FindName('GlyphSquare')
$GlyphTri = $window.FindName('GlyphTri')
$GlyphRect = $window.FindName('GlyphRect')
$script:GlyphShapes = @($GlyphCircle, $GlyphSquare, $GlyphTri, $GlyphRect)
```

Replace line 148:

```powershell
$script:Shapes = @($ShapeSquare,$ShapeCircle,$ShapeTri,$ShapeRect)
```

with:

```powershell
# canonical order matches $SlopShapeIndex: circle, square, triangle, rect
$script:Shapes = @($ShapeCircle,$ShapeSquare,$ShapeTri,$ShapeRect)
```

- [ ] **Step 3: Replace `Set-SlopMood` with signal-to-visual application**

Replace the whole `Set-SlopMood` function with:

```powershell
function Set-SlopVisualFromSignal {
    param([Parameter(Mandatory)][hashtable]$Signal)
    $new = [System.Windows.Media.BrushConverter]::new().ConvertFromString($SlopColors[$Signal.Color]).Color
    foreach ($b in $script:ColorBrushes) { $b.Color = $new }
    $idx = $SlopShapeIndex[$Signal.Shape]
    for ($i = 0; $i -lt 4; $i++) {
        $script:GlyphShapes[$i].Visibility = if ($i -eq $idx) { 'Visible' } else { 'Collapsed' }
    }
}
```

- [ ] **Step 4: Initialize unique brushes in `Initialize-MotionVisuals`**

Replace the whole `Initialize-MotionVisuals` function with:

```powershell
function Initialize-MotionVisuals {
    $Frame.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $Frame.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1,1)
    $GroundShadow.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $GroundShadow.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1,1)
    $PeaCanvas.RenderTransform = [System.Windows.Media.TranslateTransform]::new(0,0)

    $initial = [System.Windows.Media.BrushConverter]::new().ConvertFromString($SlopColors['idle']).Color
    $script:ColorBrushes = @()
    foreach ($shape in $script:Shapes) {
        $shape.Fill = [System.Windows.Media.SolidColorBrush]::new($initial)
        $script:ColorBrushes += $shape.Fill
    }
    $StatusDot.Fill = [System.Windows.Media.SolidColorBrush]::new($initial)
    $script:ColorBrushes += $StatusDot.Fill
    $Frame.BorderBrush = [System.Windows.Media.SolidColorBrush]::new($initial)
    $script:ColorBrushes += $Frame.BorderBrush
    foreach ($g in $script:GlyphShapes) {
        $g.Fill = [System.Windows.Media.SolidColorBrush]::new($initial)
        $script:ColorBrushes += $g.Fill
    }
}
```

- [ ] **Step 5: Sync signals and shrink shapes during crossfade**

At the top of `Apply-SlopMotion`, immediately after `$m = $script:Motion` add:

```powershell
    $changed = Sync-SlopSignal -State $script:Motion
    if ($changed) { Set-SlopVisualFromSignal -Signal $changed }
```

Replace these two lines inside the shape loop:

```powershell
        $g.Children[0].ScaleX = $sx * $m.Puff.Value
        $g.Children[0].ScaleY = $sy * $m.Puff.Value
```

with:

```powershell
        # fade and shrink together: outgoing shape collapses as it disappears
        $g.Children[0].ScaleX = $sx * $m.Puff.Value * $w
        $g.Children[0].ScaleY = $sy * $m.Puff.Value * $w
```

- [ ] **Step 6: Replace trigger call sites**

Replace `Set-SlopMood 'thinking'` in `Start-Stream` with:

```powershell
    Clear-SlopSignal -State $script:Motion
    Set-SlopBaseCondition -State $script:Motion -Streaming $true -ChatOpen $script:Expanded -Stalled $false
    $script:LastTokenAt = [DateTime]::UtcNow
```

`Clear-SlopSignal` here is what implements "a new request wins over an active overlay".

Replace `Set-SlopMood 'error'` in the drain error branch with:

```powershell
                Set-SlopSignal -State $script:Motion -Color 'error' -Shape 'rect' -HoldSeconds 2.0
```

Replace `Set-SlopMood 'success'` in the drain done branch with:

```powershell
                    Set-SlopSignal -State $script:Motion -Color 'success' -Shape 'square' -HoldSeconds 1.5
```

In `Finish-Stream`, after `$script:IsStreaming = $false` add:

```powershell
    Set-SlopBaseCondition -State $script:Motion -Streaming $false -ChatOpen $script:Expanded -Stalled $false
```

This updates the base to idle so the success/error overlay has something to fall back to when it expires. Do **not** add `Clear-SlopSignal` here — that would erase the overlay in the same tick it is set.

In `Expand-Chat`, after `$Frame.Opacity = 0` add:

```powershell
    Set-SlopBaseCondition -State $script:Motion -Streaming $script:IsStreaming -ChatOpen $true -Stalled $false
```

In `Collapse-Chat`, after `$script:Expanded = $false` add:

```powershell
    Set-SlopBaseCondition -State $script:Motion -Streaming $script:IsStreaming -ChatOpen $false -Stalled $false
```

Replace the startup line `Set-SlopMood 'idle'` with:

```powershell
Set-SlopBaseCondition -State $script:Motion -Streaming $false -ChatOpen $false -Stalled $false
```

- [ ] **Step 7: Add stall detection to the drain timer**

At the top of the drain `$timer.Add_Tick({` scriptblock, before `$tok = $null`, add:

```powershell
        $script:StalledNow = $script:IsStreaming -and `
            ((([DateTime]::UtcNow) - $script:LastTokenAt).TotalSeconds -gt 3)
        Set-SlopBaseCondition -State $script:Motion -Streaming $script:IsStreaming `
            -ChatOpen $script:Expanded -Stalled $script:StalledNow
```

Immediately after `$script:CurrentText += $tok` add:

```powershell
            $script:LastTokenAt = [DateTime]::UtcNow
            $script:StalledNow = $false
            Set-SlopBaseCondition -State $script:Motion -Streaming $true `
                -ChatOpen $script:Expanded -Stalled $false
```

- [ ] **Step 8: Parser + headless checks**

Run:

```powershell
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile('.\src\Slop.ps1',[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){$errors|ForEach-Object{"$($_.Extent.StartLineNumber): $($_.Message)"};exit 1}
'Parser errors: 0'
pwsh -NoProfile -File tests/slop-motion-check.ps1
```

Expected: `Parser errors: 0` and `ALL MOTION CHECKS PASSED`.

- [ ] **Step 9: Commit**

```bash
git add src/Slop.ps1
git commit -m "feat: wire visual signals into slop"
```

---

### Task 4: Animate color transitions

**Files:**
- Modify: `src/Slop.ps1`

- [ ] **Step 1: Add the color animation helper**

Insert immediately before `Set-SlopVisualFromSignal`:

```powershell
function Animate-BrushTo {
    param(
        [Parameter(Mandatory)][System.Windows.Media.SolidColorBrush]$Brush,
        [Parameter(Mandatory)][System.Windows.Media.Color]$Color
    )
    $anim = [System.Windows.Media.Animation.ColorAnimation]::new($Color, [TimeSpan]::FromMilliseconds(160))
    $anim.EasingFunction = [System.Windows.Media.Animation.CubicEase]::new()
    $Brush.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $anim)
}
```

- [ ] **Step 2: Use it in `Set-SlopVisualFromSignal`**

Replace:

```powershell
    foreach ($b in $script:ColorBrushes) { $b.Color = $new }
```

with:

```powershell
    foreach ($b in $script:ColorBrushes) { Animate-BrushTo -Brush $b -Color $new }
```

- [ ] **Step 3: Verify**

Run:

```powershell
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile('.\src\Slop.ps1',[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){$errors|ForEach-Object{"$($_.Extent.StartLineNumber): $($_.Message)"};exit 1}
'Parser errors: 0'
pwsh -NoProfile -File tests/slop-motion-check.ps1
```

Expected: `Parser errors: 0` and `ALL MOTION CHECKS PASSED`.

- [ ] **Step 4: Commit**

```bash
git add src/Slop.ps1
git commit -m "feat: animate slop color transitions"
```

---

### Task 5: Live verification and gates

**Files:**
- Modify: `tools/verify-motion.ps1`

- [ ] **Step 1: Extend the live verifier with signal checks**

Add a helper after `Pixel`:

```powershell
function CountColor($b, $mode) {
    $r = $script:W.Current.BoundingRectangle
    $s = $r.Width / 320.0
    $rect = [System.Drawing.Rectangle]::new([int](138*$s),[int](372*$s),[int](56*$s),[int](82*$s))
    $d = $b.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,$b.PixelFormat)
    $bytes = [byte[]]::new($d.Stride*$rect.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0,$bytes,0,$bytes.Length)
    $b.UnlockBits($d)
    $n=0
    for($y=0;$y -lt $rect.Height;$y++){$idx=$y*$d.Stride
        for($x=0;$x -lt $rect.Width;$x++){
            $rr=$bytes[$idx+2];$gg=$bytes[$idx+1];$bb=$bytes[$idx]
            if($mode -eq 'blue'   -and $bb -gt 180 -and $rr -lt 120 -and $gg -lt 180){$n++}
            if($mode -eq 'amber'  -and $rr -gt 200 -and $gg -gt 100 -and $gg -lt 190 -and $bb -lt 110){$n++}
            if($mode -eq 'green'  -and $gg -gt 150 -and $rr -lt 140 -and $bb -lt 160){$n++}
            if($mode -eq 'red'    -and $rr -gt 170 -and $gg -lt 100 -and $bb -lt 100){$n++}
            $idx+=4}}
    $n
}
```

Insert after the `IDLE blueSamples=...` line:

```powershell
$b = Grab; "SIGNAL idle blue=$(CountColor $b 'blue') amber=$(CountColor $b 'amber') green=$(CountColor $b 'green') red=$(CountColor $b 'red')"; $b.Dispose()
```

After `EXPAND panel=...`:

```powershell
$b = Grab; $dot = Pixel $b 26 18; "SIGNAL chat-open dot=$($dot.R),$($dot.G),$($dot.B)"; $b.Dispose()
```

Inside the streaming loop, on the first change where `$v -gt 100`, log once:

```powershell
    if ($v -gt 100 -and -not $script:loggedAmber) {
        $b = Grab; "SIGNAL thinking amber=$(CountColor $b 'amber')"; $b.Dispose()
        $script:loggedAmber = $true
    }
```

After the stream loop, before ESC:

```powershell
$b = Grab; "SIGNAL post-success green=$(CountColor $b 'green') amber=$(CountColor $b 'amber')"; $b.Dispose()
```

- [ ] **Step 2: Run all gates**

Run:

```powershell
pwsh -NoProfile -File tests/slop-motion-check.ps1
pwsh -STA -NoProfile -File tools/verify-motion.ps1
pwsh -NoProfile -File '<agent-home>/scripts/verify.ps1'
pwsh -NoProfile -File '<agent-home>/scripts/review.ps1'
```

Expected:
- `ALL MOTION CHECKS PASSED`
- `IDLE blueSamples=...`, `SIGNAL idle blue>0`, `SIGNAL chat-open dot=59,130,246`, `SIGNAL thinking amber>0`, `SIGNAL post-success green>0`
- click/stream/Esc/drag still pass; app logs empty
- verify gates pass; review advisory only

- [ ] **Step 3: Commit**

```bash
git add tools/verify-motion.ps1
git commit -m "test: verify visual signal pairs live"
```

---

## Self-Review

**Spec coverage:** signal table → Task 1/2; base + transient resolver → Task 2; trigger wiring → Task 3; opacity-shrink crossfade → Task 3; 160 ms color animation → Task 4; header glyph → Task 3; idle randomness removed → Task 2; verification → Task 5. No gaps.

**Placeholder scan:** no TBD/TODO; every code-changing step contains complete code and exact commands.

**Type consistency:** `Set-SlopBaseCondition`, `Clear-SlopSignal`, `Set-SlopSignal`, `Get-SlopSignal`, `Update-SlopSignal`, `Sync-SlopSignal`, `Set-SlopTargetShape`, `$SlopColors`, `$SlopShapeIndex` are defined in Task 2 and used unchanged in Tasks 3-5. Canonical shape order `circle, square, triangle, rect` is used in `$script:Shapes`, `$script:GlyphShapes`, and `$SlopShapeIndex`.

**Flow bugs caught during self-review (fixed above):**
1. `Finish-Stream` and every 40 ms drain tick call `Set-SlopBaseCondition`. If that function cleared the transient, the success/error overlay would be erased in the same tick it was set. Base changes therefore never clear the overlay; the explicit `Clear-SlopSignal` in `Start-Stream` is the only place a new request clears it.
2. Stall detection mixed `Get-Date` (local) with `[DateTime]::UtcNow`, which gives a timezone-offset delta on the first tick. All timestamps now use `[DateTime]::UtcNow`.


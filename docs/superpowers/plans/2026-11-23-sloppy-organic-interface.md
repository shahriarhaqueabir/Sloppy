# Sloppy Organic Conversational Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task, inline in this session. Do **not** dispatch subagents — the user has an explicit no-subagents cost constraint. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Sloppy's rounded chat frame with an organic slime body that opens into the conversation surface, keeping the compact pea signal language and a stable, undeformed text layout.

**Architecture:** A new WPF-free geometry module produces eight interpolated anchors for the blob silhouette and converts them to a closed cubic-Bézier `PathGeometry`. `Slop.Motion.ps1` gains an `Open` spring plus a pulse spring; the WPF shell writes that geometry to a `Path` and to `Frame.Clip` every tick while the content Grid itself never gets a transform. The compact pea, its four shapes and the exact-RGB verifier stay untouched.

**Tech Stack:** PowerShell 7, WPF XAML (`Path`, `Clip`, `PathGeometry`), Pester-free headless assertion scripts, live UIA/pixel verifier (`tools/verify-motion.ps1`).

---

## File structure

| File | Responsibility |
|---|---|
| `src/Slop.Silhouette.ps1` (new) | Pure geometry: compact/expanded anchors, interpolation, Bézier path data, point-in-polygon. No WPF types. |
| `src/Slop.Motion.ps1` (modify) | Add `Open` and `OpenPulse` springs; drive their targets; step them with existing springs. |
| `src/Slop.ps1` (modify) | Replace `<Border x:Name="Frame">` with a `Path` + clipped `Grid`; add three control dots; apply geometry per tick; add resize support. |
| `tests/slop-silhouette-check.ps1` (new) | Headless geometry assertions, including verifier sample points inside the body. |
| `tests/slop-shell-check.ps1` (new) | Static + XAML-parse assertions that the shell has the new elements and never transforms content. |
| `tests/slop-motion-check.ps1` (modify) | Extend existing suite with `Open` spring assertions. |
| `docs/architecture.md` (modify) | Update visual-invariance and roadmap status. |
| `tools/verify-motion.ps1` (unchanged) | Live exact-RGB verifier; must pass without edits. |

---

### Task 1: Pure silhouette geometry module

**Files:**
- Create: `src/Slop.Silhouette.ps1`
- Test: `tests/slop-silhouette-check.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
# tests/slop-silhouette-check.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/Slop.Silhouette.ps1')

$script:failures = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { "PASS: $Message" } else { "FAIL: $Message"; $script:failures++ }
}

$compact  = Get-SlopSilhouettePoints -Open 0
$expanded = Get-SlopSilhouettePoints -Open 1
Assert-True ($compact.Count -eq 8 -and $expanded.Count -eq 8) 'eight anchors in both silhouettes'
Assert-True ([Math]::Abs($compact[0].X - 141.0) -lt 0.001) 'compact seed sits at pea upper-left'
Assert-True ([Math]::Abs($expanded[0].X - 60.0) -lt 0.001 -and [Math]::Abs($expanded[0].Y - 2.0) -lt 0.001) 'expanded head shelf anchor'

$mid = Get-SlopSilhouettePoints -Open 0.5
Assert-True ([Math]::Abs($mid[0].X - ((141.0 + 60.0) / 2.0)) -lt 0.001) 'open interpolates anchors linearly'
$quarter = Get-SlopSilhouettePoints -Open 0.25
Assert-True ($quarter[0].Y -lt $quarter[3].Y) 'head shelf stays above the right flank while opening'
Assert-True ([Math]::Abs((Get-SlopSilhouettePoints -Open 2.0)[0].X - 60.0) -lt 0.001) 'open clamps above 1'
Assert-True ([Math]::Abs((Get-SlopSilhouettePoints -Open -1.0)[0].X - 141.0) -lt 0.001) 'open clamps below 0'

$data = Convert-SlopSilhouetteToPathData -Points $expanded
Assert-True ($data.StartsWith('M ') -and $data.EndsWith(' Z')) 'path data is a closed path'
$curveCount = ([regex]::Matches($data, ' C ')).Count
Assert-True ($curveCount -eq 8) "path has eight cubic segments (got $curveCount)"
Assert-True (-not ($data -match 'NaN|Infinity')) 'path data has no NaN or Infinity'
Assert-True (-not ($data -match ',')) 'path data uses invariant decimal point'

# These are the frame-local equivalents of the live verifier's sample points:
# window (160,200) -> local (150,190); window (36,28) -> local (26,18);
# window (160,407) -> local (150,397).
foreach ($probe in @(@(150.0,190.0), @(26.0,18.0), @(150.0,397.0))) {
    Assert-True (Test-SlopSilhouetteContains -Points $expanded -X $probe[0] -Y $probe[1]) `
        "verifier sample $($probe -join ',') stays inside expanded body"
}

$pulsed = Get-SlopSilhouettePoints -Open 1 -Pulse 1.0
Assert-True ([Math]::Abs(($pulsed[3].Y - 240.0) - (($expanded[3].Y - 240.0) * 1.05)) -lt 0.001) 'pulse expands body vertically'
$leaned = Get-SlopSilhouettePoints -Open 1 -Lean 7.0
Assert-True ([Math]::Abs(($leaned[3].X - $expanded[3].X) - (7.0 * ($expanded[3].Y - 240.0) * 0.004)) -lt 0.001) 'lean shears body horizontally'
$wide = Get-SlopSilhouettePoints -Open 1 -Width 600
Assert-True ([Math]::Abs($wide[0].X - 120.0) -lt 0.001) 'width scales anchors for resize'

if ($script:failures -gt 0) { throw "$($script:failures) silhouette check(s) failed" }
'ALL SILHOUETTE CHECKS PASSED'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File tests/slop-silhouette-check.ps1`
Expected: FAIL — "The term 'Get-SlopSilhouettePoints' is not recognized"

- [ ] **Step 3: Write the module**

```powershell
# src/Slop.Silhouette.ps1
# Sloppy organic body geometry. Pure math only - no WPF types, safe to dot-source headlessly.
$ErrorActionPreference = 'Stop'

# Anchors are in frame-local coordinates: the content Grid is 300 x 420 at Canvas (10,10).
# Clockwise from the head shelf. Eight anchors are enough for a soft, asymmetrical blob.
# Ordered clockwise from the upper-left so the head shelf grows out of the
# pea's upper-left instead of swinging around the body during opening.
$SlopCompactAnchors = @(
    @{ X = 141.0; Y = 404.0 }   # upper-left  -> head shelf left
    @{ X = 150.0; Y = 400.0 }   # top         -> head shelf right
    @{ X = 159.0; Y = 404.0 }   # upper-right
    @{ X = 163.0; Y = 413.0 }   # right       -> right flank
    @{ X = 159.0; Y = 422.0 }   # lower-right
    @{ X = 150.0; Y = 426.0 }   # bottom
    @{ X = 141.0; Y = 422.0 }   # lower-left  -> left flank
    @{ X = 137.0; Y = 413.0 }   # left        -> upper-left rise
)

$SlopExpandedAnchors = @(
    @{ X = 60.0;  Y = 2.0 }    # wide flat head shelf, left end
    @{ X = 102.0; Y = 2.0 }    # wide flat head shelf, right end
    @{ X = 288.0; Y = 12.0 }
    @{ X = 296.0; Y = 220.0 }
    @{ X = 262.0; Y = 408.0 }
    @{ X = 46.0;  Y = 414.0 }
    @{ X = 4.0;   Y = 220.0 }
    @{ X = 16.0;  Y = 12.0 }   # rise from upper-left into the head shelf
)

function Format-SlopNumber {
    param([double]$Value)
    return $Value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-SlopSilhouettePoints {
    param(
        [Parameter(Mandatory)][double]$Open,
        [double]$Width = 300.0,
        [double]$Height = 420.0,
        [double]$Pulse = 0.0,
        [double]$Lean = 0.0
    )
    $o = [Math]::Min(1.0, [Math]::Max(0.0, $Open))
    $sx = $Width / 300.0
    $sy = $Height / 420.0
    $cx = 150.0 * $sx
    $cy = 240.0 * $sy
    $points = @()
    for ($i = 0; $i -lt 8; $i++) {
        $c = $SlopCompactAnchors[$i]
        $e = $SlopExpandedAnchors[$i]
        $x = ($c.X + ($e.X - $c.X) * $o) * $sx
        $y = ($c.Y + ($e.Y - $c.Y) * $o) * $sy
        $y = $cy + ($y - $cy) * (1.0 + 0.05 * $Pulse)
        $x = $x + $Lean * ($y - $cy) * 0.004
        $points += @{ X = $x; Y = $y }
    }
    return $points
}

function Convert-SlopSilhouetteToPathData {
    param([Parameter(Mandatory)][object[]]$Points)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append('M ').Append((Format-SlopNumber $Points[0].X)).Append(' ').Append((Format-SlopNumber $Points[0].Y))
    $n = $Points.Count
    for ($i = 0; $i -lt $n; $i++) {
        $prev = $Points[($i - 1 + $n) % $n]
        $p0   = $Points[$i]
        $p1   = $Points[($i + 1) % $n]
        $next = $Points[($i + 2) % $n]
        $c1x = $p0.X + ($p1.X - $prev.X) / 6.0
        $c1y = $p0.Y + ($p1.Y - $prev.Y) / 6.0
        $c2x = $p1.X - ($next.X - $p0.X) / 6.0
        $c2y = $p1.Y - ($next.Y - $p0.Y) / 6.0
        [void]$sb.Append(' C ').Append((Format-SlopNumber $c1x)).Append(' ').Append((Format-SlopNumber $c1y))
        [void]$sb.Append(' ').Append((Format-SlopNumber $c2x)).Append(' ').Append((Format-SlopNumber $c2y))
        [void]$sb.Append(' ').Append((Format-SlopNumber $p1.X)).Append(' ').Append((Format-SlopNumber $p1.Y))
    }
    [void]$sb.Append(' Z')
    return $sb.ToString()
}

function Test-SlopSilhouetteContains {
    param(
        [Parameter(Mandatory)][object[]]$Points,
        [Parameter(Mandatory)][double]$X,
        [Parameter(Mandatory)][double]$Y
    )
    $inside = $false
    $n = $Points.Count
    $j = $n - 1
    for ($i = 0; $i -lt $n; $j = $i++) {
        $a = $Points[$i]
        $b = $Points[$j]
        if ((($a.Y -gt $Y) -ne ($b.Y -gt $Y)) -and
            ($X -lt (($b.X - $a.X) * ($Y - $a.Y) / ($b.Y - $a.Y)) + $a.X)) {
            $inside = -not $inside
        }
    }
    return $inside
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -File tests/slop-silhouette-check.ps1`
Expected: `ALL SILHOUETTE CHECKS PASSED`

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.Silhouette.ps1 tests/slop-silhouette-check.ps1
git commit -m "feat(slop): add pure organic silhouette geometry module"
```

---

### Task 2: Open and pulse springs in the motion state

**Files:**
- Modify: `src/Slop.Motion.ps1:65-103`, `src/Slop.Motion.ps1:121-134`, `src/Slop.Motion.ps1:241-338`
- Test: `tests/slop-motion-check.ps1:64-69`

- [ ] **Step 1: Add failing assertions to the existing suite**

Insert after section 6 in `tests/slop-motion-check.ps1` (after the reduced-motion assertion, before `# 7.`):

```powershell
# 6b. organic body springs
Set-SlopFrameTarget -State $m -Target 'open'
Assert-True ($m.Open.Target -eq 1.0) 'open target expands the organic body'
Set-SlopFrameTarget -State $m -Target 'closed'
Assert-True ($m.Open.Target -eq 0.0) 'closed target returns the body to the pea'
$r2 = New-SlopMotionState
Set-SlopFrameTarget -State $r2 -Target 'open'
Update-SlopMotionState -State $r2 -Dt (1.0 / 120.0) -ReducedMotion
Assert-True ($r2.Open.Value -eq 1.0) 'reduced motion snaps the body open'
$s2 = New-SlopMotionState
Set-SlopBaseCondition -State $s2 -Streaming $true -ChatOpen $true -Stalled $false
Update-SlopMotionState -State $s2 -Dt (1.0 / 120.0)
Assert-True ($s2.OpenPulse.Target -gt 0.0) 'streaming drives a body pulse'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: FAIL — "The property 'Open' cannot be found on this object"

- [ ] **Step 3: Add the springs and targets**

In `New-SlopMotionState`, insert after `FrameAlpha  = New-SlopSpring 0.0 260 28`:

```powershell
        Open        = New-SlopSpring 0.0 150 19   # 0 = compact pea, 1 = expanded body
        OpenPulse   = New-SlopSpring 0.0 200 16   # streaming / success body pulse
```

In `Set-SlopFrameTarget`, replace the body of the function with:

```powershell
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
```

In `Update-SlopMotionState`, add `$State.Open, $State.OpenPulse` to `$allSprings` so the existing reduced-motion snap loop covers them:

```powershell
    $allSprings = @(
        $State.Squash, $State.Lean, $State.Puff, $State.Wobble,
        $State.ShadowScale, $State.ShadowAlpha,
        $State.FrameScale, $State.FrameAlpha, $State.MoodPulse,
        $State.Open, $State.OpenPulse
    )
```

Insert immediately before `foreach ($s in $allSprings) { $s.Step($Dt) }`:

```powershell
    if ($State.Signal.Streaming) {
        $State.OpenPulse.Target = 0.05 + 0.03 * [Math]::Sin($t * 5.0)
    }
    elseif ($State.Mood -eq 'success') {
        $State.OpenPulse.Target = 0.10 * $State.MoodPulse.Value
    }
    else {
        $State.OpenPulse.Target = 0.0
    }
```

- [ ] **Step 4: Run test to verify it passes, including all existing assertions**

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: `ALL MOTION CHECKS PASSED` (all 14 existing sections plus 6b)

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.Motion.ps1 tests/slop-motion-check.ps1
git commit -m "feat(slop): add body open and pulse springs"
```

---

### Task 3: XAML shell — body path, clipped content, control dots

**Files:**
- Modify: `src/Slop.ps1:55-114`, `src/Slop.ps1:148-160`, `src/Slop.ps1:178-179`, `src/Slop.ps1:408-414`
- Test: `tests/slop-shell-check.ps1` (new)

- [ ] **Step 1: Write the failing structural test**

```powershell
# tests/slop-shell-check.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
$script:failures = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { "PASS: $Message" } else { "FAIL: $Message"; $script:failures++ }
}

$src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
$m = [regex]::Match($src, '\$xaml = @''\r?\n(?<xaml>.*?)\r?\n''@', 'Singleline')
Assert-True $m.Success 'XAML here-string found'
if ($m.Success) {
    $w = [System.Windows.Markup.XamlReader]::Parse($m.Groups['xaml'].Value)
    foreach ($name in @('BodyPath','HeadHighlight','Frame','SettingsDot','PinDot','CloseDot','ControlDots','ChatScroll','InputBox','MicBtn','AttachBtn','StatusDot','ResizeGrip')) {
        Assert-True ($null -ne $w.FindName($name)) "XAML element $name exists"
    }
}
if ($script:failures -gt 0) { throw "$($script:failures) shell check(s) failed" }
'ALL SHELL CHECKS PASSED'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -STA -NoProfile -File tests/slop-shell-check.ps1`
Expected: FAIL — "XAML element BodyPath exists" fails, plus the static assertions

- [ ] **Step 3: Replace the XAML frame block**

Replace lines 55-114 of `src/Slop.ps1` (from `<Border x:Name="Frame"` through its closing `</Border>`) with:

```xml
    <!-- Organic body: translucent fill and hairline outline, geometry set each tick -->
    <Path x:Name="BodyPath" Canvas.Left="10" Canvas.Top="10"
          Fill="#D81E293B" Stroke="#33BFDBFE" StrokeThickness="0.75"
          IsHitTestVisible="False" Opacity="0" Visibility="Collapsed"/>
    <!-- Faint highlight tracing the head shelf; endpoints follow the silhouette anchors -->
    <Path x:Name="HeadHighlight" Canvas.Left="10" Canvas.Top="10"
          Stroke="#66FFFFFF" StrokeThickness="0.75" IsHitTestVisible="False"
          Opacity="0" Visibility="Collapsed"/>

    <!-- Stable content layer: clipped by the body, never deformed itself -->
    <Grid x:Name="Frame" Width="300" Height="420" Canvas.Left="10" Canvas.Top="10"
          Opacity="0" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="36"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
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
                 VerticalAlignment="Center" Margin="92,0,0,0" IsHitTestVisible="False"/>
      <!-- Three faint embedded dots near the wide head shelf; revealed on hover -->
      <StackPanel x:Name="ControlDots" Grid.Row="0" Orientation="Horizontal"
                  HorizontalAlignment="Left" VerticalAlignment="Center" Margin="46,0,0,0" Opacity="0.35">
        <Button x:Name="SettingsDot" Width="10" Height="10" Margin="0,0,6,0"
                Style="{StaticResource SlopButton}" Background="#33BFDBFE"
                BorderThickness="0" Cursor="Hand" ToolTip="Settings (slopsettings, planned)"/>
        <Button x:Name="PinDot" Width="10" Height="10" Margin="0,0,6,0"
                Style="{StaticResource SlopButton}" Background="#33BFDBFE"
                BorderThickness="0" Cursor="Hand" ToolTip="Pin"/>
        <Button x:Name="CloseDot" Width="10" Height="10"
                Style="{StaticResource SlopButton}" Background="#33BFDBFE"
                BorderThickness="0" Cursor="Hand" ToolTip="Close"/>
      </StackPanel>
      <ScrollViewer Grid.Row="1" x:Name="ChatScroll" VerticalScrollBarVisibility="Auto" Margin="10,4">
        <StackPanel x:Name="ChatStack"/>
      </ScrollViewer>
      <Border Grid.Row="2" Background="#10FFFFFF" Padding="8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Grid Grid.Column="0">
            <TextBox x:Name="InputBox" Height="34" FontSize="12"
                     Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#33FFFFFF"
                     CaretBrush="#EAEAEA" Padding="6,4" AcceptsReturn="False"
                     VerticalContentAlignment="Center"
                     ToolTip="Type a message, then press Enter to send"/>
            <TextBlock x:Name="InputPlaceholder" Text="Ask something…" FontSize="12"
                       Foreground="#77EAEAEA" VerticalAlignment="Center" Margin="7,0,0,0"
                       IsHitTestVisible="False"/>
          </Grid>
          <Button x:Name="MicBtn" Grid.Column="1" Content="◉" Style="{StaticResource SlopButton}"
                  Width="28" Height="34" Margin="6,0,0,0" Background="Transparent" Foreground="#AAA"
                  Cursor="Hand" FontSize="13" ToolTip="Voice input (not wired in this slice)"/>
          <Button x:Name="AttachBtn" Grid.Column="2" Content="+" Style="{StaticResource SlopButton}"
                  Width="28" Height="34" Margin="4,0,0,0" Background="Transparent" Foreground="#AAA"
                  Cursor="Hand" FontSize="13" ToolTip="Attach (not wired in this slice)"/>
          <Button x:Name="StopBtn" Grid.Column="3" Content="■" Style="{StaticResource SlopButton}"
                  Width="40" Height="34" Margin="6,0,0,0" Background="#7F1D1D" Foreground="White"
                  Cursor="Hand" FontSize="11" Visibility="Collapsed"/>
          <Button x:Name="SendBtn" Grid.Column="4" Content="Send" Style="{StaticResource SlopButton}"
                  Width="64" Height="34" Margin="6,0,0,0" Background="#3B82F6" Foreground="White"
                  Cursor="Hand" FontWeight="SemiBold" FontSize="12"/>
        </Grid>
      </Border>
    </Grid>

    <!-- Bottom-right resize grip for growing the conversation workspace -->
    <Border x:Name="ResizeGrip" Width="16" Height="16" Canvas.Right="0" Canvas.Bottom="0"
            Background="Transparent" Cursor="SizeNWSE" ToolTip="Resize"/>
```

Keep the `StatusDot` at `Margin="22,0,0,0"` — the live verifier samples window pixel `(36,28)`, which is this dot's center. Keep `BodyPath.Fill` exactly `#D81E293B` so the verifier's dark-panel threshold still holds. `MicBtn` and `AttachBtn` are visual affordances only, like the settings dot; their ToolTips say they are not wired. Voice input and file attachment stay out of this slice, but their controls remain in the input pocket as the spec requires.

- [ ] **Step 4: Update element lookups and handlers**

Replace `$PinBtn = $window.FindName('PinBtn')` with:

```powershell
$BodyPath = $window.FindName('BodyPath')
$HeadHighlight = $window.FindName('HeadHighlight')
$SettingsDot = $window.FindName('SettingsDot')
$PinDot = $window.FindName('PinDot')
$CloseDot = $window.FindName('CloseDot')
$ControlDots = $window.FindName('ControlDots')
$ResizeGrip = $window.FindName('ResizeGrip')
```

Replace `$CloseChatBtn.Add_Click({ Collapse-Chat })` with:

```powershell
$CloseDot.Add_Click({ Collapse-Chat })
$ControlDots.Add_MouseEnter({ $ControlDots.Opacity = 0.95 })
$ControlDots.Add_MouseLeave({ $ControlDots.Opacity = 0.35 })
```

Replace the pin handler block at lines 408-414 with:

```powershell
# Pin is a visual lock indicator; chat no longer collapses when another app takes focus.
$PinDot.Add_Click({
    $script:Pinned = -not $script:Pinned
    $PinDot.Opacity = if ($script:Pinned) { 1.0 } else { 0.35 }
    $PinDot.ToolTip = if ($script:Pinned) { 'Unpin' } else { 'Pin' }
})
```

Also in `Initialize-MotionVisuals` (around line 271), replace the two `Frame.BorderBrush`
lines — a WPF `Grid` has no `BorderBrush` property, so leaving them would throw at
startup once `Frame` stops being a `Border`:

```powershell
    $BodyPath.Stroke = [System.Windows.Media.SolidColorBrush]::new($initial)
    $script:ColorBrushes += $BodyPath.Stroke
```

This keeps the signal colour animating on the body's hairline outline.

The `SettingsDot` stays intentionally inert in this slice: `slopsettings` is a separate future command. Its ToolTip says so. Do not add a handler that pretends to open settings.

- [ ] **Step 5: Run test to verify it passes**

Run: `pwsh -STA -NoProfile -File tests/slop-shell-check.ps1`
Expected: `ALL SHELL CHECKS PASSED`

- [ ] **Step 6: Commit**

```powershell
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "feat(slop): replace chat frame with organic body and embedded dots"
```

---

### Task 4: Apply silhouette geometry on every tick

**Files:**
- Modify: `src/Slop.ps1:20-22` (dot-source), `src/Slop.ps1:256-258` (`Initialize-MotionVisuals`), `src/Slop.ps1:305-311` (`Apply-SlopMotion`), `src/Slop.ps1:325-334` (`Expand-Chat`)
- Test: `tests/slop-shell-check.ps1` (extend)

- [ ] **Step 1: Extend the structural test**

The geometry-related assertions are deferred to this task because Task 3 only adds the
XAML elements; the module wiring and per-tick geometry arrive here. Append before the
`if ($script:failures -gt 0)` line in `tests/slop-shell-check.ps1`:

```powershell
Assert-True ($src -notmatch '\$Frame\.RenderTransform\s*=') 'content frame is never transformed by motion'
Assert-True ($src -match 'Slop\.Silhouette\.ps1') 'geometry module is dot-sourced'
Assert-True ($src -match 'Convert-SlopSilhouetteToPathData') 'silhouette geometry is applied to the shell'
Assert-True ($src -match '\$BodyPath\.Data\s*=') 'body path data is written each tick'
Assert-True ($src -match '\$HeadHighlight\.Data\s*=') 'head shelf highlight follows the silhouette'
Assert-True ($src -match '\$Frame\.Clip\s*=') 'content layer is clipped by the body geometry'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -STA -NoProfile -File tests/slop-shell-check.ps1`
Expected: FAIL on all six new assertions

- [ ] **Step 3: Dot-source the module**

Insert after `. (Join-Path $PSScriptRoot 'Slop.Motion.ps1')` at line 20:

```powershell
. (Join-Path $PSScriptRoot 'Slop.Silhouette.ps1')
```

- [ ] **Step 4: Stop transforming the content frame**

In `Initialize-MotionVisuals`, delete these two lines:

```powershell
    $Frame.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $Frame.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1,1)
```

The `$Frame.BorderBrush` assignment was already redirected to `$BodyPath.Stroke` in Task 3, since `Frame` is now a `Grid`.

- [ ] **Step 5: Write geometry instead of a scale transform**

Replace lines 305-311 of `src/Slop.ps1` (the `$Frame.Opacity` / `$Frame.RenderTransform` block and the collapse guard) with:

```powershell
    $open = [Math]::Min(1.0, [Math]::Max(0.0, $m.Open.Value))
    $alpha = [Math]::Min(1.0, [Math]::Max(0.0, $m.FrameAlpha.Value))
    if ($open -le 0.001 -and -not $script:Expanded) {
        $BodyPath.Visibility = 'Collapsed'
        $HeadHighlight.Visibility = 'Collapsed'
        $Frame.Visibility = 'Collapsed'
        $PeaCanvas.Visibility = 'Visible'
    }
    else {
        $points = Get-SlopSilhouettePoints -Open $open `
            -Width $Frame.Width -Height $Frame.Height `
            -Pulse $m.OpenPulse.Value -Lean $m.Lean.Value
        $data = Convert-SlopSilhouetteToPathData -Points $points
        $geo = [System.Windows.Media.Geometry]::Parse($data)
        $BodyPath.Data = $geo
        # Anchors 0 and 1 are the head-shelf endpoints; inset slightly so the
        # highlight sits on the shelf instead of over the outline.
        $HeadHighlight.Data = [System.Windows.Media.LineGeometry]::new(
            [System.Windows.Point]::new($points[0].X + 2.0, $points[0].Y + 2.0),
            [System.Windows.Point]::new($points[1].X - 2.0, $points[1].Y + 2.0))
        $HeadHighlight.Opacity = $alpha * 0.6
        $HeadHighlight.Visibility = 'Visible'
        $BodyPath.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
        $BodyPath.RenderTransform = [System.Windows.Media.ScaleTransform]::new($m.FrameScale.Value, $m.FrameScale.Value)
        $BodyPath.Opacity = $alpha
        $BodyPath.Visibility = 'Visible'
        $Frame.Clip = $geo
        $Frame.Opacity = $alpha
        $Frame.Visibility = 'Visible'
        $PeaCanvas.Visibility = 'Collapsed'
    }
```

Do not add any `RenderTransform` assignment to `$Frame`. The inner Grid keeps the same rows, margins and font sizes on every frame.

- [ ] **Step 6: Make expand show the body immediately**

In `Expand-Chat`, insert `$BodyPath.Visibility = 'Visible'` after `$Frame.Visibility = 'Visible'`.

- [ ] **Step 7: Run all headless checks**

Run: `pwsh -STA -NoProfile -File tests/slop-shell-check.ps1`
Expected: `ALL SHELL CHECKS PASSED`

Run: `pwsh -NoProfile -File tests/slop-silhouette-check.ps1`
Expected: `ALL SILHOUETTE CHECKS PASSED`

Run: `pwsh -NoProfile -File tests/slop-motion-check.ps1`
Expected: `ALL MOTION CHECKS PASSED`

- [ ] **Step 8: Commit**

```powershell
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "feat(slop): drive organic body geometry from motion springs"
```

---

### Task 5: Resizable workspace without losing the silhouette

**Files:**
- Modify: `src/Slop.ps1` (Window XAML `ResizeMode`, resize handlers, `SizeChanged`)

- [ ] **Step 1: Extend the structural test**

Append before the failure check in `tests/slop-shell-check.ps1`:

```powershell
Assert-True ($src -match 'Add_SizeChanged') 'window size changes relayout the organic body'
Assert-True ($src -match '\$ResizeGrip\.Add_MouseMove') 'resize grip has a live drag handler'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -STA -NoProfile -File tests/slop-shell-check.ps1`
Expected: FAIL on both new assertions

- [ ] **Step 3: Allow resizing**

In the Window XAML, change `ResizeMode="NoResize"` to `ResizeMode="CanResize"` and change `Width="320" Height="460"` to `MinWidth="320" MinHeight="460" Width="320" Height="460"`. Keep `WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True"` unchanged.

- [ ] **Step 4: Add resize and relayout handlers**

Insert after the `$DragHandle.Add_MouseLeftButtonDown(...)` line:

```powershell
$script:resizeOrigin = $null
$ResizeGrip.Add_MouseLeftButtonDown({
    param($s, $e)
    $p = $e.GetPosition($window)
    $script:resizeOrigin = @($p.X, $p.Y, $window.ActualWidth, $window.ActualHeight)
    $ResizeGrip.CaptureMouse()
    $e.Handled = $true
})
$ResizeGrip.Add_MouseMove({
    param($s, $e)
    if (-not $script:resizeOrigin) { return }
    $p = $e.GetPosition($window)
    $window.Width  = [Math]::Max(320.0, [Math]::Min(900.0, $script:resizeOrigin[2] + ($p.X - $script:resizeOrigin[0])))
    $window.Height = [Math]::Max(460.0, [Math]::Min(1100.0, $script:resizeOrigin[3] + ($p.Y - $script:resizeOrigin[1])))
})
$ResizeGrip.Add_MouseLeftButtonUp({
    param($s, $e)
    $script:resizeOrigin = $null
    $ResizeGrip.ReleaseMouseCapture()
})

$window.Add_SizeChanged({
    param($s, $e)
    $Frame.Width = [Math]::Max(200.0, $window.ActualWidth - 20)
    $Frame.Height = [Math]::Max(300.0, $window.ActualHeight - 40)
})
```

Every WPF handler declares `param($s, $e)` so `$e` is the real `MouseEventArgs`, matching
the existing handlers in `src/Slop.ps1`. `$e.GetPosition($window)` uses WPF units, so this
works under Windows display scaling. `Get-SlopSilhouettePoints` scales anchors by
`$Frame.Width / 300` and `$Frame.Height / 420`, so the blob keeps its proportions at any size.

- [ ] **Step 5: Run structural and motion checks**

Run: `pwsh -STA -NoProfile -File tests/slop-shell-check.ps1`
Expected: `ALL SHELL CHECKS PASSED`

Run: `pwsh -NoProfile -File tests/slop-silhouette-check.ps1`
Expected: `ALL SILHOUETTE CHECKS PASSED`

- [ ] **Step 6: Commit**

```powershell
git add src/Slop.ps1 tests/slop-shell-check.ps1
git commit -m "feat(slop): allow resizing while keeping the organic silhouette"
```

---

### Task 6: Update architecture docs

**Files:**
- Modify: `docs/architecture.md` (Visual invariance section ~251-260, Roadmap table ~275+)

- [ ] **Step 1: Rewrite the visual-invariance section**

Replace the `## Visual invariance` section with:

```markdown
## Visual invariance

Non-negotiable for this slice:

- four colours, four shapes, no face, eyes, mouth or emoji;
- the **compact pea** signal table is unchanged (idle/circle, chat-open/square,
  streaming/triangle, stalled/rect, success/square 1.5 s, error/rect 2.0 s);
- streaming outranks chat-open; success and error are transient overlays;
- **only the compact pea is sampled by `tools/verify-motion.ps1`**; its exact-RGB
  checks must keep passing without edits;
- the expanded chat surface is now an organic slime body (`src/Slop.Silhouette.ps1`)
  with a wide, flat head shelf at the upper-left. The outer silhouette deforms;
  the inner content Grid never receives a transform, only a clip;
- three faint dots near the head provide settings / pin / close. The settings dot
  is intentionally inert until the separate `slopsettings` command exists;
- reduced motion flattens body deformation to a simple fade.
```

- [ ] **Step 2: Add the roadmap row**

In the Roadmap table, add or update the character-restyle row to:

```markdown
| Character restyle: organic body as chat surface | `src/Slop.Silhouette.ps1`, WPF `Path`/`Clip` | done; live verifier unchanged |
```

- [ ] **Step 3: Commit**

```powershell
git add docs/architecture.md
git commit -m "docs: record organic interface invariants and roadmap status"
```

---

### Task 7: Live verification (unchanged verifier) and final gate

**Files:** none modified; `tools/verify-motion.ps1` must stay byte-identical.

- [ ] **Step 1: Confirm the live verifier was not touched**

Run: `git diff --exit-code dbd139d -- tools/verify-motion.ps1`
Expected: no output, exit 0. If it differs, stop and revert the verifier changes before continuing.

- [ ] **Step 2: Run the live verifier**

Run: `pwsh -NoProfile -File tools/verify-motion.ps1 2>&1 | Select-Object -Last 30 | Out-String`
Expected: lines `LAUNCH pid=...`, `SIGNAL idle ...`, `EXPAND panel=...`, `SIGNAL chat-open ... color=blue`, `SIGNAL thinking ... color=amber`, `STREAM changes=...`, `SIGNAL success ... color=green`, `ESC panel=...`, `DRAG moved=...`, then `FINAL_PID=...`. No `throw` messages. The script must terminate the app it launched (it calls `Stop-Process` at the end).

- [ ] **Step 3: Confirm no orphaned app process**

Run: `Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -match 'src\\Slop\.ps1' } | Select-Object ProcessId, CommandLine | Format-Table -AutoSize | Out-String`
Expected: empty table.

- [ ] **Step 4: Run every headless check**

```powershell
pwsh -NoProfile -File tests/slop-silhouette-check.ps1
pwsh -NoProfile -File tests/slop-motion-check.ps1
pwsh -NoProfile -File tests/slop-lifecycle-check.ps1
pwsh -STA -NoProfile -File tests/slop-shell-check.ps1
pwsh -NoProfile -File tests/slop-opencode-check.ps1
```
Expected: each exits 0, with `ALL ... CHECKS PASSED` or `TEST_EXIT=0`.

- [ ] **Step 5: Run the project Verify gate**

Run: `pwsh -NoProfile -File C:\Users\example\.agents\scripts\verify.ps1`
Expected: `VERIFY_EXIT=0`, `All gates passed.`

- [ ] **Step 6: Final status**

Run: `git status -sb`
Expected: `## main` with a clean working tree (the pre-existing untracked `assets/` directory is left alone).

---

## Self-review against the spec

- Shape — wide flat head shelf, faint shelf highlight, tiny, no face: Tasks 1, 3 and 4.
- Chat ~85% / embedded dots / input pocket with send, mic and attach: Task 3.
- Open/close and body-only reactions: Tasks 2 and 4.
- Stable clipped content, no per-frame rebuild: Task 4 (static guards in Task 4 Step 1).
- Reduced motion and DPI: Task 2 (spring snap), Task 5 (`GetPosition`, scaled anchors).
- Scrolling, large responses, resizable: Task 5.
- Keep signal table and exact-RGB verifier: Tasks 2 and 7, plus the geometry test's verifier-point assertions.
- `slopsettings` future intent: Task 3 (inert dot + ToolTip), documented in Task 6.
- No OpenCode/permission/persona/service changes: none of the tasks touch those files.

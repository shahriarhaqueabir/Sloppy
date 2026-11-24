# Research: WPF + PowerShell 7

## Launch
- `pwsh -STA -File src/Slop.ps1` (WPF requires STA)
- Load assemblies: PresentationFramework, PresentationCore, WindowsBase, System.Xaml

## Patterns
- XAML via `[System.Windows.Markup.XamlReader]::Load`
- Dispatcher for marshaling from background runspace/ThreadJob
- RunspacePool or ThreadJob for Ollama streaming (never block UI thread)

## Risks
- Thread apartment: must be STA; `pwsh -STA`
- Memory/GC for long-running transparent windows
- High-DPI / per-monitor DPI for overlay positioning

## Options
- Pure XAML-in-PS vs compiled C# via Add-Type
- Use `RunspaceFactory` vs `Start-ThreadJob`

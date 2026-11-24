# Research: UI Automation (System.Windows.Automation)

## Capabilities
- Read text from active window via AutomationElement
- Fast, exact, no vision model needed
- Works for most Win32/WPF/UWP apps

## Limitations
- Electron apps, some games, remote desktop → sparse text
- Needs fallback to screenshot+vision

## Implementation notes
- Get foreground window via GetForegroundWindow + AutomationElement.FromHandle
- Walk control tree, collect Name/Value patterns
- Denylist by process name (password managers, banking)
- On-demand only in v1

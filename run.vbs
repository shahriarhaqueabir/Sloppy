' Headless launcher for Sloppy (no PowerShell console window).
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pwsh -WindowStyle Hidden -STA -NoProfile -File """ & WshShell.CurrentDirectory & "\src\Slop.ps1""", 0, False
Set WshShell = Nothing
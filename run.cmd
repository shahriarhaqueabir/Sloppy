@echo off
REM Headless launcher for Sloppy (no PowerShell console window).
start "" pwsh -WindowStyle Hidden -STA -File "%~dp0src\Slop.ps1"
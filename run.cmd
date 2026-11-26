@echo off
REM Headless launcher for Sloppy (no PowerShell console window).
REM Uses a VBScript wrapper so the console never flashes.
wscript "%~dp0run.vbs"
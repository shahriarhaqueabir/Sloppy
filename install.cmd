@echo off
setlocal
title Sloppy installer
echo.
echo  Sloppy bootstrap installer
echo  ========================
echo.

REM --- Ensure winget is available (ships with Windows 11 / recent Win10) ---
where winget >nul 2>&1
if errorlevel 1 (
    echo winget was not found.
    echo Install the "App Installer" package from the Microsoft Store, then re-run.
    echo https://aka.ms/getwinget
    pause
    exit /b 1
)

REM --- Install prerequisites via winget if missing ---
where pwsh >nul 2>&1
if errorlevel 1 (
    echo Installing PowerShell 7...
    winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
)

where git >nul 2>&1
if errorlevel 1 (
    echo Installing Git...
    winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements
)

git lfs version >nul 2>&1
if errorlevel 1 (
    echo Installing Git LFS...
    winget install --id GitHub.GitLFS --silent --accept-package-agreements --accept-source-agreements
)

REM --- Refresh PATH for this session ---
for /f "delims=" %%i in ('powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')"') do set "PATH=%%i"

REM --- Hand off to the PowerShell bootstrap ---
if exist "%~dp0install.ps1" (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1 | iex"
)

echo.
pause
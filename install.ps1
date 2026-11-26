<#
.SYNOPSIS
  Bootstrap installer for Sloppy (Windows).
.DESCRIPTION
  Checks prerequisites (PowerShell 7.6+, git, git-lfs), clones or updates the
  repo, fetches LFS artifacts, and creates a Start Menu shortcut.
  Run from an elevated or normal PowerShell prompt:
    irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1 | iex
#>
$ErrorActionPreference = 'Stop'

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

Write-Host "Sloppy bootstrap installer" -ForegroundColor Cyan

# --- prerequisites ---------------------------------------------------------
if (-not (Test-Command pwsh)) {
    Write-Host "PowerShell 7+ is required. Install from https://aka.ms/powershell" -ForegroundColor Red
    exit 1
}
$ver = (Get-Command pwsh).Version
if ($ver -lt [version]'7.6') {
    Write-Host "PowerShell 7.6+ required (found $ver)." -ForegroundColor Red
    exit 1
}
if (-not (Test-Command git)) {
    Write-Host "git is required. Install from https://git-scm.com" -ForegroundColor Red
    exit 1
}
if (-not (Test-Command git-lfs)) {
    Write-Host "git-lfs is required. Install from https://git-lfs.com" -ForegroundColor Red
    exit 1
}

# --- install location -----------------------------------------------------
$installDir = Join-Path $env:LOCALAPPDATA 'Sloppy'
if (-not (Test-Path $installDir)) {
    Write-Host "Cloning Sloppy into $installDir ..."
    git clone https://github.com/shahriarhaqueabir/Sloppy.git $installDir
} else {
    Write-Host "Updating existing install at $installDir ..."
    git -C $installDir pull --ff-only
}
git -C $installDir lfs pull

# --- shortcut -------------------------------------------------------------
$wsh = New-Object -ComObject WScript.Shell
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcut = $wsh.CreateShortcut((Join-Path $startMenu 'Sloppy.lnk'))
$shortcut.TargetPath = 'pwsh.exe'
$shortcut.Arguments = "-STA -File `"$installDir\src\Slop.ps1`""
$shortcut.WorkingDirectory = $installDir
$shortcut.IconLocation = "$installDir\assets\sloppy.ico"
$shortcut.Save()

Write-Host ""
Write-Host "Sloppy installed to $installDir" -ForegroundColor Green
Write-Host "Launch from Start Menu: 'Sloppy', or run:" -ForegroundColor Green
Write-Host "  pwsh -STA -File `"$installDir\src\Slop.ps1`"" -ForegroundColor Yellow

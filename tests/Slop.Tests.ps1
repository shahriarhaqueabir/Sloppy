#Requires -Version 7.4
<#
.SYNOPSIS
  Pester discovery entry point. Lets `Invoke-Pester -Path <repo>` run every
  hand-rolled `*-check.ps1` suite that has been migrated to Pester 6, without
  renaming the suites (docs and the local test loop still use `tests/*.ps1`).
#>
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0

Get-ChildItem -Path $PSScriptRoot -Filter '*-check.ps1' |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

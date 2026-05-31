#!/usr/bin/env pwsh
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Args
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $root '.env.local.ps1'
if (Test-Path $envFile) {
  . $envFile
}

if (-not $Args -or $Args.Length -eq 0) {
  Write-Host 'Usage: .\dev.ps1 <command> [args...]'
  exit 1
}

& $Args

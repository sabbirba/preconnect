<#
.SYNOPSIS
  Automated Windows developer setup for PreConnect.

.DESCRIPTION
  Installs Android command-line tools, NDK and CMake via sdkmanager on Windows,
  writes android/local.properties, creates .env.local.ps1 that exports SDK/NDK
  env vars, and adds Rust Android targets if rustup is present.

.USAGE
  Run from repository root in PowerShell (run as normal user):

    .\tool\dev_setup.ps1

#>
param()
Set-StrictMode -Version Latest

function Write-Log { param($m) Write-Host "[dev-setup] $m" }

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Discover SDK directory
$sdkDefault = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$sdkDir = $env:ANDROID_SDK_ROOT
if (-not $sdkDir) { $sdkDir = $env:ANDROID_HOME }
if (-not $sdkDir) { $sdkDir = $sdkDefault }

Write-Log "Using Android SDK directory: $sdkDir"
if (-not (Test-Path $sdkDir)) {
  Write-Error "Android SDK directory not found at $sdkDir. Install Android Studio or set ANDROID_SDK_ROOT.";
  exit 1
}

# locate sdkmanager (.bat)
$sdkmanager = Join-Path $sdkDir 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path $sdkmanager)) {
  $alt = Join-Path $sdkDir 'tools\bin\sdkmanager.bat'
  if (Test-Path $alt) { $sdkmanager = $alt }
}

function Download-CmdlineTools {
  Write-Log 'Downloading Android command-line tools for Windows...'
  $pkg = 'commandlinetools-win-8512546_latest.zip'
  $url = "https://dl.google.com/android/repository/$pkg"
  $out = Join-Path $env:TEMP $pkg
  Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
  $target = Join-Path $sdkDir 'cmdline-tools\latest'
  if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
  Expand-Archive -Path $out -DestinationPath (Join-Path $sdkDir 'cmdline-tools') -Force
  # normalize extraction (zip contains cmdline-tools\bin or cmdline-tools\cmdline-tools)
  $raw = Join-Path $sdkDir 'cmdline-tools\cmdline-tools'
  if (Test-Path $raw) {
    Copy-Item -Path (Join-Path $raw '*') -Destination $target -Recurse -Force
  } else {
    # copy everything under cmdline-tools
    Copy-Item -Path (Join-Path $sdkDir 'cmdline-tools\*') -Destination $target -Recurse -Force
  }
  Remove-Item $out -Force
  $sdkmanager = Join-Path $target 'bin\sdkmanager.bat'
  return $sdkmanager
}

if (-not (Test-Path $sdkmanager)) {
  Write-Log 'sdkmanager not found — attempting automatic download...'
  $sdkmanager = Download-CmdlineTools
  if (-not (Test-Path $sdkmanager)) {
    Write-Error 'Failed to obtain sdkmanager. Please install Android command-line tools.'; exit 1
  }
}

Write-Log "Using sdkmanager: $sdkmanager"

function Install-Pkg($pkg) {
  Write-Log "Installing $pkg"
  & cmd /c ""$sdkmanager" --install $pkg --sdk_root="$sdkDir"" | Write-Host
}

Install-Pkg 'cmdline-tools;latest'
Install-Pkg 'cmake;3.22.1'

$recommended = '28.2.13676358'
Install-Pkg "ndk;$recommended"

# accept licenses
Write-Log 'Accepting SDK licenses'
& cmd /c "echo y|""$sdkmanager"" --licenses" | Write-Host

# detect installed NDK
$ndkFolder = Join-Path $sdkDir 'ndk'
if (-not (Test-Path $ndkFolder)) { Write-Error 'No ndk folder found after install'; exit 1 }
$ndkDirs = Get-ChildItem -Directory $ndkFolder | Sort-Object Name -Descending
if ($ndkDirs.Length -eq 0) { Write-Error 'No NDK versions found'; exit 1 }
$chosen = $ndkDirs[0].FullName
Write-Log "Detected NDK: $chosen"

# update android/local.properties
$local = Join-Path $root 'android\local.properties'
Write-Log "Updating $local"
if (-not (Test-Path (Split-Path $local))) { New-Item -ItemType Directory -Path (Split-Path $local) -Force | Out-Null }
$sdkProp = "sdk.dir=$sdkDir"
if (Test-Path $local) {
  $content = Get-Content $local
  if ($content -match '^sdk.dir=') {
    $content = $content -replace '^sdk.dir=.*', $sdkProp
  } else {
    $content += $sdkProp
  }
  $content | Where-Object { $_ -notmatch '^ndk.dir=' } | Set-Content $local
} else {
  @($sdkProp, "flutter.sdk=$(Get-Command flutter -ErrorAction SilentlyContinue | ForEach-Object { $_.Source } )", 'flutter.buildMode=release') | Set-Content $local
}

# write env helper
$envFile = Join-Path $root '.env.local.ps1'
@("$env:ANDROID_SDK_ROOT = '$sdkDir'", "$env:ANDROID_NDK_HOME = '$chosen'", "$env:ANDROID_NDK_ROOT = '$chosen'") | Set-Content $envFile
Write-Log "Wrote env helper: $envFile"

# rust targets
if (Get-Command rustup -ErrorAction SilentlyContinue) {
  Write-Log 'Adding Rust targets via rustup'
  & rustup target add aarch64-linux-android | Out-Null
  & rustup target add armv7-linux-androideabi | Out-Null
  & rustup target add i686-linux-android | Out-Null
  & rustup target add x86_64-linux-android | Out-Null
} else {
  Write-Log 'rustup not found; skipping Rust target setup'
}

# flutter pub get
if (Get-Command flutter -ErrorAction SilentlyContinue) { Write-Log 'Running flutter pub get'; & flutter pub get }

Write-Log 'Done. Use .\dev.ps1 <command> to run commands with environment variables loaded or run: . .\.env.local.ps1'
exit 0

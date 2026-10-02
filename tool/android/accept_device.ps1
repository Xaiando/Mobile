<#
.SYNOPSIS
Checks the app on a phone connected with USB or wireless debugging.

.DESCRIPTION
Finds adb, requires exactly one authorised device, verifies the APK
(tool\android\verify_apk.py), installs it, launches it twice, and reports
how long the first screen takes, whether anything crashed, and how much
memory the app uses (tool\android\emulator_smoke.sh). It writes a folder of
results you can send back: summary.md, device.txt, logcat.txt, a screenshot.

It never taps, types or confirms anything on the phone. You do the age
confirmation and the track choice yourself. It never uninstalls the app: if
an earlier build was signed with another key, Android refuses the update;
export your data in the app (Settings > Your data), uninstall the old build
by hand, and run this again.

    powershell -ExecutionPolicy Bypass -File tool\android\accept_device.ps1 `
        -Apk build\app\outputs\flutter-apk\app-release.apk

    # Later, with the app already installed and set up:
    powershell -ExecutionPolicy Bypass -File tool\android\accept_device.ps1 `
        -NoInstall -Ready 'Practice'

.PARAMETER Apk
The APK to install. Needed unless -NoInstall.

.PARAMETER NoInstall
Launch and measure the app that is already installed.

.PARAMETER Ready
Text that shows the app has started. The default is the first onboarding
line on a fresh install; use 'Practice' once you have finished onboarding.

.PARAMETER Out
Where to write the results. Defaults to build\android-acceptance\<time>.
#>
param(
    [string]$Apk,
    [switch]$NoInstall,
    [string]$Ready = 'I am of legal drinking age',
    [string]$Out
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
if (-not $Out) {
    $Out = Join-Path $root ('build\android-acceptance\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (-not $NoInstall -and -not $Apk) { throw 'Give -Apk <path>, or -NoInstall.' }
if ($Apk -and -not (Test-Path $Apk)) { throw "No such APK: $Apk" }

function Find-Adb {
    $found = Get-Command adb -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) { return $path }
    }
    throw 'adb was not found. Install it with: winget install Google.PlatformTools'
}

function Find-Bash {
    foreach ($path in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe")) {
        if (Test-Path $path) { return $path }
    }
    throw 'Git Bash was not found. Install Git for Windows (it includes bash).'
}

$adb = Find-Adb
$bash = Find-Bash
Write-Host "adb:  $adb"

# Exactly one device, authorised.
$lines = & $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() }
$devices = @($lines | ForEach-Object { $parts = $_ -split '\s+'; [pscustomobject]@{ Serial = $parts[0]; State = $parts[1] } })
if ($devices.Count -eq 0) {
    throw @'
No phone is connected. On the phone: Settings > About phone > Software
information, tap Build number seven times, then Settings > Developer options
> USB debugging (or Wireless debugging). On a Samsung phone also turn off
Settings > Security and privacy > Auto Blocker, which blocks installs and
USB commands. Then plug in and accept "Allow USB debugging?".
'@
}
if ($devices.Count -gt 1) { throw "More than one device is attached: $($devices.Serial -join ', '). Disconnect the others." }
$device = $devices[0]
if ($device.State -eq 'unauthorized') { throw 'The phone has not accepted this PC. Unlock it and tap Allow on the "Allow USB debugging?" prompt.' }
if ($device.State -ne 'device') { throw "The phone is '$($device.State)'. Reconnect it." }

$model = (& $adb shell getprop ro.product.model).Trim()
$release = (& $adb shell getprop ro.build.version.release).Trim()
$oneUi = (& $adb shell getprop ro.build.version.oneui).Trim()
Write-Host "phone: $model, Android $release$(if ($oneUi) { ", One UI code $oneUi" })"

if ($Apk) {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        Write-Host "`nChecking the APK against the app's Android contract..."
        & python (Join-Path $PSScriptRoot 'verify_apk.py') $Apk
        if ($LASTEXITCODE -ne 0) { throw 'The APK fails its contract (above). Not installing it.' }
    } else {
        Write-Warning 'Python is not installed, so the APK was not checked.'
    }
}

New-Item -ItemType Directory -Force $Out | Out-Null
$smoke = (Join-Path $PSScriptRoot 'emulator_smoke.sh') -replace '\\', '/'
$outForBash = (Resolve-Path $Out).Path -replace '\\', '/'
$arguments = @($smoke, '--ready', $Ready)
if ($NoInstall) { $arguments += '--no-install' }
$arguments += @(($(if ($Apk) { (Resolve-Path $Apk).Path -replace '\\', '/' } else { 'none.apk' })), $outForBash)

Write-Host "`nLaunching the app twice and watching for crashes. Leave the phone unlocked.`n"
$env:PATH = (Split-Path $adb) + ';' + $env:PATH
& $bash @arguments
$status = $LASTEXITCODE

Write-Host "`nResults: $Out"
Write-Host 'Now work through docs\android-acceptance.md on the phone.'
exit $status

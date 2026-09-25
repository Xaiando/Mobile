# Creates the private key that signs the APKs CI builds on main, and stores
# it as the repository's Actions secrets. Run it once, yourself:
#
#   powershell -ExecutionPolicy Bypass -File tool\android\make_release_key.ps1
#
# It needs a JDK (for keytool) and the GitHub CLI signed in to an account
# that administers the repository. It never shows the password. The key and
# its password are also kept in %USERPROFILE%\.sommelier\: back them up, and
# never make a second key, because Android installs an update only over an
# app signed with the same key.
#
# -Reupload stores the kept key as secrets again, e.g. after they were
# deleted.
param([switch]$Reupload, [string]$Repo = 'Xaiando/Mobile')

$ErrorActionPreference = 'Stop'
$dir = Join-Path $HOME '.sommelier'
$keystore = Join-Path $dir 'release.keystore'
$passwordFile = Join-Path $dir 'release.password'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'The GitHub CLI (gh) is not installed.'
}

if ($Reupload) {
    if (-not (Test-Path $keystore) -or -not (Test-Path $passwordFile)) {
        throw "No kept key in $dir to upload."
    }
    $password = Get-Content $passwordFile -Raw
} else {
    if (Test-Path $keystore) {
        throw "$keystore already exists. Keep using it: run with -Reupload to store it as secrets again."
    }
    $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
    if (-not $keytool -and $env:JAVA_HOME) {
        $keytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    }
    if (-not $keytool -or -not (Test-Path $keytool)) {
        $keytool = Get-ChildItem 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java', 'C:\Program Files\Microsoft' `
            -Filter keytool.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $keytool) { throw 'keytool was not found: install a JDK 17 or later.' }

    New-Item -ItemType Directory -Force $dir | Out-Null
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 32
    (New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })

    & $keytool -genkeypair -keystore $keystore -storetype PKCS12 `
        -storepass $password -keypass $password -alias release `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -dname 'CN=Sommelier Study Companion, O=Xaiando' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'keytool could not create the key.' }
    Set-Content -Path $passwordFile -Value $password -NoNewline
}

# Secrets go to gh on standard input, never on a command line.
[Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore)) |
    gh secret set ANDROID_KEYSTORE_BASE64 --repo $Repo
if ($LASTEXITCODE -ne 0) { throw 'gh could not store ANDROID_KEYSTORE_BASE64.' }
$password | gh secret set ANDROID_KEYSTORE_PASSWORD --repo $Repo
if ($LASTEXITCODE -ne 0) { throw 'gh could not store ANDROID_KEYSTORE_PASSWORD.' }

Write-Host "Stored the release key as $Repo's Actions secrets."
Write-Host "Back up the folder $dir. Without it, losing the secrets means reinstalling the app from scratch."

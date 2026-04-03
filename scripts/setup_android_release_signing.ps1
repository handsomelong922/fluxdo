param(
    [string]$Alias = "fluxdo",
    [string]$KeystorePassword,
    [string]$KeyPassword,
    [string]$KeystorePath = "android/app/upload-keystore.jks",
    [string]$KeyPropertiesPath = "android/key.properties",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function New-RandomPassword {
    param([int]$Length = 24)

    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*_-+="
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name. Install it and ensure it is on PATH."
    }
}

Require-Command "keytool"

if ([string]::IsNullOrWhiteSpace($KeystorePassword)) {
    $KeystorePassword = New-RandomPassword
}

if ([string]::IsNullOrWhiteSpace($KeyPassword)) {
    $KeyPassword = New-RandomPassword
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$keystoreFullPath = Join-Path $projectRoot $KeystorePath
$keyPropertiesFullPath = Join-Path $projectRoot $KeyPropertiesPath
$googleServicesPath = Join-Path $projectRoot "android/app/google-services.json"

if ((Test-Path $keystoreFullPath) -and -not $Force) {
    throw "Keystore already exists at $KeystorePath. Refusing to overwrite it without -Force."
}

$keystoreDir = Split-Path -Parent $keystoreFullPath
if (-not (Test-Path $keystoreDir)) {
    New-Item -ItemType Directory -Path $keystoreDir -Force | Out-Null
}

$dname = "CN=Fluxdo,O=Fluxdo,C=CN"

& keytool -genkeypair `
    -v `
    -keystore $keystoreFullPath `
    -storepass $KeystorePassword `
    -keypass $KeyPassword `
    -alias $Alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -dname $dname | Out-Null

$keyProperties = @"
storePassword=$KeystorePassword
keyPassword=$KeyPassword
keyAlias=$Alias
storeFile=upload-keystore.jks
"@

Set-Content -Path $keyPropertiesFullPath -Value $keyProperties -Encoding UTF8

$keystoreBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystoreFullPath))
$outputDir = Join-Path $projectRoot "build/android-signing"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Set-Content -Path (Join-Path $outputDir "ANDROID_KEYSTORE_BASE64.txt") -Value $keystoreBase64 -Encoding ASCII
Set-Content -Path (Join-Path $outputDir "ANDROID_KEY_PROPERTIES.txt") -Value $keyProperties -Encoding ASCII

if (Test-Path $googleServicesPath) {
    $googleServicesBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($googleServicesPath))
    Set-Content -Path (Join-Path $outputDir "GOOGLE_SERVICES_JSON.txt") -Value $googleServicesBase64 -Encoding ASCII
}

Write-Host ""
Write-Host "Generated release signing files:" -ForegroundColor Green
Write-Host "  $KeystorePath"
Write-Host "  $KeyPropertiesPath"
Write-Host ""
Write-Host "Exported GitHub secrets payloads:" -ForegroundColor Green
Write-Host "  build/android-signing/ANDROID_KEYSTORE_BASE64.txt"
Write-Host "  build/android-signing/ANDROID_KEY_PROPERTIES.txt"
if (Test-Path $googleServicesPath) {
    Write-Host "  build/android-signing/GOOGLE_SERVICES_JSON.txt"
}
Write-Host ""
Write-Host "Back up upload-keystore.jks and key.properties. Future update installs depend on keeping this signing key unchanged." -ForegroundColor Yellow

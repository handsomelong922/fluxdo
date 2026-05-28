# Configure local Android signing secrets for release builds.
# Usage: .\scripts\configure_android_signing.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$KeystorePath = Join-Path $ProjectRoot "fluxdo-key.jks"
$KeyPropertiesPath = Join-Path $ProjectRoot "android\key.properties"

function Read-SecretPlain {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

Write-Host "=== FluxDO Android signing setup ===" -ForegroundColor Cyan
Write-Host "Keystore: $KeystorePath" -ForegroundColor Gray
Write-Host "Output:   $KeyPropertiesPath" -ForegroundColor Gray

if (-not (Test-Path -LiteralPath $KeystorePath)) {
    throw "Keystore not found. Put fluxdo-key.jks in the project root first."
}

$keyAlias = Read-Host "keyAlias"
$storePassword = Read-SecretPlain "storePassword"
$keyPassword = Read-SecretPlain "keyPassword"

if ([string]::IsNullOrWhiteSpace($keyAlias)) {
    throw "keyAlias cannot be empty."
}
if ([string]::IsNullOrEmpty($storePassword)) {
    throw "storePassword cannot be empty."
}
if ([string]::IsNullOrEmpty($keyPassword)) {
    throw "keyPassword cannot be empty."
}

$content = @"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$keyAlias
storeFile=../../fluxdo-key.jks
"@

Set-Content -LiteralPath $KeyPropertiesPath -Value $content -Encoding ascii

Write-Host ""
Write-Host "Android signing is configured." -ForegroundColor Green
Write-Host "The generated key.properties file is ignored by git." -ForegroundColor Yellow

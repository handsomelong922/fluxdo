# Build a locally signed arm64 Android APK, including DOH proxy native libraries.
# Usage: .\scripts\build_local_apk.ps1
#        .\scripts\build_local_apk.ps1 -SkipDoh

param(
    [switch]$SkipDoh,
    [switch]$NoPubGet,
    [switch]$BuildWorkspaceMode
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$AsciiProjectBuildDir = Join-Path $env:TEMP "fluxdo_apk_workspace_$PID"
$KeyPropertiesPath = Join-Path $ProjectRoot "android\key.properties"
$KeystorePath = Join-Path $ProjectRoot "fluxdo-key.jks"
$GoogleServicesPath = Join-Path $ProjectRoot "android\app\google-services.json"
$AndroidLocalPropertiesPath = Join-Path $ProjectRoot "android\local.properties"
$GradleUserPropertiesPath = Join-Path $env:USERPROFILE ".gradle\gradle.properties"
$AndroidSdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$AndroidNdkHome = Join-Path $AndroidSdkRoot "ndk\25.2.9519653"
$AndroidStudioJbr = "C:\Program Files\Android\Android Studio\jbr"
$VsDevCmd = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
$RustDir = Join-Path $ProjectRoot "core\doh_proxy"
$DohProxyBuildDir = Join-Path $env:TEMP "fluxdo_doh_proxy_build"
$JniLibsArm64Dir = Join-Path $ProjectRoot "android\app\src\main\jniLibs\arm64-v8a"
$DohProxyArm64Source = Join-Path $DohProxyBuildDir "target\aarch64-linux-android\release\libdoh_proxy.so"
$DohProxyArm64Target = Join-Path $JniLibsArm64Dir "libdoh_proxy.so"
$DistDir = Join-Path $ProjectRoot "dist"
$ApkSource = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk"
$ApkTarget = Join-Path $DistDir "fluxdo-arm64-v8a-local.apk"
$PuroFlutterRoot = Join-Path $env:USERPROFILE ".puro\envs\fluxdo-env\flutter"
$FlutterSdkShim = Join-Path $env:TEMP "fluxdo_flutter_sdk_shim"
$PuroDart = Join-Path $PuroFlutterRoot "bin\cache\dart-sdk\bin\dart.exe"
$PuroFlutterTool = Join-Path $PuroFlutterRoot "packages\flutter_tools\bin\flutter_tools.dart"
$CargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
$CargoCmd = Join-Path $CargoBin "cargo.exe"
$RustupCmd = Join-Path $CargoBin "rustup.exe"
$CargoNdkCmd = Join-Path $CargoBin "cargo-ndk.exe"

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Resolve-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$PreferredPath
    )

    if ($PreferredPath -and (Test-Path -LiteralPath $PreferredPath)) {
        return $PreferredPath
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Required command '$Name' was not found."
}

function Import-VsDevEnvironment {
    param([Parameter(Mandatory = $true)][string]$VsDevCmdPath)

    if (-not (Test-Path -LiteralPath $VsDevCmdPath)) {
        throw "Visual Studio build environment was not found at $VsDevCmdPath."
    }

    Write-Host "Loading Visual Studio C++ build environment..." -ForegroundColor DarkGray
    $envLines = & cmd.exe /d /s /c "call `"$VsDevCmdPath`" >nul && set"
    foreach ($line in $envLines) {
        if ($line -match '^(?<name>[^=]+)=(?<value>.*)$') {
            Set-Item -Path "Env:$($Matches.name)" -Value $Matches.value
        }
    }
}

function Resolve-OpenSslConfig {
    if ($env:OPENSSL_CONF -and (Test-Path -LiteralPath $env:OPENSSL_CONF)) {
        return $env:OPENSSL_CONF
    }

    $candidates = @(
        "C:\ProgramData\miniconda3\Library\ssl\openssl.cnf",
        "C:\Program Files\Git\mingw64\ssl\openssl.cnf"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Test-ContainsNonAscii {
    param([Parameter(Mandatory = $true)][string]$Value)

    foreach ($char in $Value.ToCharArray()) {
        if ([int][char]$char -gt 127) {
            return $true
        }
    }

    return $false
}

function Assert-UnderTemp {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tempRoot = [System.IO.Path]::GetFullPath($env:TEMP)
    $target = [System.IO.Path]::GetFullPath($Path)
    if (-not $target.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate on path outside TEMP: $target"
    }
}

function Copy-DohProxySourceToBuildDir {
    Assert-UnderTemp $DohProxyBuildDir

    if (Test-Path -LiteralPath $DohProxyBuildDir) {
        Remove-Item -LiteralPath $DohProxyBuildDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DohProxyBuildDir -Force | Out-Null

    Get-ChildItem -LiteralPath $RustDir -Force |
        Where-Object { $_.Name -notin @("target", ".git") } |
        Copy-Item -Destination $DohProxyBuildDir -Recurse -Force
}

function Initialize-FlutterSdkShim {
    Assert-UnderTemp $FlutterSdkShim

    if (Test-Path -LiteralPath $FlutterSdkShim) {
        Remove-Item -LiteralPath $FlutterSdkShim -Recurse -Force
    }

    New-Item -ItemType Directory -Path (Join-Path $FlutterSdkShim "bin") -Force | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $FlutterSdkShim "packages") -Target (Join-Path $PuroFlutterRoot "packages") | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $FlutterSdkShim "bin\cache") -Target (Join-Path $PuroFlutterRoot "bin\cache") | Out-Null

    $flutterBat = @"
@echo off
set "FLUTTER_ROOT=$PuroFlutterRoot"
"$PuroDart" "$PuroFlutterTool" %*
exit /B %ERRORLEVEL%
"@
    Set-Content -LiteralPath (Join-Path $FlutterSdkShim "bin\flutter.bat") -Value $flutterBat -Encoding ascii
}

function Ensure-PropertiesEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $line = "$Name=$Value"
    $pattern = "^\s*$([regex]::Escape($Name))\s*="
    $lines = @()
    if (Test-Path -LiteralPath $Path) {
        $lines = @(Get-Content -LiteralPath $Path)
    }

    $found = $false
    $updated = foreach ($existingLine in $lines) {
        if ($existingLine -match $pattern) {
            $found = $true
            $line
        } else {
            $existingLine
        }
    }

    if (-not $found) {
        $updated += $line
    }

    Set-Content -LiteralPath $Path -Value $updated -Encoding ascii
}

function Sync-KeyAliasFromKeystore {
    $keytool = Join-Path $AndroidStudioJbr "bin\keytool.exe"
    if (-not (Test-Path -LiteralPath $keytool)) {
        throw "keytool.exe was not found at $keytool."
    }

    $props = @{}
    foreach ($line in Get-Content -LiteralPath $KeyPropertiesPath) {
        if ($line -match '^\s*([^#][^=]+?)\s*=\s*(.*)$') {
            $props[$Matches[1].Trim()] = $Matches[2]
        }
    }

    if (-not $props.ContainsKey("storePassword") -or -not $props.ContainsKey("keyAlias")) {
        return
    }

    $keytoolOutput = & $keytool -list -keystore $KeystorePath -storepass $props["storePassword"] 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect Android keystore. Check the configured store password."
    }

    $aliases = @()
    foreach ($line in $keytoolOutput) {
        if ($line -match '^Alias name:\s*(.+)$') {
            $aliases += $Matches[1].Trim()
        } elseif ($line -match '^\s*([^,\uFF0C]+)[,\uFF0C].*PrivateKeyEntry') {
            $aliases += $Matches[1].Trim()
        }
    }

    $aliases = @($aliases | Where-Object { $_ } | Select-Object -Unique)
    if ($aliases -contains $props["keyAlias"]) {
        return
    }

    if ($aliases.Count -eq 1) {
        Ensure-PropertiesEntry $KeyPropertiesPath "keyAlias" $aliases[0]
        Write-Host "Android signing keyAlias was synchronized with the keystore." -ForegroundColor DarkGray
        return
    }

    throw "Configured keyAlias was not found in the keystore. Re-run scripts\configure_android_signing.ps1 with the correct alias."
}

function Run-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Action
}

function Invoke-InAsciiProjectWorkspace {
    Assert-UnderTemp $AsciiProjectBuildDir

    Run-Step "Mirror project to ASCII build workspace" {
        if (Test-Path -LiteralPath $AsciiProjectBuildDir) {
            Remove-Item -LiteralPath $AsciiProjectBuildDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $AsciiProjectBuildDir -Force | Out-Null

        $excludeDirs = @(
            ".git",
            ".trellis",
            ".agents",
            ".claude",
            ".dart_tool",
            "build",
            "dist",
            "target"
        )
        $robocopyArgs = @(
            $ProjectRoot,
            $AsciiProjectBuildDir,
            "/MIR",
            "/XD"
        ) + $excludeDirs + @(
            "/NFL",
            "/NDL",
            "/NJH",
            "/NJS",
            "/NP"
        )
        & robocopy.exe @robocopyArgs
        if ($LASTEXITCODE -gt 7) {
            throw "Failed to mirror project to ASCII build workspace."
        }
    }

    $childScript = Join-Path $AsciiProjectBuildDir "scripts\build_local_apk.ps1"
    $childArgs = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $childScript,
        "-BuildWorkspaceMode"
    )
    if ($SkipDoh) {
        $childArgs += "-SkipDoh"
    }
    if ($NoPubGet) {
        $childArgs += "-NoPubGet"
    }

    Run-Step "Build APK in ASCII workspace" {
        & powershell.exe @childArgs
        if ($LASTEXITCODE -ne 0) {
            throw "ASCII workspace APK build failed."
        }
    }

    $workspaceApk = Join-Path $AsciiProjectBuildDir "dist\fluxdo-arm64-v8a-local.apk"
    if (-not (Test-Path -LiteralPath $workspaceApk)) {
        throw "APK was not produced in ASCII build workspace."
    }

    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
    Copy-Item -LiteralPath $workspaceApk -Destination $ApkTarget -Force

    Write-Host ""
    Write-Host "APK build complete:" -ForegroundColor Green
    Write-Host $ApkTarget -ForegroundColor Green
}

Set-Location -LiteralPath $ProjectRoot

if (-not (Test-Path -LiteralPath $KeystorePath)) {
    throw "Missing fluxdo-key.jks in project root."
}
if (-not (Test-Path -LiteralPath $KeyPropertiesPath)) {
    Write-Host "Android signing is not configured yet." -ForegroundColor Yellow
    & (Join-Path $ScriptDir "configure_android_signing.ps1")
}
Sync-KeyAliasFromKeystore

if (-not $BuildWorkspaceMode -and (Test-ContainsNonAscii $ProjectRoot)) {
    Invoke-InAsciiProjectWorkspace
    exit 0
}

$DartCmd = Resolve-Tool "dart" $PuroDart
if (-not (Test-Path -LiteralPath $PuroFlutterTool)) {
    throw "Flutter tool was not found at $PuroFlutterTool"
}
if (-not (Test-Path -LiteralPath $AndroidSdkRoot)) {
    throw "Android SDK was not found at $AndroidSdkRoot. Install it with: winget install Google.AndroidCLI"
}
if (-not (Test-Path -LiteralPath $AndroidNdkHome)) {
    throw "Android NDK 25.2.9519653 was not found at $AndroidNdkHome."
}
if (-not (Test-Path -LiteralPath $AndroidStudioJbr)) {
    throw "Android Studio JBR was not found at $AndroidStudioJbr."
}
if (-not (Test-Path -LiteralPath $CargoCmd)) {
    throw "cargo was not found at $CargoCmd. Install Rustup first."
}
if (-not (Test-Path -LiteralPath $RustupCmd)) {
    throw "rustup was not found at $RustupCmd. Install Rustup first."
}
Import-VsDevEnvironment $VsDevCmd
if (-not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
    throw "MSVC linker link.exe was not available after loading the Visual Studio build environment."
}

$env:ANDROID_HOME = $AndroidSdkRoot
$env:ANDROID_SDK_ROOT = $AndroidSdkRoot
$env:ANDROID_NDK_HOME = $AndroidNdkHome
$env:JAVA_HOME = $AndroidStudioJbr
$env:Path = "$CargoBin;$AndroidSdkRoot\platform-tools;$AndroidStudioJbr\bin;$env:Path"

if (-not $SkipDoh) {
    if (-not (Get-Command openssl.exe -ErrorAction SilentlyContinue)) {
        throw "openssl.exe was not found in PATH. It is required to generate DOH proxy CA certificates."
    }

    $opensslConfig = Resolve-OpenSslConfig
    if ($opensslConfig) {
        $env:OPENSSL_CONF = $opensslConfig
        Write-Host "Using OpenSSL config: $opensslConfig" -ForegroundColor DarkGray
    }
}

Run-Step "Configure Flutter SDK shim" {
    Initialize-FlutterSdkShim
}

Run-Step "Configure Android local.properties" {
    $sdkDir = $AndroidSdkRoot.Replace("\", "/")
    $flutterDir = $FlutterSdkShim.Replace("\", "/")
    @"
sdk.dir=$sdkDir
flutter.sdk=$flutterDir
"@ | Set-Content -LiteralPath $AndroidLocalPropertiesPath -Encoding ascii
}

Run-Step "Configure Gradle user properties" {
    Ensure-PropertiesEntry $GradleUserPropertiesPath "android.overridePathCheck" "true"
}

if (-not $NoPubGet) {
    Run-Step "Flutter pub get" {
        Invoke-Native { & $DartCmd $PuroFlutterTool pub get } "Flutter pub get failed."
    }
}

Run-Step "Merge l10n ARB files" {
    Invoke-Native { & $DartCmd tool/merge_l10n.dart } "L10n merge failed."
}

if (-not (Test-Path -LiteralPath $GoogleServicesPath)) {
    Run-Step "Create dummy google-services.json" {
        $googleServices = '{"project_info":{"project_number":"123","project_id":"dummy"},"client":[{"client_info":{"mobilesdk_app_id":"1:123:android:abc","android_client_info":{"package_name":"com.github.lingyan000.fluxdo"}},"api_key":[{"current_key":"dummy"}]}],"configuration_version":"1"}'
        Set-Content -LiteralPath $GoogleServicesPath -Value $googleServices -Encoding ascii
    }
}

if (-not $SkipDoh) {
    Run-Step "Install cargo-ndk if needed" {
        if (-not (Test-Path -LiteralPath $CargoNdkCmd)) {
            Invoke-Native { & $CargoCmd install cargo-ndk } "cargo-ndk installation failed."
        }
    }

    Run-Step "Install Rust Android arm64 target if needed" {
        $installedTargets = & $RustupCmd target list --installed
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to list installed Rust targets."
        }
        if ($installedTargets -notcontains "aarch64-linux-android") {
            Invoke-Native { & $RustupCmd target add aarch64-linux-android } "Failed to install Rust Android arm64 target."
        }
    }

    Run-Step "Generate and sync DOH certificates" {
        Push-Location $RustDir
        try {
            Invoke-Native { & $CargoCmd run --bin gen_ca } "Failed to generate DOH proxy CA certificates."
        } finally {
            Pop-Location
        }
        & (Join-Path $ScriptDir "sync_cert_resources.ps1")
    }

    Run-Step "Build Android DOH proxy native library (arm64-v8a)" {
        Copy-DohProxySourceToBuildDir
        Push-Location $DohProxyBuildDir
        try {
            Invoke-Native { & $CargoCmd ndk -t arm64-v8a --platform 28 build --release --features ech } "Failed to build DOH proxy native library."
        } finally {
            Pop-Location
        }

        if (-not (Test-Path -LiteralPath $DohProxyArm64Source)) {
            throw "DOH proxy library was not produced at $DohProxyArm64Source"
        }

        New-Item -ItemType Directory -Path $JniLibsArm64Dir -Force | Out-Null
        Copy-Item -LiteralPath $DohProxyArm64Source -Destination $DohProxyArm64Target -Force
    }
} else {
    Write-Host ""
    Write-Host "==> Skipping DOH proxy build" -ForegroundColor Yellow
}

Run-Step "Build signed Android APK" {
    $flutterBuildArgs = @(
        "build",
        "apk",
        "--release",
        "--target-platform",
        "android-arm64",
        "--dart-define=cronetHttpNoPlay=true"
    )
    if (-not $NoPubGet) {
        $flutterBuildArgs += "--no-pub"
    }

    Invoke-Native { & $DartCmd $PuroFlutterTool @flutterBuildArgs } "Flutter APK build failed."
}

if (-not (Test-Path -LiteralPath $ApkSource)) {
    throw "APK was not produced at $ApkSource"
}

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
Copy-Item -LiteralPath $ApkSource -Destination $ApkTarget -Force

Write-Host ""
Write-Host "APK build complete:" -ForegroundColor Green
Write-Host $ApkTarget -ForegroundColor Green

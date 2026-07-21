param(
    [string]$Version = "10.0.28000.2270",
    [string]$InstallRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $env:LOCALAPPDATA "Token Orb\SigningTools\WindowsSDK"
}
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)

$packageId = "microsoft.windows.sdk.buildtools"
$fileStem = "$packageId.$Version"
$packageUrl = "https://api.nuget.org/v3-flatcontainer/$packageId/$Version/$fileStem.nupkg"
$nuGetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
$cacheRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.tools\downloads"))
$packagePath = Join-Path $cacheRoot "$fileStem.nupkg"
$nuGetPath = Join-Path $cacheRoot "nuget.exe"
$versionRoot = Join-Path $InstallRoot $Version

New-Item -ItemType Directory -Force $cacheRoot | Out-Null
New-Item -ItemType Directory -Force $InstallRoot | Out-Null

function Invoke-ResumableDownload([string]$Uri, [string]$Destination) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $curl) {
        throw "curl.exe is required for resumable downloads."
    }

    & $curl.Source `
        --fail `
        --location `
        --retry 5 `
        --retry-all-errors `
        --retry-delay 2 `
        --continue-at - `
        --output $Destination `
        $Uri
    if ($LASTEXITCODE -ne 0) {
        throw "Download did not complete. Run this script again to resume: $Uri"
    }
}

function Get-ValidMicrosoftSignature([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        return $null
    }
    if ($signature.SignerCertificate.Subject -notmatch "Microsoft") {
        return $null
    }
    return $signature
}

function Install-VerifiedNuGetCli {
    $signature = Get-ValidMicrosoftSignature $nuGetPath
    if ($signature) {
        return $signature
    }

    if (Test-Path -LiteralPath $nuGetPath) {
        Remove-Item -Force -LiteralPath $nuGetPath
    }
    $partialPath = "$nuGetPath.partial"
    Write-Host "Downloading the NuGet.org recommended CLI (resumable)..."
    Invoke-ResumableDownload $nuGetUrl $partialPath

    $signature = Get-ValidMicrosoftSignature $partialPath
    if (-not $signature) {
        Remove-Item -Force -LiteralPath $partialPath
        throw "The downloaded NuGet CLI did not have a valid Microsoft Authenticode signature."
    }

    Move-Item -Force -LiteralPath $partialPath -Destination $nuGetPath
    return $signature
}

function Test-NuGetPackageSignature([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $verifyOutput = @(& $nuGetPath verify -Signatures $Path `
        -NonInteractive -ForceEnglishOutput -Verbosity detailed 2>&1)
    $verifyExitCode = $LASTEXITCODE
    $verifyOutput | ForEach-Object { Write-Host $_ }
    return ($verifyExitCode -eq 0)
}

$nuGetSignature = Install-VerifiedNuGetCli
Write-Host "NuGet CLI publisher: $($nuGetSignature.SignerCertificate.Subject)"

if (-not (Test-NuGetPackageSignature $packagePath)) {
    if (Test-Path -LiteralPath $packagePath) {
        Remove-Item -Force -LiteralPath $packagePath
    }
    $partialPackagePath = "$packagePath.partial"
    Write-Host "Downloading Microsoft Windows SDK Build Tools $Version (resumable)..."
    Invoke-ResumableDownload $packageUrl $partialPackagePath

    # NuGet's verifier expects the .nupkg extension, so verify a hard copy of the
    # completed partial download before promoting it into the cache.
    $verificationCopy = "$packagePath.verifying.nupkg"
    Copy-Item -Force -LiteralPath $partialPackagePath -Destination $verificationCopy
    try {
        if (-not (Test-NuGetPackageSignature $verificationCopy)) {
            Remove-Item -Force -LiteralPath $partialPackagePath
            throw "The Windows SDK Build Tools package signature verification failed."
        }
        Move-Item -Force -LiteralPath $partialPackagePath -Destination $packagePath
    }
    finally {
        Remove-Item -Force -LiteralPath $verificationCopy -ErrorAction SilentlyContinue
    }
}

$stagingRoot = Join-Path $InstallRoot (".staging-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $stagingRoot | Out-Null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $stagingRoot)

    $nuspec = Get-ChildItem -LiteralPath $stagingRoot -Filter "*.nuspec" | Select-Object -First 1
    if (-not $nuspec) {
        throw "The package did not contain NuGet metadata."
    }
    [xml]$metadata = Get-Content -Raw -LiteralPath $nuspec.FullName
    $actualId = [string]$metadata.package.metadata.id
    $actualVersion = [string]$metadata.package.metadata.version
    if ($actualId -ne "Microsoft.Windows.SDK.BuildTools" -or $actualVersion -ne $Version) {
        throw "Unexpected package identity: $actualId $actualVersion"
    }

    $signTool = Get-ChildItem -Path $stagingRoot -Recurse -Filter signtool.exe `
        | Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } `
        | Sort-Object FullName -Descending `
        | Select-Object -First 1
    if (-not $signTool) {
        throw "The official package did not contain an x64 signtool.exe."
    }

    $signToolSignature = Get-ValidMicrosoftSignature $signTool.FullName
    if (-not $signToolSignature) {
        throw "signtool.exe did not have a valid Microsoft Authenticode signature."
    }

    if (Test-Path -LiteralPath $versionRoot) {
        $resolvedInstallRoot = $InstallRoot.TrimEnd('\') + '\'
        $resolvedVersionRoot = [System.IO.Path]::GetFullPath($versionRoot)
        if (-not $resolvedVersionRoot.StartsWith($resolvedInstallRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to replace a path outside the intended install root: $resolvedVersionRoot"
        }
        Remove-Item -Recurse -Force -LiteralPath $resolvedVersionRoot
    }
    Move-Item -LiteralPath $stagingRoot -Destination $versionRoot
    $stagingRoot = $null
}
finally {
    if ($stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) {
        Remove-Item -Recurse -Force -LiteralPath $stagingRoot
    }
}

$signTool = Get-ChildItem -Path $versionRoot -Recurse -Filter signtool.exe `
    | Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } `
    | Sort-Object FullName -Descending `
    | Select-Object -First 1
$signature = Get-ValidMicrosoftSignature $signTool.FullName
if (-not $signature) {
    throw "The installed signtool.exe failed its post-install signature check."
}

$signToolDirectory = $signTool.Directory.FullName
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($userPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if (-not ($pathEntries | Where-Object {
    [string]::Equals($_.TrimEnd('\'), $signToolDirectory.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
})) {
    $updatedPath = (@($pathEntries) + $signToolDirectory) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $updatedPath, "User")
}
if (-not (($env:Path -split ";") -contains $signToolDirectory)) {
    $env:Path = $env:Path + ";" + $signToolDirectory
}

Write-Host "Installed SignTool: $($signTool.FullName)"
Write-Host "Version: $($signTool.VersionInfo.FileVersion)"
Write-Host "Publisher: $($signature.SignerCertificate.Subject)"

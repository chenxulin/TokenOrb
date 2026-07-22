param(
    [string]$OutputDirectory = "",
    [switch]$QaMode
)

$ErrorActionPreference = "Stop"
$productName = "Token Orb"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent (Split-Path -Parent $projectRoot)) "outputs"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$compilerCandidates = @(
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$compiler = $compilerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "Windows C# compiler was not found."
}

$frameworkDirectory = Split-Path -Parent $compiler
$sourceDirectory = Join-Path $projectRoot "src"
$buildDirectory = Join-Path $projectRoot "build"
New-Item -ItemType Directory -Force $buildDirectory | Out-Null
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null

function New-TokenOrbIcon([string]$Path) {
    Add-Type -AssemblyName System.Drawing

    $bitmap = New-Object System.Drawing.Bitmap 64, 64
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $background = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 239, 248, 255))
    $orbitPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 87, 135, 165)), 3.0
    $coreBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 47, 164, 235))
    $corePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 53, 128, 174)), 2.0
    $dotBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 68, 177, 235))
    $highlightBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235, 255, 255, 255))
    $pngStream = New-Object System.IO.MemoryStream
    $writer = $null
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.FillEllipse($background, 2, 2, 60, 60)

        foreach ($angle in @(0.0, 60.0, 120.0)) {
            $state = $graphics.Save()
            $graphics.TranslateTransform(32.0, 32.0)
            $graphics.RotateTransform($angle)
            $graphics.DrawEllipse($orbitPen, -24.0, -10.0, 48.0, 20.0)
            $graphics.Restore($state)
        }

        $graphics.FillEllipse($coreBrush, 23, 23, 18, 18)
        $graphics.DrawEllipse($corePen, 23, 23, 18, 18)
        $graphics.FillEllipse($highlightBrush, 27, 26, 5, 5)
        $graphics.FillEllipse($dotBrush, 51, 22, 7, 7)
        $graphics.FillEllipse($dotBrush, 8, 43, 6, 6)

        $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
        [byte[]]$pngBytes = $pngStream.ToArray()
        $fileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
        $writer = New-Object System.IO.BinaryWriter $fileStream
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]1)
        $writer.Write([byte]64)
        $writer.Write([byte]64)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$pngBytes.Length)
        $writer.Write([uint32]22)
        $writer.Write($pngBytes)
    }
    finally {
        if ($writer) { $writer.Dispose() }
        $pngStream.Dispose()
        $highlightBrush.Dispose()
        $dotBrush.Dispose()
        $corePen.Dispose()
        $coreBrush.Dispose()
        $orbitPen.Dispose()
        $background.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-WixToolset {
    $toolsRoot = Join-Path $projectRoot ".tools"
    $wixRoot = Join-Path $toolsRoot "wix3141"
    $candlePath = Join-Path $wixRoot "candle.exe"
    $lightPath = Join-Path $wixRoot "light.exe"
    $darkPath = Join-Path $wixRoot "dark.exe"
    $utilExtensionPath = Join-Path $wixRoot "WixUtilExtension.dll"
    if ((Test-Path $candlePath) -and
        (Test-Path $lightPath) -and
        (Test-Path $darkPath) -and
        (Test-Path $utilExtensionPath)) {
        return [pscustomobject]@{
            Candle = $candlePath
            Light = $lightPath
            Dark = $darkPath
            UtilExtension = $utilExtensionPath
        }
    }

    $downloadDirectory = Join-Path $toolsRoot "downloads"
    New-Item -ItemType Directory -Force $downloadDirectory | Out-Null
    New-Item -ItemType Directory -Force $wixRoot | Out-Null
    $archivePath = Join-Path $downloadDirectory "wix314-binaries.zip"
    $downloadUrl = "https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip"
    $expectedSha256 = "6ac824e1642d6f7277d0ed7ea09411a508f6116ba6fae0aa5f2c7daa2ff43d31"

    $archiveValid = $false
    if (Test-Path $archivePath) {
        $archiveValid = (Get-FileHash -Algorithm SHA256 $archivePath).Hash.ToLowerInvariant() -eq $expectedSha256
    }
    if (-not $archiveValid) {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $curl) {
            throw "curl.exe is required to download the WiX build tools."
        }

        Write-Host "Downloading WiX Toolset v3.14.1 (resumable)..."
        & $curl.Source --fail --location --retry 5 --retry-delay 2 --continue-at - --output $archivePath $downloadUrl
        if ($LASTEXITCODE -ne 0) {
            throw "WiX download was interrupted. Re-run build.ps1 to resume the existing partial download."
        }

        $actualSha256 = (Get-FileHash -Algorithm SHA256 $archivePath).Hash.ToLowerInvariant()
        if ($actualSha256 -ne $expectedSha256) {
            Remove-Item -Force -LiteralPath $archivePath
            throw "WiX archive SHA-256 verification failed."
        }
    }

    Expand-Archive -Force -LiteralPath $archivePath -DestinationPath $wixRoot
    if (-not (Test-Path $candlePath) -or
        -not (Test-Path $lightPath) -or
        -not (Test-Path $darkPath) -or
        -not (Test-Path $utilExtensionPath)) {
        throw "WiX Toolset extraction did not produce the required compiler, linker, decompiler, and utility extension."
    }
    return [pscustomobject]@{
        Candle = $candlePath
        Light = $lightPath
        Dark = $darkPath
        UtilExtension = $utilExtensionPath
    }
}

$legacyOutputNames = @(
    "CodexQuotaBall.exe",
    "CodexQuotaBall.zip",
    "CodexQuotaBall-source.zip",
    "CodexQuotaBall-README.md",
    "CodexQuotaBall.sha256",
    "Token Orb.exe",
    "Token Orb.msi",
    "Token Orb.zip",
    "Token Orb.source.zip",
    "Token Orb.md",
    "Token Orb.sha256",
    "Token Orb.wixpdb"
)
if (-not $QaMode) {
    foreach ($legacyName in $legacyOutputNames) {
        $legacyPath = Join-Path $OutputDirectory $legacyName
        if (Test-Path $legacyPath) {
            Remove-Item -Force -LiteralPath $legacyPath
        }
    }
}

$iconPath = Join-Path $buildDirectory "TokenOrb.ico"
New-TokenOrbIcon $iconPath

function Resolve-FrameworkAssembly([string]$Name) {
    $local = Join-Path $frameworkDirectory $Name
    if (Test-Path $local) {
        return $local
    }

    $gacRoots = @(
        "C:\Windows\Microsoft.NET\assembly\GAC_MSIL",
        "C:\Windows\Microsoft.NET\assembly\GAC_64",
        "C:\Windows\Microsoft.NET\assembly\GAC_32"
    )
    foreach ($gacRoot in $gacRoots) {
        $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($Name)
        $assemblyRoot = Join-Path $gacRoot $assemblyName
        if (Test-Path $assemblyRoot) {
            $match = Get-ChildItem $assemblyRoot -Recurse -Filter $Name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }
    }
    throw "Required assembly was not found: $Name"
}

$referenceNames = @(
    "System.dll",
    "System.Core.dll",
    "System.Web.Extensions.dll",
    "System.Xaml.dll",
    "WindowsBase.dll",
    "PresentationCore.dll",
    "PresentationFramework.dll",
    "System.Windows.Forms.dll",
    "System.Drawing.dll"
)
$references = $referenceNames | ForEach-Object { Resolve-FrameworkAssembly $_ }
$referenceByName = @{}
foreach ($reference in $references) {
    $referenceByName[[System.IO.Path]::GetFileName($reference)] = $reference
}

$applicationSources = @(
    (Join-Path $sourceDirectory "AppIdentity.cs"),
    (Join-Path $sourceDirectory "ModelsAndParser.cs"),
    (Join-Path $sourceDirectory "CodexAuthStateTracker.cs"),
    (Join-Path $sourceDirectory "RealtimeRetryPolicy.cs"),
    (Join-Path $sourceDirectory "AppServerClient.cs"),
    (Join-Path $sourceDirectory "QuotaService.cs"),
    (Join-Path $sourceDirectory "BallPositioning.cs"),
    (Join-Path $sourceDirectory "UiControls.cs"),
    (Join-Path $sourceDirectory "UiHelpers.cs"),
    (Join-Path $sourceDirectory "FollowCodexStartupBehavior.cs"),
    (Join-Path $sourceDirectory "CodexProcessMonitor.cs"),
    (Join-Path $sourceDirectory "AppearanceWindow.cs"),
    (Join-Path $sourceDirectory "AboutWindow.cs"),
    (Join-Path $sourceDirectory "DetailWindow.cs"),
    (Join-Path $sourceDirectory "MainWindow.cs"),
    (Join-Path $sourceDirectory "Program.cs")
)

$applicationPath = if ($QaMode) {
    Join-Path $buildDirectory "TokenOrb-QA.exe"
} else {
    Join-Path $OutputDirectory "TokenOrb.exe"
}
$compileArguments = @(
    "/nologo",
    "/target:winexe",
    "/platform:anycpu",
    "/optimize+",
    "/win32icon:$iconPath",
    "/out:$applicationPath"
)
if ($QaMode) {
    $compileArguments += "/define:QA"
}
$compileArguments += $references | ForEach-Object { "/reference:$_" }
$compileArguments += $applicationSources

$pdbPath = [System.IO.Path]::ChangeExtension($applicationPath, ".pdb")
if (Test-Path $pdbPath) {
    Remove-Item -Force -LiteralPath $pdbPath
}
& $compiler $compileArguments
if ($LASTEXITCODE -ne 0) {
    throw "Application compilation failed with exit code $LASTEXITCODE"
}

$testPath = Join-Path $buildDirectory "TokenOrb.Tests.exe"
$testArguments = @(
    "/nologo",
    "/target:exe",
    "/platform:anycpu",
    "/optimize+",
    "/main:CodexQuotaBall.ParserTests",
    "/out:$testPath",
    "/reference:$($referenceByName['System.dll'])",
    "/reference:$($referenceByName['System.Core.dll'])",
    "/reference:$($referenceByName['System.Xaml.dll'])",
    "/reference:$($referenceByName['WindowsBase.dll'])",
    "/reference:$($referenceByName['PresentationCore.dll'])",
    "/reference:$($referenceByName['PresentationFramework.dll'])",
    "/reference:$($referenceByName['System.Web.Extensions.dll'])",
    (Join-Path $sourceDirectory "AppIdentity.cs"),
    (Join-Path $sourceDirectory "ModelsAndParser.cs"),
    (Join-Path $sourceDirectory "CodexAuthStateTracker.cs"),
    (Join-Path $sourceDirectory "RealtimeRetryPolicy.cs"),
    (Join-Path $sourceDirectory "BallPositioning.cs"),
    (Join-Path $sourceDirectory "UiControls.cs"),
    (Join-Path $sourceDirectory "FollowCodexStartupBehavior.cs"),
    (Join-Path $sourceDirectory "CodexProcessMonitor.cs"),
    (Join-Path $sourceDirectory "ParserTests.cs")
)

& $compiler $testArguments
if ($LASTEXITCODE -ne 0) {
    throw "Parser test compilation failed with exit code $LASTEXITCODE"
}
& $testPath
if ($LASTEXITCODE -ne 0) {
    throw "Parser tests failed with exit code $LASTEXITCODE"
}

if ($QaMode) {
    Write-Host "QA build: $applicationPath"
    exit 0
}

$readmeSource = Join-Path $projectRoot "README.md"
$readmeOutput = Join-Path $OutputDirectory "TokenOrb.md"
Copy-Item -Force $readmeSource $readmeOutput

$wix = Get-WixToolset
$wixSource = Join-Path (Join-Path $projectRoot "installer") "TokenOrb.wxs"
[xml]$wixDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $wixSource
$wixNamespace = New-Object System.Xml.XmlNamespaceManager($wixDocument.NameTable)
$wixNamespace.AddNamespace("w", "http://schemas.microsoft.com/wix/2006/wi")
$product = $wixDocument.SelectSingleNode("//w:Product", $wixNamespace)
$majorUpgrade = $wixDocument.SelectSingleNode("//w:Product/w:MajorUpgrade", $wixNamespace)
$setStopCommand = $wixDocument.SelectSingleNode(
    "//w:Product/w:CustomAction[@Id='SetStopTokenOrbCommand']",
    $wixNamespace)
$stopProcesses = $wixDocument.SelectSingleNode(
    "//w:Product/w:CustomAction[@Id='StopTokenOrbProcesses']",
    $wixNamespace)
$stopSequence = $wixDocument.SelectSingleNode(
    "//w:Product/w:InstallExecuteSequence/w:Custom[@Action='StopTokenOrbProcesses']",
    $wixNamespace)
if ((-not $product) -or ($product.Id -ne "*")) {
    throw "MSI Product Id must be '*' so every release receives a new ProductCode."
}
if ($product.UpgradeCode -ne "{E2EE802B-B7DD-4436-ADF1-A3DF49DCD07A}") {
    throw "MSI UpgradeCode must remain stable so new releases can find installed versions."
}
if ((-not $majorUpgrade) -or
    ($majorUpgrade.Schedule -ne "afterInstallInitialize") -or
    ($majorUpgrade.AllowSameVersionUpgrades -ne "yes")) {
    throw "MSI must remove related versions before installation and support same-version replacement builds."
}
if ((-not $setStopCommand) -or
    ($setStopCommand.Property -ne "WixQuietExecCmdLine") -or
    ($setStopCommand.Value -notmatch "taskkill\.exe") -or
    ($setStopCommand.Value -notmatch "/IM TokenOrb\.exe") -or
    (-not $stopProcesses) -or
    ($stopProcesses.BinaryKey -ne "WixCA") -or
    ($stopProcesses.DllEntry -ne "WixQuietExec") -or
    ($stopProcesses.Return -ne "ignore") -or
    (-not $stopSequence) -or
    ($stopSequence.Before -ne "InstallValidate") -or
    ($stopSequence.InnerText -notmatch "WIX_UPGRADE_DETECTED")) {
    throw "MSI must close a running Token Orb before replacing an installed version."
}
$identitySource = Get-Content -Raw -LiteralPath (Join-Path $sourceDirectory "AppIdentity.cs")
$protocolVersionMatch = [regex]::Match(
    $identitySource,
    'ProtocolVersion\s*=\s*"([^"]+)"')
if ((-not $protocolVersionMatch.Success) -or
    ($product.Version -ne $protocolVersionMatch.Groups[1].Value)) {
    throw "MSI Product Version must match AppIdentity.ProtocolVersion."
}
$autoStartValue = $wixDocument.SelectSingleNode(
    "//w:Component[@Id='TokenOrbAutoStartComponent']/w:RegistryValue[@Name='Token Orb']",
    $wixNamespace)
if ((-not $autoStartValue) -or
    ($autoStartValue.KeyPath -ne "yes") -or
    ($autoStartValue.Value -notlike "*--watch*")) {
    throw "MSI must track the Token Orb --watch login entry as its own component key path."
}
$wixObject = Join-Path $buildDirectory "TokenOrb.wixobj"
$msiPath = Join-Path $OutputDirectory "TokenOrb.msi"
if (Test-Path $wixObject) {
    Remove-Item -Force -LiteralPath $wixObject
}
$candleArguments = @(
    "-nologo",
    "-arch", "x86",
    "-ext", $wix.UtilExtension,
    "-dTokenOrbExe=$applicationPath",
    "-dTokenOrbIcon=$iconPath",
    "-out", $wixObject,
    $wixSource
)
$candleExecutable = $wix.Candle
& $candleExecutable $candleArguments
if ($LASTEXITCODE -ne 0) {
    throw "MSI source compilation failed with exit code $LASTEXITCODE"
}
# ICE91 warns for files in a user-profile directory even when the package is
# intentionally declared per-user. ICE61 warns because same-version replacement
# is deliberately enabled so development builds can upgrade without a manual
# uninstall. Keep every other MSI consistency check on.
$lightArguments = @(
    "-nologo",
    "-ext", $wix.UtilExtension,
    "-sice:ICE91",
    "-sice:ICE61",
    "-spdb",
    "-out", $msiPath,
    $wixObject
)
$lightExecutable = $wix.Light
& $lightExecutable $lightArguments
if ($LASTEXITCODE -ne 0) {
    throw "MSI linking or validation failed with exit code $LASTEXITCODE"
}

$packagePath = Join-Path $OutputDirectory "TokenOrb.zip"
Compress-Archive -Force -Path $applicationPath, $readmeOutput -DestinationPath $packagePath

$sourcePackagePath = Join-Path $OutputDirectory "TokenOrb.source.zip"
$sourceItems = @(
    (Join-Path $projectRoot "src"),
    (Join-Path $projectRoot "installer"),
    (Join-Path $projectRoot ".github"),
    (Join-Path $projectRoot "tools"),
    $readmeSource,
    (Join-Path $projectRoot "LICENSE"),
    (Join-Path $projectRoot ".gitignore"),
    $MyInvocation.MyCommand.Path
) | Where-Object { Test-Path -LiteralPath $_ }
Compress-Archive -Force -Path $sourceItems -DestinationPath $sourcePackagePath

$hashTargets = @($applicationPath, $msiPath, $packagePath, $sourcePackagePath, $readmeOutput)
$hashLines = $hashTargets | ForEach-Object {
    $hash = Get-FileHash -Algorithm SHA256 $_
    $hash.Hash.ToLowerInvariant() + "  " + [System.IO.Path]::GetFileName($_)
}
$hashPath = Join-Path $OutputDirectory "TokenOrb.sha256"
Set-Content -Encoding ASCII -Path $hashPath -Value $hashLines

Write-Host "Built: $applicationPath"
Write-Host "Installer: $msiPath"
Write-Host "Package: $packagePath"
Write-Host "Checksums: $hashPath"

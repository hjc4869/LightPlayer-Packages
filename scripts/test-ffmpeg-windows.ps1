param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Target,
    [string]$ArtifactsDirectory,
    [string]$PackageSource,
    [string]$PackageVersion = '0.0.0-windows-test',
    [switch]$Hardware
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$architecture = $Target.Substring(4)
if ($env:VSCMD_ARG_TGT_ARCH -ne $architecture) {
    throw "Initialize the Visual Studio $architecture developer environment before running this test."
}
if (!$ArtifactsDirectory) {
    $ArtifactsDirectory = Join-Path $repoRoot "artifacts/ffmpeg-$Target"
}
$testRoot = Join-Path $repoRoot "artifacts/tests/ffmpeg-$Target"
$sharedRoot = Join-Path $testRoot 'shared'
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

function Invoke-Native {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable failed with exit code $LASTEXITCODE"
    }
}

$libraryNames = @(
    'avcodec', 'avdevice', 'avfilter', 'avformat', 'avutil', 'swresample', 'swscale',
    'dav1d', 'jxl', 'jxl_cms', 'jxl_threads', 'hwy', 'brotlicommon', 'brotlidec',
    'brotlienc', 'xml2', 'zlib'
)
$libraries = @($libraryNames | ForEach-Object {
    $library = Join-Path $ArtifactsDirectory "$_.lib"
    if (!(Test-Path $library)) { throw "Missing static library: $library" }
    $library
})
$systemLibraries = @('mfuuid.lib', 'ole32.lib', 'strmiids.lib', 'user32.lib', 'bcrypt.lib')
$pgsExecutable = Join-Path $testRoot 'pgs-support.exe'
Invoke-Native 'cl.exe' (@(
    '/nologo', '/O2', '/MT', '/EHsc', "/I$(Join-Path $ArtifactsDirectory 'include')",
    (Join-Path $repoRoot 'tests/ffmpeg/pgs-support.cc'),
    "/Fo$(Join-Path $testRoot 'pgs-support.obj')", "/Fe$pgsExecutable", '/link'
) + $libraries + $systemLibraries)

$publishArguments = @(
    'publish', (Join-Path $repoRoot 'tests/ffmpeg/consumer/FfmpegConsumer.csproj'),
    '-c', 'Release', '-r', $Target
)
if ($PackageSource) {
    $publishArguments += @(
        "-p:FfmpegPackageVersion=$PackageVersion",
        "-p:RestoreAdditionalProjectSources=$PackageSource",
        "-p:RestorePackagesPath=$(Join-Path $PackageSource "restore-$Target")"
    )
} else {
    $publishArguments += @('-p:UseLocalFfmpegArtifacts=true', "-p:LightStudioFfmpegStaticLibraryDir=$ArtifactsDirectory")
}
Invoke-Native 'dotnet' ($publishArguments + @('-o', $testRoot))

$consumer = Join-Path $testRoot 'FfmpegConsumer.exe'
foreach ($executable in @($pgsExecutable, $consumer)) {
    $headers = (& dumpbin.exe /headers $executable) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $headers -notmatch "machine \($architecture\)") {
        throw "Wrong PE architecture for $executable"
    }
    $imports = (& dumpbin.exe /dependents $executable) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect $executable" }
    if ($imports -match '(?im)^\s*(?:lib)?(?:avcodec|avdevice|avfilter|avformat|avutil|swresample|swscale|dav1d|jxl|xml2|zlib)[^\s]*\.dll\s*$' -or
        $imports -match '(?i)msys-2\.0|libgcc|libstdc\+\+|libwinpthread|vcruntime|msvcp') {
        throw "Unexpected native runtime dependency in $executable`n$imports"
    }
}
if (Get-ChildItem $testRoot -Filter '*.dll' | Where-Object Name -Match '^(lib)?(avcodec|avdevice|avfilter|avformat|avutil|swresample|swscale)') {
    throw 'Static publish contains FFmpeg DLLs'
}

Invoke-Native 'dotnet' ($publishArguments + @('-p:EnableStaticFfmpeg=false', '-o', $sharedRoot))
$sharedConsumer = Join-Path $sharedRoot 'FfmpegConsumer.exe'
$sharedLibraries = @()
foreach ($library in $libraryNames[0..6]) {
    $dlls = @(Get-ChildItem $sharedRoot -Filter "$library-*.dll")
    if ($dlls.Count -ne 1) { throw "Expected one $library DLL in the shared publish" }
    $source = Get-FileHash (Join-Path $ArtifactsDirectory $dlls[0].Name)
    if ((Get-FileHash $dlls[0].FullName).Hash -ne $source.Hash) {
        throw "Wrong $Target DLL deployed: $($dlls[0].Name)"
    }
    $sharedLibraries += $dlls[0].FullName
}
foreach ($binary in @($sharedConsumer) + $sharedLibraries) {
    $headers = (& dumpbin.exe /headers $binary) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $headers -notmatch "machine \($architecture\)") {
        throw "Wrong PE architecture for $binary"
    }
    $imports = (& dumpbin.exe /dependents $binary) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect $binary" }
    if ($imports -match '(?im)^\s*(?:lib)?(?:dav1d|jxl|hwy|brotli|xml2|zlib)[^\s]*\.dll\s*$' -or
        $imports -match '(?i)msys-2\.0|libgcc|libstdc\+\+|libwinpthread|vcruntime|msvcp') {
        throw "Unexpected external runtime dependency in $binary`n$imports"
    }
}

$hostArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
if ($architecture -eq $hostArchitecture) {
    Invoke-Native $pgsExecutable @()
    $consumerArguments = @()
    if ($Hardware) { $consumerArguments += '--hardware' }
    Invoke-Native $consumer $consumerArguments
    Invoke-Native $sharedConsumer $consumerArguments
    Write-Host "$Target shared/static NativeAOT decoding, MSVC linking, and PE dependency checks passed."
} else {
    if ($Hardware) { throw 'The hardware test must run on the target architecture.' }
    Write-Host "$Target shared/static NativeAOT and MSVC cross-link checks passed; execution requires a $architecture Windows host."
}
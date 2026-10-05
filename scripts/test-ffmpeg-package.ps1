param([switch]$SkipNative)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $repoRoot 'artifacts/build/ffmpeg-package-tests'
$artifactRoot = Join-Path $testRoot 'artifacts'
$packageRoot = Join-Path $testRoot 'packages'
$project = Join-Path $repoRoot 'package/LightStudio.Ffmpeg.csproj'
$libraryNames = @(
    'avcodec', 'avdevice', 'avfilter', 'avformat', 'avutil', 'swresample', 'swscale',
    'dav1d', 'jxl', 'jxl_cms', 'jxl_threads', 'hwy', 'brotlicommon', 'brotlidec',
    'brotlienc', 'xml2', 'zlib'
)
$dllNames = @('avcodec-63.dll', 'avdevice-63.dll', 'avfilter-12.dll', 'avformat-63.dll', 'avutil-61.dll', 'swresample-7.dll', 'swscale-10.dll')

foreach ($rid in @('win-x64', 'win-arm64')) {
    foreach ($library in $libraryNames) {
        $source = Join-Path $repoRoot "artifacts/ffmpeg-$rid/$library.lib"
        if (!(Test-Path $source)) { throw "Build both Windows variants first. Missing $source" }
    }
    foreach ($dll in $dllNames) {
        $source = Join-Path $repoRoot "artifacts/ffmpeg-$rid/$dll"
        if (!(Test-Path $source)) { throw "Build both Windows variants first. Missing $source" }
    }
}
if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
foreach ($rid in @('win-x64', 'win-arm64')) {
    $destination = Join-Path $artifactRoot "ffmpeg-$rid"
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($library in $libraryNames) {
        Copy-Item (Join-Path $repoRoot "artifacts/ffmpeg-$rid/$library.lib") $destination
    }
    foreach ($dll in $dllNames) {
        Copy-Item (Join-Path $repoRoot "artifacts/ffmpeg-$rid/$dll") $destination
    }
}

$fixtures = @{
    'ffmpeg-android/android-arm64' = @('libavcodec.so')
    'ffmpeg-android/android-x64' = @('libavcodec.so')
    'ffmpeg-osx-arm64' = @('libavcodec.dylib', 'libdav1d.a', 'libjxl.a', 'libxml2.a')
    'ffmpeg-browser-wasm-em3' = @('libdav1d.a', 'libxml2.a', 'libz.a')
    'ffmpeg-MT-browser-wasm-em3' = @('libdav1d.a', 'libxml2.a', 'libz.a', 'libjxl.a')
    'ffmpeg-browser-wasm-em6' = @('libdav1d.a', 'libxml2.a', 'libz.a')
    'ffmpeg-MT-browser-wasm-em6' = @('libdav1d.a', 'libxml2.a', 'libz.a', 'libjxl.a')
}
foreach ($relative in $fixtures.Keys) {
    $directory = Join-Path $artifactRoot $relative
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    foreach ($file in $fixtures[$relative]) {
        [System.IO.File]::Create((Join-Path $directory $file)).Dispose()
    }
}

& dotnet pack $project -c Release -o $packageRoot '-p:PackageVersion=0.0.0-windows-test' "-p:FFmpegArtifactsPath=$artifactRoot"
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg test package creation failed' }
$package = Join-Path $packageRoot 'LightStudio.Ffmpeg.0.0.0-windows-test.nupkg'
$extracted = Join-Path $testRoot 'extracted'
[System.IO.Compression.ZipFile]::ExtractToDirectory($package, $extracted)
foreach ($rid in @('win-x64', 'win-arm64')) {
    $archives = @(Get-ChildItem (Join-Path $extracted "static/$rid") -Filter '*.lib')
    if ($archives.Count -ne $libraryNames.Count) { throw "Incorrect static layout for $rid" }
    foreach ($library in $libraryNames) {
        $source = Get-FileHash (Join-Path $artifactRoot "ffmpeg-$rid/$library.lib")
        $packed = Get-FileHash (Join-Path $extracted "static/$rid/$library.lib")
        if ($source.Hash -ne $packed.Hash) { throw "Package changed $rid/$library.lib" }
    }
    $dlls = @(Get-ChildItem (Join-Path $extracted "runtimes/$rid/native") -Filter '*.dll')
    if ($dlls.Count -ne $dllNames.Count) { throw "Incorrect runtime layout for $rid" }
    foreach ($dll in $dllNames) {
        $source = Get-FileHash (Join-Path $artifactRoot "ffmpeg-$rid/$dll")
        $packed = Get-FileHash (Join-Path $extracted "runtimes/$rid/native/$dll")
        if ($source.Hash -ne $packed.Hash) { throw "Package changed $rid/$dll" }
    }
    if (Get-ChildItem (Join-Path $extracted "static/$rid") -Filter '*.dll') {
        throw 'DLLs must not be static assets'
    }
}
foreach ($directory in @('build', 'buildTransitive')) {
    foreach ($extension in @('props', 'targets')) {
        if (!(Test-Path (Join-Path $extracted "$directory/LightStudio.Ffmpeg.$extension"))) {
            throw "Missing $directory MSBuild $extension"
        }
    }
}
if (!(Test-Path (Join-Path $extracted 'licenses/zlib/LICENSE'))) { throw 'Missing zlib license' }
if (Get-ChildItem (Join-Path $extracted 'runtimes') -Recurse -Include '*.lib', '*.a') {
    throw 'Static archives must not be runtime assets'
}

$targets = Join-Path $extracted 'build/LightStudio.Ffmpeg.targets'
foreach ($aot in @('true', 'false')) {
    foreach ($enabled in @('true', 'false')) {
        foreach ($rid in @('win-x64', 'win-arm64')) {
            $selection = & dotnet msbuild $targets -nologo "-p:RuntimeIdentifier=$rid" "-p:PublishAot=$aot" "-p:EnableStaticFfmpeg=$enabled" "-p:LightStudioFfmpegPackageRoot=$extracted/" -getItem:NativeLibrary
            if ($LASTEXITCODE -ne 0) { throw 'MSBuild target evaluation failed' }
            $expected = 0
            if ($aot -eq 'true' -and $enabled -eq 'true') { $expected = 22 }
            $items = ($selection | ConvertFrom-Json).Items.NativeLibrary
            if (@($items).Count -ne $expected) { throw "Invalid selection: $rid PublishAot=$aot EnableStaticFfmpeg=$enabled" }
        }
    }
}
foreach ($framework in @('v10.0', 'v11.0')) {
    foreach ($threads in @('true', 'false')) {
        $selection = & dotnet msbuild $targets -nologo '-p:RuntimeIdentifier=browser-wasm' "-p:TargetFrameworkVersion=$framework" "-p:WasmEnableThreads=$threads" "-p:LightStudioFfmpegPackageRoot=$extracted/" -getItem:NativeFileReference
        if ($LASTEXITCODE -ne 0) { throw 'Wasm target evaluation failed' }
        $flavor = 'wasm'
        if ($threads -eq 'true') { $flavor += '-mt' }
        $flavor += $(if ($framework -eq 'v11.0') { '-em6' } else { '-em3' })
        $items = @(($selection | ConvertFrom-Json).Items.NativeFileReference)
        if ($items.Count -lt 3 -or @($items | Where-Object { $_.Identity.Replace('\', '/') -notmatch "/static/$flavor/" }).Count -ne 0) {
            throw "Incorrect wasm selection for $framework, threads=$threads"
        }
    }
}

foreach ($rid in @('win-x64', 'win-arm64')) {
    foreach ($file in @($libraryNames | ForEach-Object { "$_.lib" }) + $dllNames) {
        $archive = Join-Path $artifactRoot "ffmpeg-$rid/$file"
        Move-Item $archive "$archive.missing"
        try {
            $diagnostics = & dotnet msbuild $project -nologo -v:quiet -t:ValidateFFmpegArtifacts "-p:FFmpegArtifactsPath=$artifactRoot" 2>&1
            if ($LASTEXITCODE -eq 0 -or ($diagnostics -join "`n") -notmatch 'Missing Windows (static archive|shared library)') {
                throw "Missing archive was not rejected: $archive"
            }
        }
        finally {
            Move-Item "$archive.missing" $archive
        }
    }
}

if (!$SkipNative) {
    & (Join-Path $PSScriptRoot 'test-ffmpeg-windows.ps1') -Target win-x64 -PackageSource $packageRoot
}
Write-Host 'Windows NuGet runtime/static layout, target selection, and missing-library guards passed.'
Write-Host 'Non-Windows binaries in this test package are empty fixtures. Do not publish it.'
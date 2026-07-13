# LightPlayer Packages

This repository builds and publishes two NuGet packages containing FFmpeg 8.1.2 static libraries for the .NET `browser-wasm` runtime:

| Package | Threading model |
| --- | --- |
| `LightStudio.Ffmpeg.browser-wasm` | Single-threaded; pthread, Win32 thread, and OS/2 thread support are disabled. |
| `LightStudio.Ffmpeg.MT.browser-wasm` | Emscripten pthread support is enabled through FFmpeg's automatic detection. |

The MT package requires the consuming WebAssembly application to enable shared memory and serve the cross-origin isolation headers required by browser pthreads.

## Publish

Push a tag named `ffmpeg-v<package-version>` to build both FFmpeg variants with Emscripten and publish both packages to this repository's GitHub Packages feed. For version 8.1.2:

```bash
git tag ffmpeg-v8.1.2
git push origin ffmpeg-v8.1.2
```

The workflow can also be run manually with a NuGet package version from the Actions tab.

## Consume

Add the repository owner's GitHub Packages feed to the consuming project's NuGet configuration:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="github-lightstudio" value="https://nuget.pkg.github.com/hjc4869/index.json" />
  </packageSources>
</configuration>
```

Authenticate to the feed with a GitHub token that has `read:packages`, then add one of the packages:

```bash
dotnet add package LightStudio.Ffmpeg.browser-wasm --version 8.1.2
dotnet add package LightStudio.Ffmpeg.MT.browser-wasm --version 8.1.2
```

The archives are packaged under `runtimes/browser-wasm/native`, which is NuGet's native asset convention for the `browser-wasm` runtime identifier.

## Local builds

Build and pack each variant independently:

```bash
./scripts/build-ffmpeg-browser-wasm.sh single-threaded
dotnet pack package/LightStudio.Ffmpeg.browser-wasm.csproj --output artifacts/packages

./scripts/build-ffmpeg-browser-wasm.sh multi-threaded
dotnet pack package/LightStudio.Ffmpeg.MT.browser-wasm.csproj --output artifacts/packages
```
# LightPlayer Packages

This repository builds and publishes four NuGet packages containing FFmpeg 8.1.2 libraries for .NET:

| Package | Runtime | Threading model |
| --- | --- | --- |
| `LightStudio.Ffmpeg.browser-wasm` | `browser-wasm` | Single-threaded; pthread, Win32 thread, and OS/2 thread support are disabled. |
| `LightStudio.Ffmpeg.MT.browser-wasm` | `browser-wasm` | Emscripten pthread support is enabled through FFmpeg's automatic detection. |
| `LightStudio.Ffmpeg.osx-arm64` | `osx-arm64` | Native pthread support is enabled. |
| `LightStudio.Ffmpeg.Android` | `android-arm64`, `android-x64` | Native pthread support is enabled. |

The MT package requires the consuming WebAssembly application to enable shared memory and serve the cross-origin isolation headers required by browser pthreads.

The osx-arm64 package contains both static archives and dynamic libraries. The Android package contains shared libraries only for both the `android-arm64` and `android-x64` runtimes. The browser-wasm packages contain static archives only.

## Publish

Push a tag named `ffmpeg-v<package-version>` to build both browser-wasm variants, the osx-arm64 variant, and the Android variant, then publish all four packages to this repository's GitHub Packages feed. For version 8.1.2:

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

Authenticate to the feed with a GitHub token that has `read:packages`, then add the package for the target runtime:

```bash
dotnet add package LightStudio.Ffmpeg.browser-wasm --version 8.1.2
dotnet add package LightStudio.Ffmpeg.MT.browser-wasm --version 8.1.2
dotnet add package LightStudio.Ffmpeg.osx-arm64 --version 8.1.2
dotnet add package LightStudio.Ffmpeg.Android --version 8.1.2
```

The browser archives are packaged under `runtimes/browser-wasm/native`. The Apple silicon static and dynamic libraries are packaged under `runtimes/osx-arm64/native` and target macOS 11.0 or later. The Android shared libraries are packaged under `runtimes/android-arm64/native` and `runtimes/android-x64/native` and target Android API level 21 or later.

## Local builds

Build and pack each variant independently:

```bash
./scripts/build-ffmpeg-browser-wasm.sh single-threaded
dotnet pack package/LightStudio.Ffmpeg.browser-wasm.csproj --output artifacts/packages

./scripts/build-ffmpeg-browser-wasm.sh multi-threaded
dotnet pack package/LightStudio.Ffmpeg.MT.browser-wasm.csproj --output artifacts/packages

# Run on macOS with Xcode command-line tools installed.
./scripts/build-ffmpeg-osx-arm64.sh
dotnet pack package/LightStudio.Ffmpeg.osx-arm64.csproj --output artifacts/packages

# Requires the Android NDK. Set ANDROID_NDK_HOME if it is not already exported.
./scripts/build-ffmpeg-android.sh
dotnet pack package/LightStudio.Ffmpeg.Android.csproj --output artifacts/packages
```

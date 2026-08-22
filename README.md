# LightPlayer Packages

This repository builds and publishes a single NuGet package, `LightStudio.Ffmpeg`, containing FFmpeg 8.1.2 native libraries for .NET.

| Runtime | Linking | Location in the package |
| --- | --- | --- |
| `android-arm64`, `android-x64` | Shared (`.so`) | `runtimes/android-<arch>/native` |
| `osx-arm64` | Shared (`.dylib`) | `runtimes/osx-arm64/native` |
| `osx-arm64` | Static (`.a`, native AOT only) | `static/osx-arm64` |
| `browser-wasm`, single-threaded | Static (`.a`) | `static/wasm` |
| `browser-wasm`, multi-threaded | Static (`.a`) | `static/wasm-mt` |

Static archives are deliberately kept outside `runtimes/` so NuGet never treats them as deployable runtime assets. The package's `build/LightStudio.Ffmpeg.targets` wires them up instead.

Every runtime bundles dav1d 1.5.4 as the AV1 decoder. The browser-wasm and osx-arm64 static sets ship `libdav1d.a` next to the FFmpeg archives; the Android and macOS shared libraries link dav1d statically into `libavcodec`.

## Publish

Push a tag named `ffmpeg-v<package-version>`. The workflow builds each platform in its own job, then a final job merges the artifacts, packs `LightStudio.Ffmpeg`, and publishes it to this repository's GitHub Packages feed. For version 8.1.2:

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

Authenticate to the feed with a GitHub token that has `read:packages`, then add the package:

```bash
dotnet add package LightStudio.Ffmpeg --version 8.1.2
```

### Android and macOS

Nothing else is required. The shared libraries are deployed by the .NET SDK from `runtimes/<rid>/native`. The macOS binaries target macOS 11.0 or later; the Android binaries target API level 21 or later.

### WebAssembly

The package adds the correct archives as `NativeFileReference` items automatically. `WasmEnableThreads` selects the variant: `true` links the pthread-enabled archives from `static/wasm-mt`, otherwise the single-threaded archives from `static/wasm` are used. No manual `NativeFileReference` in the consuming project is needed.

### Static linking with native AOT

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <EnableStaticFfmpeg>true</EnableStaticFfmpeg>
</PropertyGroup>
```

`EnableStaticFfmpeg` adds the `NativeLibrary` items and the `CoreMedia`, `CoreVideo`, and `VideoToolbox` linker arguments, and drops the package's shared libraries from the publish output. It is ignored when `PublishAot` is not enabled and on runtimes that ship shared libraries only, such as Android and browser-wasm.

## Local builds

All variants build dav1d from the `dav1d` submodule first, so meson and ninja are required. Each script stages its output under `artifacts/<artifact-name>`; packing requires all of them, which normally means collecting the artifacts from CI.

```bash
./scripts/build-ffmpeg-browser-wasm.sh single-threaded   # artifacts/ffmpeg-browser-wasm
./scripts/build-ffmpeg-browser-wasm.sh multi-threaded    # artifacts/ffmpeg-MT-browser-wasm

# Run on macOS with Xcode command-line tools installed.
./scripts/build-ffmpeg-osx-arm64.sh                      # artifacts/ffmpeg-osx-arm64

# Requires the Android NDK and nasm (nasm assembles the android-x64 target).
# Set ANDROID_NDK_HOME if it is not already exported.
./scripts/build-ffmpeg-android.sh                        # artifacts/ffmpeg-android

dotnet pack package/LightStudio.Ffmpeg.csproj --output artifacts/packages
```

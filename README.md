# LightPlayer Packages

This repository builds and publishes a single NuGet package, [`LightStudio.Ffmpeg`](https://www.nuget.org/packages/LightStudio.Ffmpeg/), containing FFmpeg 9.0.1 native libraries for .NET.

| Runtime | Linking | Location in the package |
| --- | --- | --- |
| `android-arm64`, `android-x64` | Shared (`.so`) | `runtimes/android-<arch>/native` |
| `osx-arm64` | Shared (`.dylib`) | `runtimes/osx-arm64/native` |
| `osx-arm64` | Static (`.a`, native AOT only) | `static/osx-arm64` |
| `browser-wasm`, single-threaded | Static (`.a`) | `static/wasm` |
| `browser-wasm`, multi-threaded | Static (`.a`) | `static/wasm-mt` |

Static archives are deliberately kept outside `runtimes/` so NuGet never treats them as deployable runtime assets. The package's `build/LightStudio.Ffmpeg.targets` wires them up instead.

Every runtime bundles dav1d 1.5.4 as the AV1 decoder. The browser-wasm and osx-arm64 static sets ship `libdav1d.a` next to the FFmpeg archives; the Android and macOS shared libraries link dav1d statically into `libavcodec`.

The HLS and DASH demuxers and file protocol are enabled on every runtime for applications that provide manifests, playlists, and segment resources through `AVFormatContext.io_open`. FFmpeg networking remains disabled; HTTP transport belongs to the consuming application. DASH manifest parsing is provided by libxml2 2.15.3, which is linked statically into shared builds and shipped as `libxml2.a` with static builds.

## Photo formats

The common still-image formats are enabled on every runtime:

| Format | Demuxer | Decoder |
| --- | --- | --- |
| JPEG | `image2`, `jpeg_pipe` | `mjpeg` |
| PNG / APNG | `image2`, `png_pipe`, `apng` | `png`, `apng` |
| WebP (still and animated) | `image2`, `webp_pipe`, `webp_anim` | `webp` |
| TIFF | `image2`, `tiff_pipe` | `tiff` |
| AVIF | `mov` (HEIF item support) | `libdav1d` |
| HEIC | `mov` (HEIF item support) | `hevc` |
| JPEG XL (still and animated) | `jpegxl_pipe`, `jpegxl_anim` | `libjxl`, `libjxl_anim` |

JPEG XL comes from libjxl 0.11.2, which is built from the `libjxl` submodule the
same way dav1d is. It is enabled on `android-arm64`, `android-x64`, `osx-arm64`
and the multi-threaded browser-wasm variant. It is **not** available in the
single-threaded browser-wasm variant: libjxl's parallel runner is `std::thread`
based and FFmpeg always creates it with `av_cpu_count()` workers, which aborts in
an Emscripten module built without pthreads.

zlib is required by the PNG decoder. Android and macOS use the platform copy;
browser-wasm uses the Emscripten `zlib` port and ships the resulting `libz.a`
next to the FFmpeg archives, so consuming projects do not have to enable the
port themselves.

## Publish

Push a tag named `ffmpeg-v<package-version>`. The workflow builds each platform in its own job, then a final job merges the artifacts, packs `LightStudio.Ffmpeg`, and publishes it to [nuget.org](https://www.nuget.org/packages/LightStudio.Ffmpeg/). For version 9.0.1:

```bash
git tag ffmpeg-v9.0.1
git push origin ffmpeg-v9.0.1
```

The workflow can also be run manually with a NuGet package version from the Actions tab.

## Consume

The package is published to nuget.org, so no extra feed configuration is required:

```bash
dotnet add package LightStudio.Ffmpeg --version 9.0.1
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

`EnableStaticFfmpeg` adds the `NativeLibrary` items and the `c++`, `z`, `CoreMedia`, `CoreVideo`, and `VideoToolbox` linker arguments, and drops the package's shared libraries from the publish output. It is ignored when `PublishAot` is not enabled and on runtimes that ship shared libraries only, such as Android and browser-wasm.

## Local builds

All variants build dav1d, libjxl, and libxml2 from their submodules first, so cmake, meson and ninja are required. libjxl has ten nested submodules, including a multi-gigabyte test corpus, so `--recursive` is deliberately avoided; `scripts/fetch-libjxl-dependencies.sh` initializes only brotli, highway and skcms.

Each script stages its output under `artifacts/<artifact-name>`; packing requires all of them, which normally means collecting the artifacts from CI.

```bash
git submodule update --init
./scripts/fetch-libjxl-dependencies.sh

./scripts/build-ffmpeg-browser-wasm.sh single-threaded   # artifacts/ffmpeg-browser-wasm
./scripts/build-ffmpeg-browser-wasm.sh multi-threaded    # artifacts/ffmpeg-MT-browser-wasm

# Run on macOS with Xcode command-line tools installed.
./scripts/build-ffmpeg-osx-arm64.sh                      # artifacts/ffmpeg-osx-arm64

# Requires the Android NDK and nasm (nasm assembles the android-x64 target).
# Set ANDROID_NDK_HOME if it is not already exported.
./scripts/build-ffmpeg-android.sh                        # artifacts/ffmpeg-android

dotnet pack package/LightStudio.Ffmpeg.csproj --output artifacts/packages
```

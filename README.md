# LightPlayer Packages

This repository builds native NuGet packages for .NET:

- [`LightStudio.Ffmpeg`](https://www.nuget.org/packages/LightStudio.Ffmpeg/): FFmpeg 9.0.1 and its decoding dependencies.
- [LightStudio.Photos](package/photos/README.md): LibRaw 0.22.2 and Little CMS 2.19.1 for RAW photos and ICC color management. See [Photos builds](#photos-builds) for its platform matrix and workflow.

## FFmpeg Runtimes

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

## Photos Builds

`LightStudio.Photos` is independent of FFmpeg. It includes shared libraries for `android-arm64`, `android-x64`, `linux-x64`, `linux-arm64`, `win-x64`, `osx-arm64` and `osx-x64`; static archives for both macOS architectures; and separate single/multi-threaded wasm32 archives. libjpeg-turbo 3.1.3 and zlib 1.3.2 enable lossy JPEG and floating-point deflate DNG decoding. They are embedded into LibRaw's shared libraries and shipped as `libjpeg.a`/`libz.a` beside `libraw.a`/`liblcms2.a` for static consumers. The [package README](package/photos/README.md) documents P/Invoke names, `WasmEnableThreads`, `EnableStaticPhotos`, supported formats and licenses.

The [Photos workflow](.github/workflows/photos.yml) uses `ubuntu-22.04`, the oldest supported hosted Ubuntu image, for Linux x64, Windows cross-builds, Android, wasm and packing. Linux arm64 builds natively on `ubuntu-22.04-arm`. Both Linux architectures compile and run smoke tests inside pinned architecture-specific manylinux2014 (CentOS 7, glibc 2.17) containers; the host runner does not set the binary's glibc baseline. CI rejects newer glibc/C++ ABI requirements. The baseline containers are build environments, not a recommendation to deploy an end-of-life OS.

macOS uses `macos-14`, as the existing FFmpeg macOS job does, and explicitly targets macOS 11.0. That runner is deprecated upstream and will need replacement when retired; the deployment target can remain 11.0. Intel binaries are cross-built on Apple silicon and both shared/static smoke tests run through Rosetta. Windows x64 uses the MinGW Win32-thread toolchain on Linux and a Wine smoke test, with no Windows build runner required.

Android follows FFmpeg's SDK setup and combined artifact pattern, using NDK r28c (`28.2.13676358`), API 21, and both 64-bit ABIs. Local tests use `/usr/lib/android-ndk` by default. Artifacts have 16 KB page alignment and do not require `libc++_shared.so`.

Initialize only the required sources, then run the targets available on your host:

```bash
git submodule update --init libraw lcms2 libjpeg-turbo zlib

# Requires Autotools, CMake, make, pkg-config, GCC/G++, and patchelf.
./scripts/build-photos.sh linux-x64

# Cross-build on x64 with crossbuild-essential-arm64, qemu-user, and patchelf.
# Also works natively on arm64; cross-build smoke tests execute through QEMU.
./scripts/build-photos.sh linux-arm64

# Reproduce the CI glibc compatibility build; Docker image contains the tools.
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/work" -w /work \
  quay.io/pypa/manylinux2014_x86_64@sha256:493d2032114d757aaa761a9385ad8497f391503bf71acef9abeeb66682ca5d90 \
  ./scripts/build-photos.sh linux-x64
./scripts/check-photos-linux-abi.sh

# Debian/Ubuntu MinGW packages: gcc/g++-mingw-w64-x86-64-win32.
./scripts/build-photos.sh win-x64

ANDROID_NDK_HOME=/usr/lib/android-ndk ./scripts/build-photos-android.sh

# Requires Emscripten; CI uses 3.1.69, matching FFmpeg.
./scripts/build-photos.sh browser-wasm
./scripts/build-photos.sh browser-wasm-mt

# On macOS with Xcode and Homebrew autoconf, automake, libtool, pkg-config, cmake.
./scripts/build-photos.sh osx-arm64
./scripts/build-photos.sh osx-x64

./scripts/test-photos-targets.sh

# Requires Linux, Android and Windows outputs (including runtime notices).
# Uses isolated placeholder files for unavailable platforms, never for release.
./scripts/test-photos-package.sh

# Requires every real platform artifact, normally downloaded from CI.
dotnet pack package/photos/LightStudio.Photos.csproj --output artifacts/packages
```

`PHOTOS_BUILD_JOBS` controls parallelism. Each target rebuilds its own directory under `artifacts/build/photos-*` without modifying the pinned submodule sources. Shared C API smoke tests run for Linux/macOS; wasm tests execute in Node; Android smoke executables are cross-linked but require a device/emulator to execute. Tests check LibRaw capabilities and decode synthetic 32x32 JPEG/float-deflate DNGs, including on a wasm pthread. The workflow also checks JPEG/zlib capabilities from a .NET P/Invoke consumer loading the final NuGet's Linux assets.

The installed `crossbuild-essential-arm64` toolchain was verified locally by compiling all four libraries and running the resulting arm64 smoke executable with `qemu-aarch64 -L /usr/aarch64-linux-gnu`. Local cross-builds inherit that toolchain's glibc/C++ sysroot baseline; use CI's native manylinux build for release compatibility. JPEG/zlib are built from the pinned sources rather than taken from the host or NDK.

The committed DNG fixture header is generated by [generate-dng-fixtures.c](tests/photos/generate-dng-fixtures.c), which links against the built JPEG and zlib archives. To regenerate after a Linux x64 build:

```bash
gcc tests/photos/generate-dng-fixtures.c \
  -Iartifacts/build/photos-linux-x64/install/include \
  artifacts/build/photos-linux-x64/install/lib/libjpeg.a \
  artifacts/build/photos-linux-x64/install/lib/libz.a \
  -o artifacts/build/photos-dng-fixtures-generator
artifacts/build/photos-dng-fixtures-generator > tests/photos/dng-fixtures.h
```

Push a `photos-v<package-version>` tag (initial version `photos-v0.22.2`) or dispatch the workflow manually to build a complete `.nupkg`. Like the current FFmpeg workflow, tag builds produce an artifact without automatically publishing. To publish Photos, use workflow dispatch with `publish=true` and configure the repository's `NUGET_API_KEY` secret. No package is published by local tests.

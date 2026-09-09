# LightStudio.Photos

Native **LibRaw 0.22.2** and **Little CMS 2.19.1** libraries for .NET. LibRaw includes Little CMS color management, **libjpeg-turbo 3.1.3** for lossy JPEG-compressed DNGs, and **zlib 1.3.2** for deflate-compressed floating-point DNGs. This package contains native libraries, not managed bindings.

| Runtime | Libraries | Package location |
| --- | --- | --- |
| `android-arm64`, `android-x64` | Shared `.so` | `runtimes/<rid>/native` |
| `linux-x64`, `linux-arm64` | Shared `.so` | `runtimes/<rid>/native` |
| `win-x64` (MinGW) | Shared `.dll` | `runtimes/win-x64/native` |
| `osx-arm64`, `osx-x64` | Shared `.dylib` | `runtimes/<rid>/native` |
| `osx-arm64`, `osx-x64` | Static `.a`, native AOT opt-in | `static/<rid>` |
| `browser-wasm`, single-threaded | Static `.a` | `static/wasm` |
| `browser-wasm`, multi-threaded | Static `.a` | `static/wasm-mt` |

## Consume

```bash
dotnet add package LightStudio.Photos --version 0.22.2
```

Use native library names `libraw` and `liblcms2` in P/Invoke declarations. The .NET SDK deploys shared libraries automatically. For statically linked platforms, use the native entry-point conventions required by your .NET toolchain/binding generator.

For WebAssembly, `WasmEnableThreads=true` selects the pthread-enabled archives; otherwise the single-threaded archives are selected. `NativeFileReference` items are added automatically, including through transitive references. Wasm exception handling must remain enabled (`WasmEnableExceptionHandling=true`, the SDK default). Use independent LibRaw handles for concurrent work; the multi-threaded build is pthread-compatible, not an OpenMP worker pool.

For macOS native AOT static linking:

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <EnableStaticPhotos>true</EnableStaticPhotos>
</PropertyGroup>
```

This adds `libraw.a`, `liblcms2.a`, `libjpeg.a` and `libz.a` as `NativeLibrary` items, links `c++`, and removes this package's shared libraries from the publish output, following `LightStudio.Ffmpeg`'s `EnableStaticFfmpeg` convention. The same four archives are provided for each wasm variant. `EnableStaticPhotos` has no effect without native AOT or on other RIDs. Static archives are outside `runtimes/` so they are not copied as deployable native assets.

Shared builds embed JPEG and zlib into LibRaw, so applications deploy only `libraw` and `liblcms2`, with no additional JPEG/zlib shared libraries to install. LibRaw links the separately exposed LCMS library from this package.

## Compatibility

- Linux: release builds use the CentOS 7-based manylinux2014 environment for glibc 2.17 or newer, using baseline x86-64 or ARMv8-A instructions. Requires system `libstdc++`, `libgcc_s` and glibc; not an Alpine/musl build. Your .NET runtime may require a newer OS. Local arm64 cross-builds use the installed toolchain's sysroot and may require newer glibc than CI releases.
- Android: API 21 or newer, NDK r28c, 16 KB page-compatible libraries. The C++ runtime is linked statically.
- macOS: deployment target 11.0, both Apple silicon and Intel. Shared libraries resolve the bundled LCMS library relative to themselves.
- Windows: x64, cross-built on Linux with the MinGW Win32-thread toolchain. No separately installed MinGW runtime DLLs are required.
- WebAssembly: wasm32 static archives, with separate single-threaded and pthread-enabled builds using native wasm exceptions. Applications must use a compatible Emscripten/.NET wasm toolchain and configure cross-origin isolation for browser threads.

OpenMP, RawSpeed, the Adobe DNG SDK and the LCMS GPL plugins are not included. JPEG and zlib support are required at build time and validated by decoding synthetic compressed DNGs. libjpeg-turbo uses the JPEG v8 API, without its TurboJPEG API/tools or SIMD assembly. The upstream `lcms2.19.1` tag reports API version `2190` / Autotools version `2.19`; the source is pinned to the actual 2.19.1 release commit.

## Licenses

LibRaw is available under LGPL-2.1-or-later or CDDL-1.0; Little CMS uses MIT; the libjpeg API uses the IJG license; zlib uses the zlib license. Their license and copyright files are included under `licenses/`. Static linking does not remove the applicable redistribution/relinking obligations. Windows and Android builds also contain their toolchains' standard C++ runtimes under their respective runtime licenses and exceptions.

This software is based in part on the work of the Independent JPEG Group.

Build scripts, exact source pins, and release instructions are in the [source repository](https://github.com/hjc4869/LightPlayer-Packages).
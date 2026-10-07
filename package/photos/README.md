# LightStudio.Photos

Native **LibRaw 0.22.2** and **Little CMS 2.19.1** libraries for .NET. LibRaw includes Little CMS color management, **libjpeg-turbo 3.1.3** for lossy JPEG-compressed DNGs, and **zlib 1.3.2** for deflate-compressed floating-point DNGs. This package contains native libraries, not managed bindings.

| Runtime | Libraries | Package location |
| --- | --- | --- |
| `android-arm64`, `android-x64` | Shared `.so` | `runtimes/<rid>/native` |
| `android-arm64`, `android-x64` | Static `.a`, native AOT opt-in | `static/<rid>` |
| `linux-x64`, `linux-arm64` | Shared `.so` | `runtimes/<rid>/native` |
| `linux-x64`, `linux-arm64` | Static `.a`, native AOT opt-in | `static/<rid>` |
| `win-x64` (MinGW) | Shared `.dll` | `runtimes/win-x64/native` |
| `win-arm64` (LLVM-MinGW) | Shared `.dll` | `runtimes/win-arm64/native` |
| `win-x64`, `win-arm64` (MSVC ABI) | Static `.lib`, native AOT opt-in | `static/<rid>` |
| `osx-arm64`, `osx-x64` | Shared `.dylib` | `runtimes/<rid>/native` |
| `osx-arm64`, `osx-x64` | Static `.a`, native AOT opt-in | `static/<rid>` |
| `ios-arm64` | Static `.a`, device only | `runtimes/ios-arm64/native` |
| `iossimulator-arm64` | Static `.a`, ARM64 simulator | `runtimes/iossimulator-arm64/native` |
| `browser-wasm`, single-threaded | Static `.a` | `static/wasm-em3`, `static/wasm-em6` |
| `browser-wasm`, multi-threaded | Static `.a` | `static/wasm-mt-em3`, `static/wasm-mt-em6` |

## Consume

```bash
dotnet add package LightStudio.Photos --version 0.22.2
```

Use native library names `libraw` and `liblcms2` in P/Invoke declarations. The .NET SDK deploys shared libraries automatically. For statically linked platforms, use the native entry-point conventions required by your .NET toolchain/binding generator.

On every target, the bundled JPEG symbols, including internal helpers and data, use the `lightstudio_photos_` prefix, and LibRaw references those private names. This isolates its JPEG ABI 80 from other linked JPEG implementations. zlib and LCMS are not namespaced.

For WebAssembly, `WasmEnableThreads=true` selects the pthread-enabled archives; otherwise the single-threaded archives are selected. `NativeFileReference` items are added automatically, including through transitive references. Wasm exception handling must remain enabled (`WasmEnableExceptionHandling=true`, the SDK default). Use independent LibRaw handles for concurrent work; the multi-threaded build is pthread-compatible, not an OpenMP worker pool.

Target frameworks through .NET 10 select the `em3` archives built with Emscripten 3.1.69 and legacy wasm exceptions; .NET 11 and newer select `em6` built with 6.0.2 and standardized wasm exceptions (`-sWASM_LEGACY_EXCEPTIONS=0`). Compilation and linking use the same exception mode. This is a best-effort compatibility rule, not a guarantee for every workload/toolchain version. Both SDK variants are supplied for each threading mode.

Each wasm variant supplies `libraw.a`, `liblcms2.a` and `libz.a`. The private JPEG implementation is embedded into `libraw.a`; there is no standalone wasm `libjpeg.a` to reference manually. zlib and LCMS remain separate.

For iOS ARM64 devices and simulators, the .NET for iOS SDK automatically links
`libraw.a`, `liblcms2.a`, `libjpeg.a`, and `libz.a` from `runtimes/<rid>/native/`,
using `ios-arm64` or `iossimulator-arm64` respectively. No manual archive
references, package-specific linking targets, or `EnableStaticPhotos` setting
are needed. Use `__Internal` P/Invokes and link the system `c++` library through
the app's iOS linker settings.

For Android, Linux, macOS, or Windows native AOT static linking:

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <EnableStaticPhotos>true</EnableStaticPhotos>
</PropertyGroup>
```

Publish for `android-arm64`, `android-x64`, `linux-arm64`, `linux-x64`, `osx-arm64`, `osx-x64`, `win-x64` or `win-arm64`. Android, Linux, and macOS add `libraw.a`, `liblcms2.a`, `libjpeg.a` and `libz.a` as `NativeLibrary` items. macOS links `c++`; Linux links `stdc++`, `m`, and `pthread`; Android links the consuming NDK's `c++_static` and `c++abi`, plus `dl` and `m`, and requests 16 KB pages. Windows adds MSVC-compatible `libraw.lib`, `liblcms2.lib`, `jpeg.lib` and `zlib.lib`, plus the Windows SDK's `ws2_32.lib`. Use direct P/Invokes for the LibRaw and LCMS entry points, as required by your static bindings; this option supplies linker inputs, not managed bindings.

Static publishes remove this package's shared libraries from the publish output, following `LightStudio.Ffmpeg`'s `EnableStaticFfmpeg` convention. `EnableStaticPhotos` has no effect without native AOT or on other RIDs. Android, desktop, and browser static archives are outside `runtimes/`; iOS uses the SDK's native static-asset support instead.

Android static consumption requires a NativeAOT host that honors `NativeLibrary`, `NativeSystemLibrary`, and `LinkerArg` with a compatible NDK. Standard .NET Android Mono AOT does not consume these archives automatically. The Linux and Android build jobs produce both shared libraries and static archives; the application chooses which to consume.

Shared builds embed JPEG and zlib into LibRaw, so applications deploy only `libraw` and `liblcms2`, with no additional JPEG/zlib shared libraries to install. LibRaw links the separately exposed LCMS library from this package.

## Compatibility

- Linux: release builds use the CentOS 7-based manylinux2014 environment for glibc 2.17 or newer, using baseline x86-64 or ARMv8-A instructions. Requires system `libstdc++`, `libgcc_s` and glibc; not an Alpine/musl build. Your .NET runtime may require a newer OS. Local arm64 cross-builds use the installed toolchain's sysroot and may require newer glibc than CI releases.
- Android: API 21 or newer, NDK r28c, 16 KB page-compatible libraries. The C++ runtime is linked statically.
- macOS: deployment target 11.0, both Apple silicon and Intel. Shared libraries resolve the bundled LCMS library relative to themselves.
- iOS: ARM64 devices and simulators, deployment target 15.0, static only; no Intel simulator archives. Build with full Xcode using `bash scripts/build-photos.sh ios-arm64` or `bash scripts/build-photos.sh iossimulator-arm64`. The matching iPhoneOS or iPhoneSimulator SDK is selected automatically. `IPHONEOS_DEPLOYMENT_TARGET` overrides the minimum for both. The macOS library feature configuration is preserved.
- Windows x64 shared: cross-built on Linux with the GCC MinGW Win32-thread toolchain. No separately installed MinGW runtime DLLs are required.
- Windows ARM64 shared: cross-built on Linux with LLVM-MinGW 20260908 (LLVM 23.1.1), targeting native ARM64 rather than ARM64EC. Uses the UCRT provided by Windows 10/11 on ARM. JPEG, zlib and the LLVM C++ runtime are linked statically; only the two package DLLs and Windows system DLLs are needed.
- Windows static: both architectures are built separately with clang-cl, the MSVC ABI and `/MT`, matching FFmpeg's Windows static libraries. These are true static archives, not DLL import libraries or renamed MinGW archives. Native AOT linking requires the matching MSVC tools and Windows SDK; the MinGW DLLs are not used by static publishes.
- WebAssembly: wasm32 static archives, with separate single-threaded and pthread-enabled builds using native wasm exceptions. Applications must use a compatible Emscripten/.NET wasm toolchain and configure cross-origin isolation for browser threads.

OpenMP, RawSpeed, the Adobe DNG SDK and the LCMS GPL plugins are not included. JPEG and zlib support are required at build time. libjpeg-turbo uses the JPEG v8 API, without its TurboJPEG API/tools or SIMD assembly. The upstream `lcms2.19.1` tag reports API version `2190` / Autotools version `2.19`; the source is pinned to the actual 2.19.1 release commit.

## Licenses

LibRaw is available under LGPL-2.1-or-later or CDDL-1.0; Little CMS uses MIT; the libjpeg API uses the IJG license; zlib uses the zlib license. Their license and copyright files are included under `licenses/`. Static linking does not remove the applicable redistribution/relinking obligations. Windows and Android builds also contain their toolchains' standard C++ runtimes under their respective runtime licenses and exceptions.

This software is based in part on the work of the Independent JPEG Group.

Build scripts, exact source pins, and release instructions are in the [source repository](https://github.com/hjc4869/LightPlayer-Packages).
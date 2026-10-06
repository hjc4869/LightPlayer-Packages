# LightStudio.Ffmpeg

FFmpeg 9.0.2 native libraries for .NET, with AV1 decoding provided by dav1d 1.5.4, JPEG XL decoding by libjxl 0.11.2, and DASH manifest parsing by libxml2 2.15.3.

| Runtime | Linking | Location in the package |
| --- | --- | --- |
| `android-arm64`, `android-x64` | Shared (`.so`) | `runtimes/android-<arch>/native` |
| `win-x64`, `win-arm64` | Shared (`.dll`) | `runtimes/win-<arch>/native` |
| `win-x64`, `win-arm64` | Static (`.lib`, NativeAOT only) | `static/win-<arch>` |
| `osx-arm64` | Shared (`.dylib`) | `runtimes/osx-arm64/native` |
| `osx-arm64` | Static (`.a`, native AOT only) | `static/osx-arm64` |
| `ios-arm64` | Static (`.a`, device only) | `runtimes/ios-arm64/native` |
| `iossimulator-arm64` | Static (`.a`, ARM64 simulator) | `runtimes/iossimulator-arm64/native` |
| `browser-wasm`, single-threaded | Static (`.a`) | `static/wasm-em3`, `static/wasm-em6` |
| `browser-wasm`, multi-threaded | Static (`.a`) | `static/wasm-mt-em3`, `static/wasm-mt-em6` |

The FFmpeg command-line programs, networking, device and filter implementations, software encoders, and other optional external-library dependencies are not included. The `libavdevice`, `libavfilter`, and `libswscale` cores are included with their optional components disabled. macOS and iOS include VideoToolbox encoders; Windows includes Media Foundation encoders.

The HLS and DASH demuxers and file protocol are enabled for applications that provide manifests, playlists, and segment resources through `AVFormatContext.io_open`. FFmpeg networking remains disabled; HTTP transport belongs to the consuming application.

## Photo formats

| Format | Demuxer | Decoder |
| --- | --- | --- |
| JPEG | `image2`, `jpeg_pipe` | `mjpeg` |
| PNG / APNG | `image2`, `png_pipe`, `apng` | `png`, `apng` |
| WebP (still and animated) | `image2`, `webp_pipe`, `webp_anim` | `webp` |
| TIFF | `image2`, `tiff_pipe` | `tiff` |
| AVIF | `mov` | `libdav1d` |
| HEIC | `mov` | `hevc` |
| JPEG XL (still and animated) | `jpegxl_pipe`, `jpegxl_anim` | `libjxl`, `libjxl_anim` |

JPEG XL is unavailable in the single-threaded browser-wasm variant, because libjxl's parallel runner needs pthreads.

## Shared libraries

Shared libraries are deployed automatically by the .NET SDK on Android, macOS, and Windows. Android sonames are unversioned (`libavcodec.so`), macOS dylibs use `@rpath` install names, and Windows DLLs use versioned names (`avcodec-63.dll`). FFmpeg's internal dependencies resolve from the application's native library directory. dav1d and libjxl are linked statically into the codec library and libxml2 into the format library, without adding runtime library dependencies.

Supply managed bindings separately. For example, reference `FFmpeg.AutoGen.Bindings.DynamicallyLoaded` version `9.0.1.1` and initialize `FFmpeg.AutoGen.Bindings.DynamicallyLoaded.DynamicallyLoadedBindings.Initialize()` before calling FFmpeg. Shared deployment works with ordinary .NET applications and NativeAOT; leave `EnableStaticFfmpeg` unset or `false`.

## iOS

Target `ios-arm64` for devices or `iossimulator-arm64` for the ARM64 simulator
with .NET for iOS. The SDK automatically links the `.a`
assets in `runtimes/<rid>/native/`; no package-specific linking targets,
manual archive references, or `EnableStaticFfmpeg` setting are needed. Use
static bindings with `__Internal`, not a dynamic library loader.

The build targets iOS 15 or later and retains the macOS codec, format, pthread,
and VideoToolbox configuration. Hardware codec availability depends on the
device and OS. All third-party dependencies are static; the application must
link the system `c++` and `z` libraries and the `CoreMedia`, `CoreVideo`, and
`VideoToolbox` frameworks through its iOS linker settings. Intel simulator
archives are not included. Static linking carries the LGPL obligations below.

Build on macOS with full Xcode and the iPhoneOS/iPhoneSimulator SDK using
`bash scripts/build-ffmpeg-osx-arm64.sh ios-arm64` or
`bash scripts/build-ffmpeg-osx-arm64.sh iossimulator-arm64`. The existing script defaults
to macOS when no argument is supplied. Set `IPHONEOS_DEPLOYMENT_TARGET` to
override the iOS minimum consistently across FFmpeg and its dependencies for
both device and simulator builds. Their archives are built separately and are
not interchangeable, even though both use ARM64.

## WebAssembly

The package injects the matching archives as `NativeFileReference` items automatically. `WasmEnableThreads=true` selects `static/wasm-mt-em<major>`; otherwise `static/wasm-em<major>` is used. Target frameworks through .NET 10 select `em3` (Emscripten 3.1.69); .NET 11 and newer select `em6` (6.0.2). This is a best-effort compatibility rule, not a guarantee for every workload/toolchain version. Multi-threaded applications must serve the cross-origin isolation headers that browser pthreads require. zlib and libxml2 are included as static archives, so the consuming project does not need to provide them.

## Windows

Windows libraries use the MSVC ABI and static MSVC C/C++ runtime (`/MT`), built with clang-cl, the Windows SDK, and the MSVC librarian. Both architectures ship 7 FFmpeg DLLs for shared deployment and 17 COFF `.lib` archives for static NativeAOT linking. The DLLs embed dav1d, JPEG XL, Brotli, Highway, libxml2, zlib, and the MSVC runtime, so no separate third-party or MinGW runtime DLLs are needed. The static archives include these dependencies separately and are not DLL import libraries. Windows libraries target Windows 10 or later; the consuming .NET version may impose additional requirements.

The format selection matches macOS. D3D11VA decoding is enabled for H.264, HEVC, AV1, VP9, MPEG-2, VC-1, and WMV3. Media Foundation provides `aac_mf`, `ac3_mf`, `av1_mf`, `h264_mf`, `hevc_mf`, and `mp3_mf` encoders. Set the encoder option `hw_encoding=1` to require hardware encoding. Runtime availability depends on Windows components, the GPU/driver, and the codec profile; Media Foundation is an encoding API in this FFmpeg build, not a separate decoding backend.

Assembly optimizations and runtime CPU detection are enabled. x64 uses NASM and inline assembly, including runtime-dispatched AVX2 and AVX-512 paths; JPEG XL's AVX-512 variants are enabled too. ARM64 uses Clang's assembler for NEON and supported architecture extensions, including dot-product, I8MM, SVE, and SME. Runtime dispatch keeps newer instructions off unsupported CPUs. skcms symbols are isolated from Skia's copy.

## Static linking with native AOT

Set `EnableStaticFfmpeg` to link the static archives into the AOT binary instead of deploying the shared libraries:

```xml
<PropertyGroup>
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <PublishAot>true</PublishAot>
  <EnableStaticFfmpeg>true</EnableStaticFfmpeg>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="FFmpeg.AutoGen.Bindings.StaticallyLinked" Version="9.0.1.1" />
  <DirectPInvoke Include="__Internal" />
</ItemGroup>
```

Use `win-x64`, `win-arm64`, or `osx-arm64`. Initialize `FFmpeg.AutoGen.Bindings.StaticallyLinked.StaticallyLinkedBindings.Initialize()` before using the abstractions, and do not initialize the dynamically loaded bindings in that build. Other P/Invoke bindings need equivalent direct-call configuration.

The package adds the native archives and required system libraries: `mfuuid`, `ole32`, `strmiids`, `user32`, and `bcrypt` on Windows; `c++`, `z`, `CoreMedia`, `CoreVideo`, and `VideoToolbox` on macOS. Windows and macOS shared libraries are removed from static publish output. `EnableStaticFfmpeg` is ignored without `PublishAot` and on unsupported RIDs. `LightStudioFfmpegStaticLibraryDir` can override the archive directory for local builds; Windows consumers fail early if any required archive is missing.

## Licensing

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later; dav1d under the BSD 2-Clause license; libjxl and skcms under the BSD 3-Clause license; highway under the Apache License 2.0; brotli and libxml2 under the MIT license; and zlib under the zlib license. The upstream licensing files are included in the package under `licenses/`.

Windows builds explicitly disable GPL, nonfree, and version-3-only FFmpeg components. Static linking still carries LGPL obligations: distributors must provide the applicable notices and source, and a way to relink the application with a modified library, such as suitable application object files and build instructions. A NativeAOT executable or this NuGet package alone is not a complete relinking kit.

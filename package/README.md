# LightStudio.Ffmpeg

FFmpeg 9.0.1 native libraries for .NET, with AV1 decoding provided by dav1d 1.5.4, JPEG XL decoding by libjxl 0.11.2, and DASH manifest parsing by libxml2 2.15.3.

| Runtime | Linking | Location in the package |
| --- | --- | --- |
| `android-arm64`, `android-x64` | Shared (`.so`) | `runtimes/android-<arch>/native` |
| `osx-arm64` | Shared (`.dylib`) | `runtimes/osx-arm64/native` |
| `osx-arm64` | Static (`.a`, native AOT only) | `static/osx-arm64` |
| `browser-wasm`, single-threaded | Static (`.a`) | `static/wasm` |
| `browser-wasm`, multi-threaded | Static (`.a`) | `static/wasm-mt` |

The FFmpeg command-line programs, networking, device and filter implementations, encoders, and other optional external-library dependencies are not included. The `libavdevice`, `libavfilter`, and `libswscale` cores are included with their optional components disabled.

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

## Android and macOS

Shared libraries are deployed automatically by the .NET SDK. Android sonames are unversioned (`libavcodec.so`) and the macOS dylibs use `@rpath` install names, so FFmpeg's internal dependencies resolve from the application's native library directory. dav1d and libjxl are linked statically into `libavcodec` and libxml2 into `libavformat`, without adding runtime library dependencies.

## WebAssembly

The package injects the matching archives as `NativeFileReference` items automatically. The variant is selected from `WasmEnableThreads`: when it is `true` the pthread-enabled archives from `static/wasm-mt` are linked, otherwise the single-threaded archives from `static/wasm`. Multi-threaded applications must serve the cross-origin isolation headers that browser pthreads require. zlib and libxml2 are included as static archives, so the consuming project does not need to provide them.

## Static linking with native AOT

Set `EnableStaticFfmpeg` to link the static archives into the AOT binary instead of deploying the shared libraries:

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <EnableStaticFfmpeg>true</EnableStaticFfmpeg>
</PropertyGroup>
```

The package then adds the `NativeLibrary` items and the `c++`, `z`, `CoreMedia`, `CoreVideo`, and `VideoToolbox` linker arguments, and removes the package's shared libraries from the publish output. The property is ignored when `PublishAot` is not enabled and on runtimes that ship shared libraries only, such as Android.

## Licensing

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later; dav1d under the BSD 2-Clause license; libjxl and skcms under the BSD 3-Clause license; highway under the Apache License 2.0; brotli and libxml2 under the MIT license; and zlib under the zlib license. The upstream licensing files are included in the package under `licenses/`.

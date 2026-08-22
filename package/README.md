# LightStudio.Ffmpeg

FFmpeg 8.1.2 native libraries for .NET, with AV1 decoding provided by dav1d 1.5.4.

| Runtime | Linking | Location in the package |
| --- | --- | --- |
| `android-arm64`, `android-x64` | Shared (`.so`) | `runtimes/android-<arch>/native` |
| `osx-arm64` | Shared (`.dylib`) | `runtimes/osx-arm64/native` |
| `osx-arm64` | Static (`.a`, native AOT only) | `static/osx-arm64` |
| `browser-wasm`, single-threaded | Static (`.a`) | `static/wasm` |
| `browser-wasm`, multi-threaded | Static (`.a`) | `static/wasm-mt` |

The FFmpeg command-line programs, networking, device and filter implementations, encoders, and optional external-library dependencies are not included. The `libavdevice`, `libavfilter`, and `libswscale` cores are included with their optional components disabled.

## Android and macOS

Shared libraries are deployed automatically by the .NET SDK. Android sonames are unversioned (`libavcodec.so`) and the macOS dylibs use `@rpath` install names, so FFmpeg's internal dependencies resolve from the application's native library directory. dav1d is linked statically into `libavcodec.so` on Android.

## WebAssembly

The package injects the matching archives as `NativeFileReference` items automatically. The variant is selected from `WasmEnableThreads`: when it is `true` the pthread-enabled archives from `static/wasm-mt` are linked, otherwise the single-threaded archives from `static/wasm`. Multi-threaded applications must serve the cross-origin isolation headers that browser pthreads require.

## Static linking with native AOT

Set `EnableStaticFfmpeg` to link the static archives into the AOT binary instead of deploying the shared libraries:

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <EnableStaticFfmpeg>true</EnableStaticFfmpeg>
</PropertyGroup>
```

The package then adds the `NativeLibrary` items and the `CoreMedia`, `CoreVideo`, and `VideoToolbox` linker arguments, and removes the package's shared libraries from the publish output. The property is ignored when `PublishAot` is not enabled and on runtimes that ship shared libraries only, such as Android.

## Licensing

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later, and dav1d under the BSD 2-Clause license. The upstream licensing files are included in the package under `licenses/`.

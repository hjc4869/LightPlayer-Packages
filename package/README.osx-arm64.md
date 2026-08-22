# LightStudio.Ffmpeg.osx-arm64

This package contains FFmpeg 8.1.2 static and dynamic libraries compiled with Apple Clang for Apple silicon and the .NET `osx-arm64` runtime. The binaries target macOS 11.0 or later and use native pthread support.

The native assets are installed under `runtimes/osx-arm64/native`:

- `libavcodec.a`
- `libavdevice.a`
- `libavfilter.a`
- `libavformat.a`
- `libavutil.a`
- `libswresample.a`
- `libswscale.a`
- `libdav1d.a`
- `libavcodec.dylib` and its major-versioned dylib
- `libavdevice.dylib` and its major-versioned dylib
- `libavfilter.dylib` and its major-versioned dylib
- `libavformat.dylib` and its major-versioned dylib
- `libavutil.dylib` and its major-versioned dylib
- `libswresample.dylib` and its major-versioned dylib
- `libswscale.dylib` and its major-versioned dylib

The dynamic libraries use `@rpath` install names so their FFmpeg dependencies resolve from the application runtime directory.

AV1 is decoded by dav1d 1.5.4, which is built as part of this package. It is linked statically into the dylibs; link `libdav1d.a` explicitly when using the static archives.

The FFmpeg command-line programs, networking, device and filter implementations, encoders, and optional external-library dependencies are not included. The `libavdevice`, `libavfilter`, and `libswscale` library cores are included with their optional components disabled.

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later, and dav1d under the BSD 2-Clause license. The upstream licensing files are included in the package under `licenses/`.

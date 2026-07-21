# LightStudio.Ffmpeg.osx-arm64

This package contains FFmpeg 8.1.2 static and dynamic libraries compiled with Apple Clang for Apple silicon and the .NET `osx-arm64` runtime. The binaries target macOS 11.0 or later and use native pthread support.

The native assets are installed under `runtimes/osx-arm64/native`:

- `libavcodec.a`
- `libavformat.a`
- `libavutil.a`
- `libswresample.a`
- `libavcodec.dylib` and its major-versioned dylib
- `libavformat.dylib` and its major-versioned dylib
- `libavutil.dylib` and its major-versioned dylib
- `libswresample.dylib` and its major-versioned dylib

The dynamic libraries use `@rpath` install names so their FFmpeg dependencies resolve from the application runtime directory.

The FFmpeg command-line programs, networking, devices, filters, scaling, encoders, and optional external-library dependencies are not included.

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later. The upstream licensing files are included in the package under `licenses/`.

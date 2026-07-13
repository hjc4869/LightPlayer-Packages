# LightStudio.Ffmpeg.browser-wasm

This package contains FFmpeg 8.1.2 static libraries compiled with Emscripten for the .NET `browser-wasm` runtime.

The archives are installed under `runtimes/browser-wasm/native`:

- `libavcodec.a`
- `libavformat.a`
- `libavutil.a`
- `libswresample.a`

The FFmpeg command-line programs, networking, devices, filters, scaling, encoders, and shared libraries are not included.

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later. The upstream licensing files are included in the package under `licenses/`.
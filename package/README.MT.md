# LightStudio.Ffmpeg.MT.browser-wasm

This package contains pthread-enabled FFmpeg 8.1.2 static libraries compiled with Emscripten for the .NET `browser-wasm` runtime. The consuming WebAssembly application must enable shared memory and provide the required cross-origin isolation headers.

The archives are installed under `runtimes/browser-wasm/native`:

- `libavcodec.a`
- `libavformat.a`
- `libavutil.a`
- `libswresample.a`
- `libdav1d.a`

AV1 is decoded by dav1d 1.5.4, which is built as part of this package. Link `libdav1d.a` together with `libavcodec.a`.

The FFmpeg command-line programs, networking, devices, filters, scaling, encoders, and shared libraries are not included.

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later, and dav1d under the BSD 2-Clause license. The upstream licensing files are included in the package under `licenses/`.
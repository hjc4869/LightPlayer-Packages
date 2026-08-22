# LightStudio.Ffmpeg.Android

This package contains FFmpeg 8.1.2 shared libraries compiled with the Android NDK for the .NET `android-arm64` and `android-x64` runtimes. The binaries target Android API level 21 or later and use native (bionic) pthread support.

The native assets are installed under `runtimes/android-arm64/native` and `runtimes/android-x64/native`:

- `libavcodec.so`
- `libavdevice.so`
- `libavfilter.so`
- `libavformat.so`
- `libavutil.so`
- `libswresample.so`
- `libswscale.so`

The shared libraries use unversioned Android sonames (`libavcodec.so`, `libavutil.so`, and so on) so their FFmpeg dependencies resolve from the application's native library directory.

AV1 is decoded by dav1d 1.5.4, which is linked statically into `libavcodec.so`; no additional native asset has to be deployed.

The FFmpeg command-line programs, networking, device and filter implementations, encoders, static archives, and optional external-library dependencies are not included. The `libavdevice`, `libavfilter`, and `libswscale` library cores are included with their optional components disabled.

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later, and dav1d under the BSD 2-Clause license. The upstream licensing files are included in the package under `licenses/`.

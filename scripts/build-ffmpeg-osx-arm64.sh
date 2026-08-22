#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ffmpeg_dir="$repo_root/ffmpeg"
artifact_name="ffmpeg-osx-arm64"
build_dir="${FFMPEG_BUILD_DIR:-$repo_root/artifacts/build/$artifact_name}"
artifacts_dir="${FFMPEG_ARTIFACTS_DIR:-$repo_root/artifacts/$artifact_name}"
deployment_target="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This build must run on macOS." >&2
  exit 1
fi

if [[ ! -x "$ffmpeg_dir/configure" ]]; then
  echo "FFmpeg is not initialized at '$ffmpeg_dir'. Run 'git submodule update --init'." >&2
  exit 1
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
cc="$(xcrun --sdk macosx --find clang)"
cxx="$(xcrun --sdk macosx --find clang++)"
ar="$(xcrun --sdk macosx --find ar)"
ranlib="$(xcrun --sdk macosx --find ranlib)"
nm="$(xcrun --sdk macosx --find nm)"
strip="$(xcrun --sdk macosx --find strip)"
lipo="$(xcrun --sdk macosx --find lipo)"
otool="$(xcrun --sdk macosx --find otool)"
target_flags="-arch arm64 -mmacosx-version-min=$deployment_target"

if [[ -f "$ffmpeg_dir/ffbuild/config.mak" ]]; then
  make -C "$ffmpeg_dir" distclean
fi

rm -rf -- "$build_dir"
mkdir -p "$build_dir"

dav1d_prefix="$build_dir/dav1d"
MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$repo_root/scripts/build-dav1d.sh" \
  osx-arm64 "$dav1d_prefix" "$build_dir/dav1d-build"

# Keep pkg-config away from the host libraries while cross-compiling.
export PKG_CONFIG_LIBDIR="$dav1d_prefix/lib/pkgconfig"
export PKG_CONFIG_PATH="$dav1d_prefix/lib/pkgconfig"

cd "$build_dir"

"$ffmpeg_dir/configure" \
  --cc="$cc" \
  --cxx="$cxx" \
  --ar="$ar" \
  --ranlib="$ranlib" \
  --nm="$nm" \
  --strip="$strip" \
  --target-os=darwin \
  --arch=arm64 \
  --enable-cross-compile \
  --sysroot="$sdk_path" \
  --extra-cflags="$target_flags" \
  --extra-cxxflags="$target_flags" \
  --extra-ldflags="$target_flags" \
  --enable-static \
  --enable-shared \
  --install-name-dir=@rpath \
  --enable-pic \
  --enable-pthreads \
  --disable-w32threads \
  --disable-os2threads \
  --disable-programs \
  --disable-debug \
  --disable-doc \
  --enable-swscale \
  --enable-avfilter \
  --enable-avdevice \
  --disable-filters \
  --disable-devices \
  --disable-network \
  --disable-autodetect \
  --enable-videotoolbox \
  --disable-vaapi \
  --disable-vdpau \
  --disable-d3d11va \
  --disable-dxva2 \
  --disable-runtime-cpudetect \
  --disable-protocols \
  --disable-bsfs \
  --disable-muxers \
  --disable-demuxers \
  --disable-parsers \
  --disable-decoders \
  --disable-encoders \
  --pkg-config-flags=--static \
  --enable-libdav1d \
  --enable-decoder=libdav1d \
  --enable-parser=aac \
  --enable-parser=aac_latm \
  --enable-parser=flac \
  --enable-parser=mpegaudio \
  --enable-parser=tak \
  --enable-parser=vorbis \
  --enable-parser=h264 \
  --enable-parser=hevc \
  --enable-parser=mpeg4video \
  --enable-parser=mpegvideo \
  --enable-parser=vp8 \
  --enable-parser=vp9 \
  --enable-parser=av1 \
  --enable-parser=vc1 \
  --enable-parser=mjpeg \
  --enable-parser=h263 \
  --enable-parser=ac3 \
  --enable-parser=dca \
  --enable-parser=opus \
  --enable-parser=mlp \
  --enable-demuxer=aac \
  --enable-demuxer=ape \
  --enable-demuxer=asf \
  --enable-demuxer=mov \
  --enable-demuxer=matroska \
  --enable-demuxer=mpegts \
  --enable-demuxer=mpegps \
  --enable-demuxer=flv \
  --enable-demuxer=avi \
  --enable-demuxer=h264 \
  --enable-demuxer=hevc \
  --enable-demuxer=m4v \
  --enable-demuxer=mpegvideo \
  --enable-demuxer=ogg \
  --enable-demuxer=flac \
  --enable-demuxer=tak \
  --enable-demuxer=tta \
  --enable-demuxer=wav \
  --enable-demuxer=xwma \
  --enable-demuxer=mp3 \
  --enable-demuxer=pcm_alaw \
  --enable-demuxer=pcm_f32be \
  --enable-demuxer=pcm_f32le \
  --enable-demuxer=pcm_f64be \
  --enable-demuxer=pcm_f64le \
  --enable-demuxer=pcm_mulaw \
  --enable-demuxer=pcm_s16be \
  --enable-demuxer=pcm_s16le \
  --enable-demuxer=pcm_s24be \
  --enable-demuxer=pcm_s24le \
  --enable-demuxer=pcm_s32be \
  --enable-demuxer=pcm_s32le \
  --enable-demuxer=pcm_s8 \
  --enable-demuxer=pcm_u16be \
  --enable-demuxer=pcm_u16le \
  --enable-demuxer=pcm_u24be \
  --enable-demuxer=pcm_u24le \
  --enable-demuxer=pcm_u32be \
  --enable-demuxer=pcm_u32le \
  --enable-demuxer=pcm_u8 \
  --enable-decoder=aac \
  --enable-decoder=alac \
  --enable-decoder=ape \
  --enable-decoder=flac \
  --enable-decoder=mp3float \
  --enable-decoder=tak \
  --enable-decoder=tta \
  --enable-decoder=vorbis \
  --enable-decoder=wmalossless \
  --enable-decoder=wmapro \
  --enable-decoder=wmav1 \
  --enable-decoder=wmav2 \
  --enable-decoder=h264 \
  --enable-decoder=hevc \
  --enable-decoder=mpeg1video \
  --enable-decoder=mpeg2video \
  --enable-decoder=mpeg4 \
  --enable-decoder=msmpeg4v1 \
  --enable-decoder=msmpeg4v2 \
  --enable-decoder=msmpeg4v3 \
  --enable-decoder=vc1 \
  --enable-decoder=wmv1 \
  --enable-decoder=wmv2 \
  --enable-decoder=wmv3 \
  --enable-decoder=vp8 \
  --enable-decoder=vp9 \
  --enable-decoder=av1 \
  --enable-decoder=theora \
  --enable-decoder=flv \
  --enable-decoder=h263 \
  --enable-decoder=mjpeg \
  --enable-decoder=prores \
  --enable-decoder=ac3 \
  --enable-decoder=eac3 \
  --enable-decoder=dca \
  --enable-decoder=opus \
  --enable-decoder=mp1float \
  --enable-decoder=mp2float \
  --enable-decoder=truehd \
  --enable-decoder=pcm_alaw \
  --enable-decoder=pcm_f32be \
  --enable-decoder=pcm_f32le \
  --enable-decoder=pcm_f64be \
  --enable-decoder=pcm_f64le \
  --enable-decoder=pcm_lxf \
  --enable-decoder=pcm_mulaw \
  --enable-decoder=pcm_s16be \
  --enable-decoder=pcm_s16be_planar \
  --enable-decoder=pcm_s16le \
  --enable-decoder=pcm_s16le_planar \
  --enable-decoder=pcm_s24be \
  --enable-decoder=pcm_s24daud \
  --enable-decoder=pcm_s24le \
  --enable-decoder=pcm_s24le_planar \
  --enable-decoder=pcm_s32be \
  --enable-decoder=pcm_s32le \
  --enable-decoder=pcm_s32le_planar \
  --enable-decoder=pcm_s8 \
  --enable-decoder=pcm_s8_planar \
  --enable-decoder=pcm_u16be \
  --enable-decoder=pcm_u16le \
  --enable-decoder=pcm_u24be \
  --enable-decoder=pcm_u24le \
  --enable-decoder=pcm_u32be \
  --enable-decoder=pcm_u32le \
  --enable-decoder=pcm_u8 \
  --enable-encoder=h264_videotoolbox \
  --enable-encoder=hevc_videotoolbox \
  --enable-encoder=prores_videotoolbox \
  --enable-stripping

if ! grep -q '^#define HAVE_PTHREADS 1$' config.h; then
  echo "FFmpeg did not configure pthread support for macOS." >&2
  exit 1
fi

if ! grep -q '^#define CONFIG_LIBDAV1D_DECODER 1$' config_components.h; then
  echo "FFmpeg did not enable the libdav1d decoder for macOS." >&2
  exit 1
fi

build_jobs="${FFMPEG_BUILD_JOBS:-$(sysctl -n hw.logicalcpu)}"
make -j"$build_jobs"

archives=(
  "$build_dir/libavdevice/libavdevice.a"
  "$build_dir/libavfilter/libavfilter.a"
  "$build_dir/libavcodec/libavcodec.a"
  "$build_dir/libavformat/libavformat.a"
  "$build_dir/libavutil/libavutil.a"
  "$build_dir/libswresample/libswresample.a"
  "$build_dir/libswscale/libswscale.a"
  "$dav1d_prefix/lib/libdav1d.a"
)

library_names=(libavdevice libavfilter libavcodec libavformat libavutil libswresample libswscale)
dynamic_libraries=()

for library_name in "${library_names[@]}"; do
  library_dir="$build_dir/$library_name"
  dylib_link="$library_dir/$library_name.dylib"

  if [[ ! -L "$dylib_link" ]]; then
    echo "Expected FFmpeg dynamic library link was not built: $dylib_link" >&2
    exit 1
  fi

  dylib_target="$library_dir/$(readlink "$dylib_link")"
  if [[ ! -f "$dylib_target" ]]; then
    echo "Expected FFmpeg dynamic library was not built: $dylib_target" >&2
    exit 1
  fi

  dynamic_libraries+=("$dylib_link" "$dylib_target")
done

for archive in "${archives[@]}"; do
  if [[ ! -f "$archive" ]]; then
    echo "Expected FFmpeg archive was not built: $archive" >&2
    exit 1
  fi

  if ! "$lipo" "$archive" -verify_arch arm64; then
    echo "Expected an arm64 FFmpeg archive: $archive" >&2
    exit 1
  fi
done

for dynamic_library in "${dynamic_libraries[@]}"; do
  if ! "$lipo" "$dynamic_library" -verify_arch arm64; then
    echo "Expected an arm64 FFmpeg dynamic library: $dynamic_library" >&2
    exit 1
  fi

  if [[ -L "$dynamic_library" ]]; then
    dynamic_library_name="$(readlink "$dynamic_library")"
  else
    dynamic_library_name="$(basename "$dynamic_library")"
  fi

  expected_install_name="@rpath/$(basename "$dynamic_library_name")"
  if ! "$otool" -D "$dynamic_library" | grep -Fxq "$expected_install_name"; then
    echo "Expected '$expected_install_name' as the install name for $dynamic_library" >&2
    exit 1
  fi
done

rm -rf -- "$artifacts_dir"
mkdir -p "$artifacts_dir"

for archive in "${archives[@]}"; do
  cp "$archive" "$artifacts_dir/"
done

for dynamic_library in "${dynamic_libraries[@]}"; do
  cp -L "$dynamic_library" "$artifacts_dir/"
done

printf "Staged %d FFmpeg archives and %d dynamic libraries for 'osx-arm64' in %s\n" \
  "${#archives[@]}" "${#dynamic_libraries[@]}" "$artifacts_dir"

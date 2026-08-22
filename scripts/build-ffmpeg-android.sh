#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ffmpeg_dir="$repo_root/ffmpeg"
artifact_name="ffmpeg-android"
build_root="${FFMPEG_BUILD_DIR:-$repo_root/artifacts/build/$artifact_name}"
artifacts_root="${FFMPEG_ARTIFACTS_DIR:-$repo_root/artifacts/$artifact_name}"
android_api="${ANDROID_API_LEVEL:-21}"
android_ndk_home="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_ROOT:-}}}"

if [[ ! -x "$ffmpeg_dir/configure" ]]; then
  echo "FFmpeg is not initialized at '$ffmpeg_dir'. Run 'git submodule update --init'." >&2
  exit 1
fi

if [[ -z "$android_ndk_home" || ! -d "$android_ndk_home" ]]; then
  echo "Android NDK not found. Set ANDROID_NDK_HOME to a valid NDK installation." >&2
  exit 1
fi

shopt -s nullglob
prebuilt_dirs=("$android_ndk_home"/toolchains/llvm/prebuilt/*/)
shopt -u nullglob

if [[ ${#prebuilt_dirs[@]} -eq 0 ]]; then
  echo "No LLVM toolchain was found under '$android_ndk_home/toolchains/llvm/prebuilt'." >&2
  exit 1
fi

toolchain="${prebuilt_dirs[0]%/}"
toolchain_bin="$toolchain/bin"
sysroot="$toolchain/sysroot"
ar="$toolchain_bin/llvm-ar"
ranlib="$toolchain_bin/llvm-ranlib"
nm="$toolchain_bin/llvm-nm"
strip="$toolchain_bin/llvm-strip"
readelf="$toolchain_bin/llvm-readelf"

for tool in "$ar" "$ranlib" "$nm" "$strip" "$readelf"; do
  if [[ ! -x "$tool" ]]; then
    echo "Expected the NDK to provide '$tool'." >&2
    exit 1
  fi
done

library_names=(libavdevice libavfilter libavcodec libavformat libavutil libswresample libswscale)

if [[ -f "$ffmpeg_dir/ffbuild/config.mak" ]]; then
  make -C "$ffmpeg_dir" distclean
fi

rm -rf -- "$artifacts_root"

build_abi() {
  local abi="$1"
  local ffmpeg_arch triple dotnet_rid elf_machine
  case "$abi" in
    arm64)
      ffmpeg_arch=aarch64
      triple=aarch64-linux-android
      dotnet_rid=android-arm64
      elf_machine=AArch64
      ;;
    x64)
      ffmpeg_arch=x86_64
      triple=x86_64-linux-android
      dotnet_rid=android-x64
      elf_machine=X86-64
      ;;
    *)
      echo "Unknown Android ABI '$abi'. Expected 'arm64' or 'x64'." >&2
      exit 2
      ;;
  esac

  local cc="$toolchain_bin/${triple}${android_api}-clang"
  local cxx="$toolchain_bin/${triple}${android_api}-clang++"

  if [[ ! -x "$cc" || ! -x "$cxx" ]]; then
    echo "Expected the NDK to provide the '$triple' compilers for API $android_api." >&2
    exit 1
  fi

  local build_dir="$build_root/$dotnet_rid"
  local artifacts_dir="$artifacts_root/$dotnet_rid"
  local dav1d_prefix="$build_dir/dav1d"

  rm -rf -- "$build_dir"
  mkdir -p "$build_dir"

  ANDROID_API_LEVEL="$android_api" "$repo_root/scripts/build-dav1d.sh" \
    "$dotnet_rid" "$dav1d_prefix" "$build_dir/dav1d-build"

  # Keep pkg-config away from the host libraries while cross-compiling.
  export PKG_CONFIG_LIBDIR="$dav1d_prefix/lib/pkgconfig"
  export PKG_CONFIG_PATH="$dav1d_prefix/lib/pkgconfig"

  pushd "$build_dir" >/dev/null

  "$ffmpeg_dir/configure" \
    --cc="$cc" \
    --cxx="$cxx" \
    --ar="$ar" \
    --ranlib="$ranlib" \
    --nm="$nm" \
    --strip="$strip" \
    --target-os=android \
    --arch="$ffmpeg_arch" \
    --enable-cross-compile \
    --sysroot="$sysroot" \
    --disable-static \
    --enable-shared \
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
    --enable-jni \
    --enable-mediacodec \
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
    --enable-decoder=h264_mediacodec \
    --enable-decoder=hevc_mediacodec \
    --enable-decoder=mpeg4_mediacodec \
    --enable-decoder=mpeg2_mediacodec \
    --enable-decoder=vp8_mediacodec \
    --enable-decoder=vp9_mediacodec \
    --enable-decoder=av1_mediacodec \
    --enable-encoder=h264_mediacodec \
    --enable-encoder=hevc_mediacodec \
    --enable-stripping

  if ! grep -q '^#define HAVE_PTHREADS 1$' config.h; then
    echo "FFmpeg did not configure pthread support for Android $dotnet_rid." >&2
    exit 1
  fi

  if ! grep -q '^#define CONFIG_LIBDAV1D_DECODER 1$' config_components.h; then
    echo "FFmpeg did not enable the libdav1d decoder for Android $dotnet_rid." >&2
    exit 1
  fi

  local build_jobs="${FFMPEG_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
  make -j"$build_jobs"

  mkdir -p "$artifacts_dir"

  local library_name library_dir slib_link dest header dynamic
  for library_name in "${library_names[@]}"; do
    library_dir="$build_dir/$library_name"
    slib_link="$library_dir/$library_name.so"

    if [[ ! -e "$slib_link" ]]; then
      echo "Expected FFmpeg shared library was not built: $slib_link" >&2
      exit 1
    fi

    dest="$artifacts_dir/$library_name.so"
    cp -L "$slib_link" "$dest"

    # Read the tool output into variables rather than piping into 'grep -q'.
    # Under 'set -o pipefail', 'grep -q' can exit as soon as it matches and
    # close the pipe, leaving llvm-readelf killed by SIGPIPE; that would fail
    # the pipeline even though the pattern was found.
    header="$("$readelf" -h "$dest")"
    if ! grep -iq "$elf_machine" <<<"$header"; then
      echo "Expected an $elf_machine FFmpeg shared library: $dest" >&2
      echo "$header" >&2
      exit 1
    fi

    dynamic="$("$readelf" -d "$dest")"
    if ! grep -Fq "Library soname: [$library_name.so]" <<<"$dynamic"; then
      echo "Expected '$library_name.so' as the soname for $dest" >&2
      echo "$dynamic" >&2
      exit 1
    fi

    # The package ships no libdav1d.so, so dav1d has to be linked statically.
    if grep -Fq "Shared library: [libdav1d" <<<"$dynamic"; then
      echo "Expected dav1d to be linked statically into $dest" >&2
      echo "$dynamic" >&2
      exit 1
    fi
  done

  popd >/dev/null

  printf "Staged %d FFmpeg shared libraries for '%s' in %s\n" \
    "${#library_names[@]}" "$dotnet_rid" "$artifacts_dir"
}

for abi in arm64 x64; do
  build_abi "$abi"
done

printf "Completed Android FFmpeg build for android-arm64 and android-x64 in %s\n" "$artifacts_root"

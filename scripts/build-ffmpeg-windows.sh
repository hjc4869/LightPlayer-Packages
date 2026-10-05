#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"
case "$target" in
  win-x64) arch=x86_64; triple=x86_64-pc-windows-msvc; processor=AMD64; vc_arch=x64 ;;
  win-arm64) arch=aarch64; triple=aarch64-pc-windows-msvc; processor=ARM64; vc_arch=arm64 ;;
  *) echo "Usage: build-ffmpeg-windows.sh <win-x64|win-arm64>" >&2; exit 2 ;;
esac

if [[ "$(uname -s)" != MSYS* && "$(uname -s)" != MINGW* ]]; then
  echo "Run this build in MSYS2 with the Visual Studio developer environment inherited." >&2
  exit 1
fi
if [[ "${VSCMD_ARG_TGT_ARCH:-}" != "$vc_arch" ]]; then
  echo "Initialize the Visual Studio '$vc_arch' target environment before starting MSYS2." >&2
  exit 1
fi
for tool in clang-cl clang lld-link lib.exe llvm-lib llvm-nm llvm-readobj cmake ninja meson nasm make pkg-config; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "'$tool' is required to build FFmpeg for Windows." >&2
    exit 1
  fi
done

ffmpeg_dir="$repo_root/ffmpeg"
if [[ ! -f "$ffmpeg_dir/configure" ]]; then
  echo "Initialize the ffmpeg, dav1d, libjxl, libxml2 and zlib submodules first." >&2
  exit 1
fi

build_dir="${FFMPEG_BUILD_DIR:-$repo_root/artifacts/build/ffmpeg-$target}"
artifacts_dir="${FFMPEG_ARTIFACTS_DIR:-$repo_root/artifacts/ffmpeg-$target}"
build_jobs="${FFMPEG_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN)}"
dav1d_prefix="$build_dir/dav1d"
libjxl_prefix="$build_dir/libjxl"
libxml2_prefix="$build_dir/libxml2"
zlib_prefix="$build_dir/zlib"
mkdir -p "$build_dir"

if [[ "${FFMPEG_REUSE_DEPS:-0}" != 1 ]]; then
  bash "$repo_root/scripts/build-dav1d.sh" "$target" "$dav1d_prefix" "$build_dir/dav1d-build"
  bash "$repo_root/scripts/build-libjxl.sh" "$target" "$libjxl_prefix" "$build_dir/libjxl-build"
  bash "$repo_root/scripts/build-libxml2.sh" "$target" "$libxml2_prefix" "$build_dir/libxml2-build"
fi

MSYS2_ARG_CONV_EXCL='*' cmake -G Ninja \
  -S "$(cygpath -m "$repo_root/zlib")" -B "$(cygpath -m "$build_dir/zlib-build")" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR="$processor" \
  -DCMAKE_C_COMPILER=clang-cl -DCMAKE_C_COMPILER_TARGET="$triple" \
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
  -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$zlib_prefix")" -DCMAKE_INSTALL_LIBDIR=lib \
  -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON -DZLIB_BUILD_TESTING=OFF
cmake --build "$(cygpath -m "$build_dir/zlib-build")" --parallel "$build_jobs"
cmake --install "$(cygpath -m "$build_dir/zlib-build")"
cp "$zlib_prefix/lib/zs.lib" "$zlib_prefix/lib/zlib.lib"

export PKG_CONFIG_LIBDIR="$dav1d_prefix/lib/pkgconfig:$libjxl_prefix/lib/pkgconfig:$libxml2_prefix/lib/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export MSYS2_ARG_CONV_EXCL=

parsers=(
  aac aac_latm flac mpegaudio tak vorbis h264 hevc mpeg4video mpegvideo
  vp8 vp9 av1 vc1 mjpeg h263 ac3 dca opus mlp png webp jpegxl
)
demuxers=(
  aac ape asf dash hls mov matroska mpegts mpegps flv avi h264 hevc m4v
  mpegvideo ogg flac tak tta wav xwma mp3 pcm_alaw pcm_f32be pcm_f32le
  pcm_f64be pcm_f64le pcm_mulaw pcm_s16be pcm_s16le pcm_s24be pcm_s24le
  pcm_s32be pcm_s32le pcm_s8 pcm_u16be pcm_u16le pcm_u24be pcm_u24le
  pcm_u32be pcm_u32le pcm_u8 image2 image2pipe image_jpeg_pipe image_png_pipe
  image_webp_pipe image_tiff_pipe image_jpegxl_pipe jpegxl_anim webp_anim apng sup
)
decoders=(
  libdav1d libjxl libjxl_anim pgssub aac alac ape flac mp3float tak tta vorbis
  wmalossless wmapro wmav1 wmav2 h264 hevc mpeg1video mpeg2video mpeg4
  msmpeg4v1 msmpeg4v2 msmpeg4v3 vc1 wmv1 wmv2 wmv3 vp8 vp9 av1 theora flv
  h263 mjpeg prores ac3 eac3 dca opus mp1float mp2float truehd pcm_alaw
  pcm_bluray pcm_dvd pcm_f16le pcm_f24le pcm_f32be pcm_f32le pcm_f64be
  pcm_f64le pcm_lxf pcm_mulaw pcm_s16be pcm_s16be_planar pcm_s16le
  pcm_s16le_planar pcm_s24be pcm_s24daud pcm_s24le pcm_s24le_planar pcm_s32be
  pcm_s32le pcm_s32le_planar pcm_s64be pcm_s64le pcm_s8 pcm_s8_planar pcm_sga
  pcm_u16be pcm_u16le pcm_u24be pcm_u24le pcm_u32be pcm_u32le pcm_u8 pcm_vidc
  png apng webp tiff
)
component_args=()
for component in "${parsers[@]}"; do component_args+=(--enable-parser="$component"); done
for component in "${demuxers[@]}"; do component_args+=(--enable-demuxer="$component"); done
for component in "${decoders[@]}"; do component_args+=(--enable-decoder="$component"); done
for component in av1 h264 hevc mpeg2 vc1 vp9 wmv3; do
  component_args+=(--enable-hwaccel="${component}_d3d11va" --enable-hwaccel="${component}_d3d11va2")
done

configure_args=(
  --prefix="$(cygpath -m "$artifacts_dir")"
  --toolchain=msvc --target-os=win32 --arch="$arch" --enable-cross-compile
  --cc="clang-cl --target=$triple -MT" --cxx="clang-cl --target=$triple -MT"
  --ld=lld-link --ar=lib.exe --nm=llvm-nm --ranlib=:
  --as="clang --target=$triple" --x86asmexe=nasm
  --host-cc=clang --host-ld=clang
  --extra-cflags="-D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 -I$(cygpath -m "$zlib_prefix/include")"
  --extra-cxxflags="-D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00"
  --extra-ldflags="-libpath:$(cygpath -m "$zlib_prefix/lib")"
  --disable-gpl --disable-nonfree --disable-version3
  --enable-asm --enable-inline-asm --enable-optimizations --enable-runtime-cpudetect
  --enable-w32threads --disable-pthreads --disable-os2threads
  --disable-programs --disable-debug --disable-doc --disable-autodetect
  --enable-swscale --enable-avfilter --enable-avdevice
  --disable-filters --disable-devices --disable-network
  --enable-d3d11va --enable-mediafoundation
  --disable-dxva2 --disable-d3d12va --disable-vaapi --disable-vdpau --disable-videotoolbox
  --disable-protocols --enable-protocol=file
  --disable-bsfs --disable-muxers --disable-demuxers --disable-parsers
  --disable-decoders --disable-encoders --disable-hwaccels
  --pkg-config-flags=--static --enable-zlib --enable-libxml2 --enable-libdav1d --enable-libjxl
  --enable-encoder=aac_mf,ac3_mf,av1_mf,h264_mf,hevc_mf,mp3_mf
  "${component_args[@]}"
)

library_names=(avcodec avdevice avfilter avformat avutil swresample swscale)
for linkage in static shared; do
  ffmpeg_build_dir="$build_dir/ffmpeg"
  build_info_dir="$artifacts_dir/build-info"
  linkage_args=(--enable-static --disable-shared)
  shared=0
  if [[ "$linkage" == shared ]]; then
    ffmpeg_build_dir="$build_dir/ffmpeg-shared"
    build_info_dir="$artifacts_dir/build-info/shared"
    linkage_args=(--disable-static --enable-shared)
    shared=1
  fi
  mkdir -p "$ffmpeg_build_dir"
  cd "$ffmpeg_build_dir"
  "$ffmpeg_dir/configure" "${configure_args[@]}" "${linkage_args[@]}"

  for feature in W32THREADS INLINE_ASM; do
    grep -q "^#define HAVE_$feature 1$" config.h || { echo "Missing $feature for $target ($linkage)." >&2; exit 1; }
  done
  for feature in D3D11VA MEDIAFOUNDATION LIBDAV1D LIBJXL LIBXML2 ZLIB RUNTIME_CPUDETECT; do
    grep -q "^#define CONFIG_$feature 1$" config.h || { echo "Missing $feature for $target ($linkage)." >&2; exit 1; }
  done
  for feature in GPL NONFREE VERSION3 NETWORK; do
    grep -q "^#define CONFIG_$feature 0$" config.h || { echo "Unexpected $feature for $target ($linkage)." >&2; exit 1; }
  done
  grep -q "^#define CONFIG_SHARED $shared$" config.h
  grep -q "^#define CONFIG_STATIC $((1 - shared))$" config.h
  for component in DASH_DEMUXER HLS_DEMUXER FILE_PROTOCOL SUP_DEMUXER PGSSUB_DECODER \
    LIBDAV1D_DECODER LIBJXL_DECODER LIBJXL_ANIM_DECODER PNG_DECODER WEBP_DECODER TIFF_DECODER \
    H264_D3D11VA_HWACCEL HEVC_D3D11VA_HWACCEL AV1_D3D11VA_HWACCEL VP9_D3D11VA_HWACCEL \
    H264_MF_ENCODER HEVC_MF_ENCODER AV1_MF_ENCODER; do
    grep -q "^#define CONFIG_$component 1$" config_components.h || { echo "Missing $component for $target ($linkage)." >&2; exit 1; }
  done
  if [[ "$target" == win-x64 ]]; then
    assembly_features=(X86ASM SSE2_EXTERNAL AVX2_EXTERNAL AVX512_EXTERNAL)
  else
    assembly_features=(NEON_EXTERNAL ARMV8_EXTERNAL ARM_CRC DOTPROD I8MM PMULL EOR3 SVE SVE2 SME SME_I16I64 SME2)
  fi
  for feature in "${assembly_features[@]}"; do
    grep -q "^#define HAVE_$feature 1$" config.h || { echo "Missing $feature assembly for $target ($linkage)." >&2; exit 1; }
  done

  make -j"$build_jobs"
  mkdir -p "$build_info_dir"
  for library in "${library_names[@]}"; do
    if [[ "$linkage" == static ]]; then
      archive="$ffmpeg_build_dir/lib$library/$library.lib"
      cp "$archive" "$artifacts_dir/$library.lib"
    else
      shopt -s nullglob
      dlls=("$ffmpeg_build_dir/lib$library/$library"-*.dll)
      shopt -u nullglob
      if [[ ${#dlls[@]} -ne 1 ]]; then
        echo "Expected one $library DLL for $target, found ${#dlls[@]}." >&2
        exit 1
      fi
      imports="$(llvm-readobj --coff-imports "${dlls[0]}")"
      if grep -Ei 'Name:.*(dav1d|jxl|hwy|brotli|xml2|zlib|libgcc|libstdc\+\+|libwinpthread|msys-|vcruntime|msvcp).*\.dll' <<<"$imports"; then
        echo "Unexpected external runtime dependency in '${dlls[0]}'." >&2
        exit 1
      fi
      cp "${dlls[0]}" "$artifacts_dir/"
    fi
  done
  cp config.h config_components.h ffbuild/config.mak ffbuild/config.log "$build_info_dir/"
  make install-headers
done

cp "$dav1d_prefix/lib/dav1d.lib" "$libxml2_prefix/lib/xml2.lib" "$zlib_prefix/lib/zlib.lib" "$artifacts_dir/"
for library in jxl jxl_cms jxl_threads hwy brotlicommon brotlidec brotlienc; do
  cp "$libjxl_prefix/lib/$library.lib" "$artifacts_dir/"
done

machine=IMAGE_FILE_MACHINE_AMD64
if [[ "$target" == win-arm64 ]]; then machine=IMAGE_FILE_MACHINE_ARM64; fi
llvm-readobj --file-headers "$artifacts_dir"/*.lib "$artifacts_dir"/*.dll |
  awk -v machine="$machine" '/Machine:/ { count++; if ($2 != machine) { print; failed = 1 } }
    END { if (!count || failed) exit 1 }'

printf "Built LGPL FFmpeg MSVC static and shared libraries for '%s' in %s\n" "$target" "$artifacts_dir"
#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ffmpeg_dir="$repo_root/ffmpeg"
variant="${1:-single-threaded}"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [single-threaded|multi-threaded]" >&2
  exit 2
fi

case "$variant" in
  single-threaded)
    artifact_name="ffmpeg-browser-wasm"
    dav1d_target="browser-wasm-st"
    thread_options=(--disable-pthreads --disable-w32threads --disable-os2threads)
    expected_pthreads=0
    # libjxl's parallel runner is std::thread based and FFmpeg always asks it
    # for av_cpu_count() workers, which aborts in a module without pthreads.
    enable_libjxl=0
    ;;
  multi-threaded)
    artifact_name="ffmpeg-MT-browser-wasm"
    dav1d_target="browser-wasm-mt"
    thread_options=()
    expected_pthreads=1
    enable_libjxl=1
    ;;
  *)
    echo "Unknown build variant '$variant'. Expected 'single-threaded' or 'multi-threaded'." >&2
    exit 2
    ;;
esac

build_dir="${FFMPEG_BUILD_DIR:-$repo_root/artifacts/build/$artifact_name}"
artifacts_dir="${FFMPEG_ARTIFACTS_DIR:-$repo_root/artifacts/$artifact_name}"

if [[ ! -x "$ffmpeg_dir/configure" ]]; then
  echo "FFmpeg is not initialized at '$ffmpeg_dir'. Run 'git submodule update --init'." >&2
  exit 1
fi

if [[ -f "$ffmpeg_dir/ffbuild/config.mak" ]]; then
  make -C "$ffmpeg_dir" distclean
fi

rm -rf -- "$build_dir"
mkdir -p "$build_dir"

dav1d_prefix="$build_dir/dav1d"
"$repo_root/scripts/build-dav1d.sh" "$dav1d_target" "$dav1d_prefix" "$build_dir/dav1d-build"

libxml2_prefix="$build_dir/libxml2"
"$repo_root/scripts/build-libxml2.sh" "$dav1d_target" "$libxml2_prefix" "$build_dir/libxml2-build"

pkg_config_path="$dav1d_prefix/lib/pkgconfig:$libxml2_prefix/lib/pkgconfig"
libjxl_options=()
libjxl_prefix="$build_dir/libjxl"

if [[ "$enable_libjxl" -eq 1 ]]; then
  "$repo_root/scripts/build-libjxl.sh" browser-wasm-mt "$libjxl_prefix" "$build_dir/libjxl-build"
  pkg_config_path="$pkg_config_path:$libjxl_prefix/lib/pkgconfig"
  libjxl_options=(--enable-libjxl --enable-decoder=libjxl --enable-decoder=libjxl_anim)
fi

# emconfigure forwards EM_PKG_CONFIG_PATH to PKG_CONFIG_PATH.
export EM_PKG_CONFIG_PATH="$pkg_config_path"

cd "$build_dir"

# zlib comes from the Emscripten port; its archive is staged next to the FFmpeg
# ones so consumers do not have to enable the port themselves.
zlib_flag="-sUSE_ZLIB=1"

emconfigure "$ffmpeg_dir/configure" \
  --extra-cflags="$zlib_flag" \
  --extra-cxxflags="$zlib_flag" \
  --extra-ldflags="$zlib_flag" \
  --cc=emcc \
  --cxx=em++ \
  --ar=emar \
  --ranlib=emranlib \
  --nm=emnm \
  --target-os=none \
  --arch=wasm \
  --enable-cross-compile \
  --enable-static \
  "${thread_options[@]}" \
  --disable-shared \
  --disable-programs \
  --disable-debug \
  --disable-doc \
  --enable-swscale \
  --enable-avfilter \
  --enable-avdevice \
  --disable-filters \
  --disable-devices \
  --disable-network \
  --disable-vaapi \
  --disable-vdpau \
  --disable-d3d11va \
  --disable-dxva2 \
  --disable-runtime-cpudetect \
  --disable-protocols \
  --enable-protocol=file \
  --disable-bsfs \
  --disable-muxers \
  --disable-demuxers \
  --disable-parsers \
  --disable-decoders \
  --disable-encoders \
  --pkg-config-flags=--static \
  --enable-zlib \
  --enable-libxml2 \
  --enable-libdav1d \
  --enable-decoder=libdav1d \
  "${libjxl_options[@]}" \
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
  --enable-parser=png \
  --enable-parser=webp \
  --enable-parser=jpegxl \
  --enable-demuxer=aac \
  --enable-demuxer=ape \
  --enable-demuxer=asf \
  --enable-demuxer=dash \
  --enable-demuxer=hls \
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
  --enable-demuxer=image2 \
  --enable-demuxer=image2pipe \
  --enable-demuxer=image_jpeg_pipe \
  --enable-demuxer=image_png_pipe \
  --enable-demuxer=image_webp_pipe \
  --enable-demuxer=image_tiff_pipe \
  --enable-demuxer=image_jpegxl_pipe \
  --enable-demuxer=jpegxl_anim \
  --enable-demuxer=webp_anim \
  --enable-demuxer=apng \
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
  --enable-decoder=pcm_bluray \
  --enable-decoder=pcm_dvd \
  --enable-decoder=pcm_f16le \
  --enable-decoder=pcm_f24le \
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
  --enable-decoder=pcm_s64be \
  --enable-decoder=pcm_s64le \
  --enable-decoder=pcm_s8 \
  --enable-decoder=pcm_s8_planar \
  --enable-decoder=pcm_sga \
  --enable-decoder=pcm_u16be \
  --enable-decoder=pcm_u16le \
  --enable-decoder=pcm_u24be \
  --enable-decoder=pcm_u24le \
  --enable-decoder=pcm_u32be \
  --enable-decoder=pcm_u32le \
  --enable-decoder=pcm_u8 \
  --enable-decoder=pcm_vidc \
  --enable-decoder=png \
  --enable-decoder=apng \
  --enable-decoder=webp \
  --enable-decoder=tiff \
  --enable-stripping

if ! grep -q "^#define HAVE_PTHREADS $expected_pthreads$" config.h; then
  echo "FFmpeg configured an unexpected pthread state for '$variant'." >&2
  exit 1
fi

if ! grep -q '^#define CONFIG_LIBDAV1D_DECODER 1$' config_components.h; then
  echo "FFmpeg did not enable the libdav1d decoder for '$variant'." >&2
  exit 1
fi

if ! grep -q '^#define CONFIG_ZLIB 1$' config.h; then
  echo "FFmpeg did not enable zlib for '$variant'; the PNG decoder needs it." >&2
  exit 1
fi

if ! grep -q '^#define CONFIG_LIBXML2 1$' config.h; then
  echo "FFmpeg did not enable libxml2 for DASH in '$variant'." >&2
  exit 1
fi

if ! grep -q '^#define CONFIG_NETWORK 0$' config.h; then
  echo "FFmpeg unexpectedly enabled networking for '$variant'." >&2
  exit 1
fi

for protocol in HTTP HTTPS TCP TLS; do
  if ! grep -q "^#define CONFIG_${protocol}_PROTOCOL 0$" config_components.h; then
    echo "FFmpeg unexpectedly enabled the $protocol protocol for '$variant'." >&2
    exit 1
  fi
done

for component in DASH_DEMUXER HLS_DEMUXER FILE_PROTOCOL \
  PNG_DECODER WEBP_DECODER TIFF_DECODER MJPEG_DECODER \
  IMAGE_PNG_PIPE_DEMUXER IMAGE_JPEG_PIPE_DEMUXER IMAGE_WEBP_PIPE_DEMUXER \
  IMAGE_TIFF_PIPE_DEMUXER; do
  if ! grep -q "^#define CONFIG_$component 1$" config_components.h; then
    echo "FFmpeg did not enable $component for '$variant'." >&2
    exit 1
  fi
done

if [[ "$enable_libjxl" -eq 1 ]] && ! grep -q '^#define CONFIG_LIBJXL_DECODER 1$' config_components.h; then
  echo "FFmpeg did not enable the libjxl decoder for '$variant'." >&2
  exit 1
fi

emmake make -j32

zlib_archive="$(em-config CACHE)/sysroot/lib/wasm32-emscripten/libz.a"
if [[ ! -f "$zlib_archive" ]]; then
  echo "The Emscripten zlib port did not produce '$zlib_archive'." >&2
  exit 1
fi

archives=(
  "$build_dir/libavcodec/libavcodec.a"
  "$build_dir/libavdevice/libavdevice.a"
  "$build_dir/libavformat/libavformat.a"
  "$build_dir/libavfilter/libavfilter.a"
  "$build_dir/libavutil/libavutil.a"
  "$build_dir/libswresample/libswresample.a"
  "$build_dir/libswscale/libswscale.a"
  "$dav1d_prefix/lib/libdav1d.a"
  "$libxml2_prefix/lib/libxml2.a"
  "$zlib_archive"
)

if [[ "$enable_libjxl" -eq 1 ]]; then
  archives+=(
    "$libjxl_prefix/lib/libjxl.a"
    "$libjxl_prefix/lib/libjxl_cms.a"
    "$libjxl_prefix/lib/libjxl_threads.a"
    "$libjxl_prefix/lib/libhwy.a"
    "$libjxl_prefix/lib/libbrotlicommon.a"
    "$libjxl_prefix/lib/libbrotlidec.a"
    "$libjxl_prefix/lib/libbrotlienc.a"
  )
fi

for archive in "${archives[@]}"; do
  if [[ ! -f "$archive" ]]; then
    echo "Expected FFmpeg archive was not built: $archive" >&2
    exit 1
  fi
done

rm -rf -- "$artifacts_dir"
mkdir -p "$artifacts_dir"

for archive in "${archives[@]}"; do
  cp "$archive" "$artifacts_dir/"
done

printf "Staged %d FFmpeg archives for '%s' in %s\n" "${#archives[@]}" "$variant" "$artifacts_dir"
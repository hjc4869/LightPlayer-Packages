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
    thread_options=(--disable-pthreads --disable-w32threads --disable-os2threads)
    expected_pthreads=0
    ;;
  multi-threaded)
    artifact_name="ffmpeg-MT-browser-wasm"
    thread_options=()
    expected_pthreads=1
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
cd "$build_dir"

emconfigure "$ffmpeg_dir/configure" \
  --cc=emcc \
  --cxx=em++ \
  --ar=emar \
  --ranlib=emranlib \
  --nm=emnm \
  --target-os=none \
  --arch=x86_32 \
  --enable-cross-compile \
  --disable-x86asm \
  --disable-inline-asm \
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
  --disable-bsfs \
  --disable-muxers \
  --disable-demuxers \
  --disable-parsers \
  --disable-decoders \
  --disable-encoders \
  --enable-parser=aac \
  --enable-parser=aac_latm \
  --enable-parser=flac \
  --enable-parser=mpegaudio \
  --enable-parser=tak \
  --enable-parser=vorbis \
  --enable-demuxer=aac \
  --enable-demuxer=ape \
  --enable-demuxer=asf \
  --enable-demuxer=mov \
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
  --enable-stripping

if ! grep -q "^#define HAVE_PTHREADS $expected_pthreads$" config.h; then
  echo "FFmpeg configured an unexpected pthread state for '$variant'." >&2
  exit 1
fi

emmake make -j32

archives=(
  "$build_dir/libavcodec/libavcodec.a"
  "$build_dir/libavdevice/libavdevice.a"
  "$build_dir/libavformat/libavformat.a"
  "$build_dir/libavfilter/libavfilter.a"
  "$build_dir/libavutil/libavutil.a"
  "$build_dir/libswresample/libswresample.a"
  "$build_dir/libswscale/libswscale.a"
)

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
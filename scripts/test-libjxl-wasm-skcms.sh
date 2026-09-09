#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo 'Usage: test-libjxl-wasm-skcms.sh <browser-wasm-st|browser-wasm-mt> <prefix> <build-dir>' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$1"
prefix="$2"
build_dir="$3"
skcms_dir="$repo_root/libjxl/third_party/skcms"
compile_flags=(-O2 -DSKCMS_DISABLE_HSW -DSKCMS_DISABLE_SKX)
link_flags=(-sENVIRONMENT=node -sALLOW_MEMORY_GROWTH=1 -sASSERTIONS=1 -sEXIT_RUNTIME=1)
case "$target" in
  browser-wasm-st) ;;
  browser-wasm-mt)
    compile_flags+=(-pthread)
    link_flags+=(-pthread -sPROXY_TO_PTHREAD=1)
    ;;
  *) echo "Unsupported skcms test target '$target'." >&2; exit 2 ;;
esac

mkdir -p "$build_dir"
for source in skcms.cc src/skcms_TransformBaseline.cc; do
  em++ "${compile_flags[@]}" -I"$skcms_dir" -c "$skcms_dir/$source" \
    -o "$build_dir/$(basename "$source").o"
done
emar rcs "$build_dir/libskcms-independent.a" \
  "$build_dir/skcms.cc.o" "$build_dir/skcms_TransformBaseline.cc.o"

for order in libjxl-first skcms-first; do
  if [[ "$order" == libjxl-first ]]; then
    archives=("$prefix/lib/libjxl_cms.a" "$build_dir/libskcms-independent.a")
  else
    archives=("$build_dir/libskcms-independent.a" "$prefix/lib/libjxl_cms.a")
  fi
  em++ "${compile_flags[@]}" "${link_flags[@]}" \
    -I"$prefix/include" -I"$skcms_dir" \
    "$repo_root/tests/ffmpeg/skcms-coexistence.cc" \
    -Wl,--whole-archive "${archives[@]}" -Wl,--no-whole-archive \
    "$prefix/lib/libjxl.a" "$prefix/lib/libhwy.a" \
    "$prefix/lib/libbrotlidec.a" "$prefix/lib/libbrotlicommon.a" \
    --embed-file "$skcms_dir/profiles/mobile/Display_P3_parametric.icc@/display-p3.icc" \
    --embed-file "$skcms_dir/profiles/mobile/sRGB_parametric.icc@/srgb.icc" \
    -o "$build_dir/$order.js"
  node "$build_dir/$order.js"
done

printf "Verified independent skcms coexistence in both link orders for '%s'.\n" "$target"
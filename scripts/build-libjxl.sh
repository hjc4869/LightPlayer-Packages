#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
libjxl_dir="$repo_root/libjxl"

if [[ $# -ne 3 ]]; then
  cat >&2 <<'EOF'
Usage: build-libjxl.sh <target> <prefix> <build-dir>

Targets:
  browser-wasm-st  Emscripten, no shared memory (single-threaded FFmpeg package)
  browser-wasm-mt  Emscripten with pthreads
  android-arm64    Android NDK, aarch64
  android-x64      Android NDK, x86_64
  osx-arm64        macOS, Apple silicon
EOF
  exit 2
fi

target="$1"
prefix="$2"
build_dir="$3"

if [[ ! -f "$libjxl_dir/CMakeLists.txt" ]]; then
  echo "libjxl is not initialized at '$libjxl_dir'. Run 'git submodule update --init'." >&2
  exit 1
fi

for tool in cmake ninja; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "'$tool' is required to build libjxl." >&2
    exit 1
  fi
done

# libjxl compiles brotli, highway and skcms from its own submodules; the FFmpeg
# builds never link system copies of them.
for dependency in brotli highway skcms; do
  if [[ -z "$(ls -A "$libjxl_dir/third_party/$dependency" 2>/dev/null)" ]]; then
    echo "libjxl's '$dependency' submodule is empty. Run scripts/fetch-libjxl-dependencies.sh." >&2
    exit 1
  fi
done

rm -rf -- "$build_dir" "$prefix"
mkdir -p "$build_dir"

# Decoder-only configuration: no tools, no plugins, no encoders' extra
# dependencies, everything static so it can be linked into FFmpeg.
cmake_args=(
  -G Ninja
  -S "$libjxl_dir"
  -B "$build_dir"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$prefix"
  -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_INSTALL_INCLUDEDIR=include
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_TESTING=OFF
  -DJPEGXL_ENABLE_SKCMS=ON
  -DJPEGXL_ENABLE_TOOLS=OFF
  -DJPEGXL_ENABLE_DEVTOOLS=OFF
  -DJPEGXL_ENABLE_BENCHMARK=OFF
  -DJPEGXL_ENABLE_EXAMPLES=OFF
  -DJPEGXL_ENABLE_MANPAGES=OFF
  -DJPEGXL_ENABLE_DOXYGEN=OFF
  -DJPEGXL_ENABLE_JNI=OFF
  -DJPEGXL_ENABLE_JPEGLI=OFF
  -DJPEGXL_ENABLE_SJPEG=OFF
  -DJPEGXL_ENABLE_OPENEXR=OFF
  -DJPEGXL_ENABLE_PLUGINS=OFF
  -DJPEGXL_ENABLE_VIEWERS=OFF
  -DJPEGXL_ENABLE_FUZZERS=OFF
  -DJPEGXL_ENABLE_COVERAGE=OFF
  -DJPEGXL_BUNDLE_LIBPNG=OFF
  -DJPEGXL_FORCE_SYSTEM_BROTLI=OFF
  -DJPEGXL_FORCE_SYSTEM_HWY=OFF
  -DJPEGXL_WARNINGS_AS_ERRORS=OFF
)

configure=(cmake)

require_ndk_tool() {
  if [[ ! -x "$1" ]]; then
    echo "Expected the NDK to provide '$1'." >&2
    exit 1
  fi
}

case "$target" in
  browser-wasm-st | browser-wasm-mt)
    for tool in emcmake emcc em++ emnm; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "'$tool' is required to build libjxl for browser-wasm." >&2
        exit 1
      fi
    done

    configure=(emcmake cmake)

    if [[ "$target" == browser-wasm-st ]]; then
      # JPEGXL_ENABLE_WASM_THREADS adds -pthread, which marks the objects as
      # shared memory and makes them unlinkable into a single-threaded module.
      cmake_args+=(-DJPEGXL_ENABLE_WASM_THREADS=OFF)
    else
      cmake_args+=(-DJPEGXL_ENABLE_WASM_THREADS=ON)
    fi
    ;;

  android-arm64 | android-x64)
    android_api="${ANDROID_API_LEVEL:-21}"
    android_ndk_home="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_ROOT:-}}}"

    if [[ -z "$android_ndk_home" || ! -d "$android_ndk_home" ]]; then
      echo "Android NDK not found. Set ANDROID_NDK_HOME to a valid NDK installation." >&2
      exit 1
    fi

    toolchain_file="$android_ndk_home/build/cmake/android.toolchain.cmake"
    if [[ ! -f "$toolchain_file" ]]; then
      echo "Expected the NDK to provide '$toolchain_file'." >&2
      exit 1
    fi

    if [[ "$target" == android-arm64 ]]; then
      android_abi=arm64-v8a
    else
      android_abi=x86_64
    fi

    cmake_args+=(
      -DCMAKE_TOOLCHAIN_FILE="$toolchain_file"
      -DANDROID_ABI="$android_abi"
      -DANDROID_PLATFORM="android-$android_api"
      # FFmpeg links libavcodec.so with the C compiler driver, so the C++
      # runtime has to come from a static archive rather than libc++_shared.so.
      -DANDROID_STL=c++_static
    )
    ;;

  osx-arm64)
    deployment_target="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

    if [[ "$(uname -s)" != "Darwin" ]]; then
      echo "The osx-arm64 libjxl build must run on macOS." >&2
      exit 1
    fi

    cmake_args+=(
      -DCMAKE_OSX_ARCHITECTURES=arm64
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
    )

    export MACOSX_DEPLOYMENT_TARGET="$deployment_target"
    ;;

  *)
    echo "Unknown libjxl target '$target'." >&2
    exit 2
    ;;
esac

build_jobs="${LIBJXL_BUILD_JOBS:-${FFMPEG_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}}"

"${configure[@]}" "${cmake_args[@]}"
cmake --build "$build_dir" --target jxl_cms --parallel "$build_jobs"
nm_tool="$(sed -n 's/^CMAKE_NM:[^=]*=//p' "$build_dir/CMakeCache.txt")"
if [[ "$target" == browser-wasm-* ]]; then
  nm_tool="$(command -v emnm)"
fi
if [[ ! -x "$nm_tool" ]]; then
  echo "CMake did not select an executable nm tool: '$nm_tool'." >&2
  exit 1
fi
skcms_symbols="$build_dir/skcms-symbols.txt"
skcms_namespace="$build_dir/skcms-namespace.h"
skcms_objects="$build_dir/lib/CMakeFiles/jxl_cms.dir/__/third_party/skcms"
"$nm_tool" -g "$skcms_objects"/*.o "$skcms_objects"/src/*.o |
  awk -v target="$target" 'NF >= 2 && $(NF - 1) ~ /^[ABCDGRSTVW]$/ {
    symbol = $NF;
    if (target == "osx-arm64") sub(/^_/, "", symbol);
    if (symbol ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && symbol !~ /^_Z/) print symbol
  }' | LC_ALL=C sort -u > "$skcms_symbols"
awk '{ printf "#define %s lightstudio_ffmpeg_%s\n", $1, $1 }' \
  "$skcms_symbols" > "$skcms_namespace"
printf '#define skcms_private lightstudio_ffmpeg_skcms_private\n' >> "$skcms_namespace"
grep -q '^#define skcms_Transform ' "$skcms_namespace"
for language in C CXX; do
  compiler_flags="$(sed -n "s/^CMAKE_${language}_FLAGS:STRING=//p" "$build_dir/CMakeCache.txt")"
  cmake_args+=("-DCMAKE_${language}_FLAGS=$compiler_flags -include \"$skcms_namespace\"")
done
"${configure[@]}" "${cmake_args[@]}"
# The default target is used on purpose: brotli's install rules cover its CLI,
# so building only the libraries leaves 'cmake --install' without input files.
cmake --build "$build_dir" --parallel "$build_jobs"
cmake --install "$build_dir"

static_libraries=(
  "$prefix/lib/libjxl.a"
  "$prefix/lib/libjxl_cms.a"
  "$prefix/lib/libjxl_threads.a"
  "$prefix/lib/libhwy.a"
  "$prefix/lib/libbrotlicommon.a"
  "$prefix/lib/libbrotlidec.a"
  "$prefix/lib/libbrotlienc.a"
)

pkg_config_files=(
  "$prefix/lib/pkgconfig/libjxl.pc"
  "$prefix/lib/pkgconfig/libjxl_cms.pc"
  "$prefix/lib/pkgconfig/libjxl_threads.pc"
  "$prefix/lib/pkgconfig/libhwy.pc"
  "$prefix/lib/pkgconfig/libbrotlicommon.pc"
  "$prefix/lib/pkgconfig/libbrotlidec.pc"
  "$prefix/lib/pkgconfig/libbrotlienc.pc"
)

for artifact in "${static_libraries[@]}" "${pkg_config_files[@]}"; do
  if [[ ! -f "$artifact" ]]; then
    echo "libjxl did not produce '$artifact'." >&2
    exit 1
  fi
done

skcms_conflicts="$("$nm_tool" -g "${static_libraries[@]}" |
  awk -v symbols="$skcms_symbols" -v target="$target" '
    BEGIN {
      while ((getline symbol < symbols) > 0) original[symbol] = 1;
      close(symbols);
    }
    NF >= 2 {
      symbol = $NF;
      if (target == "osx-arm64") sub(/^_/, "", symbol);
      if (symbol in original || symbol ~ /^skcms_/ || symbol ~ /^_Z.*13skcms_private/)
        print symbol;
    }' |
  LC_ALL=C sort -u)"
if [[ -n "$skcms_conflicts" ]]; then
  printf 'libjxl exposes or imports unprefixed skcms symbols:\n%s\n' "$skcms_conflicts" >&2
  exit 1
fi

if [[ "$target" == browser-wasm-st ]]; then
  # Nothing in the single-threaded package may carry the shared-memory flags.
  for pkg_config_file in "${pkg_config_files[@]}"; do
    sed -i.bak -E 's/ -pthread//g' "$pkg_config_file"
    rm -f -- "$pkg_config_file.bak"
  done
fi

# FFmpeg links its configure test programs and libavcodec with the C driver, so
# the C++ runtime libjxl needs has to be named by the .pc files. libjxl writes
# '-lc++' whenever the compiler is clang, which the NDK sysroot does not provide
# (it ships libc++_static.a and libc++abi.a next to libc++_shared.so).
case "$target" in
  android-*) cxx_runtime_libs="-lc++_static -lc++abi" ;;
  *) cxx_runtime_libs="-lc++" ;;
esac

for pkg_config_file in "${pkg_config_files[@]}"; do
  sed -i.bak -E "s/-lc\\+\\+( |\$)/$cxx_runtime_libs\\1/g" "$pkg_config_file"
  rm -f -- "$pkg_config_file.bak"
done

# libjxl_threads.pc only lists '-lm' even though the runner is std::thread based.
threads_pkg_config_file="$prefix/lib/pkgconfig/libjxl_threads.pc"
sed -i.bak -E "s/^Libs\\.private:.*/& $cxx_runtime_libs/" "$threads_pkg_config_file"
rm -f -- "$threads_pkg_config_file.bak"

for pkg_config_file in "$prefix/lib/pkgconfig/libjxl.pc" "$threads_pkg_config_file"; do
  if ! grep -Fq -- "$cxx_runtime_libs" "$pkg_config_file"; then
    echo "'$pkg_config_file' does not name the C++ runtime ($cxx_runtime_libs)." >&2
    exit 1
  fi
done

if [[ "$target" == browser-wasm-* ]]; then
  bash "$repo_root/scripts/test-libjxl-wasm-skcms.sh" "$target" "$prefix" "$build_dir/skcms-coexistence"
fi

printf "Built libjxl %s for '%s' in %s\n" \
  "$(sed -n 's/^Version: *//p' "$prefix/lib/pkgconfig/libjxl.pc")" "$target" "$prefix"

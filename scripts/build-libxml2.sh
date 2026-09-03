#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
libxml2_dir="$repo_root/libxml2"

if [[ $# -ne 3 ]]; then
  cat >&2 <<'EOF'
Usage: build-libxml2.sh <target> <prefix> <build-dir>

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

if [[ ! -f "$libxml2_dir/CMakeLists.txt" ]]; then
  echo "libxml2 is not initialized at '$libxml2_dir'. Run 'git submodule update --init'." >&2
  exit 1
fi

for tool in cmake ninja; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "'$tool' is required to build libxml2." >&2
    exit 1
  fi
done

rm -rf -- "$build_dir" "$prefix"

cmake_args=(
  -G Ninja
  -S "$libxml2_dir"
  -B "$build_dir"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$prefix"
  -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_INSTALL_INCLUDEDIR=include
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DBUILD_SHARED_LIBS=OFF
  -DLIBXML2_WITH_DOCS=OFF
  -DLIBXML2_WITH_ICONV=OFF
  -DLIBXML2_WITH_ICU=OFF
  -DLIBXML2_WITH_MODULES=OFF
  -DLIBXML2_WITH_PROGRAMS=OFF
  -DLIBXML2_WITH_PYTHON=OFF
  -DLIBXML2_WITH_READLINE=OFF
  -DLIBXML2_WITH_TESTS=OFF
  -DLIBXML2_WITH_ZLIB=OFF
)

configure=(cmake)

case "$target" in
  browser-wasm-st | browser-wasm-mt)
    for tool in emcmake emcc; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "'$tool' is required to build libxml2 for browser-wasm." >&2
        exit 1
      fi
    done

    configure=(emcmake cmake)
    if [[ "$target" == browser-wasm-st ]]; then
      cmake_args+=(-DLIBXML2_WITH_THREADS=OFF)
    else
      cmake_args+=(-DLIBXML2_WITH_THREADS=ON)
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
      -DLIBXML2_WITH_THREADS=ON
    )
    ;;

  osx-arm64)
    deployment_target="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

    if [[ "$(uname -s)" != "Darwin" ]]; then
      echo "The osx-arm64 libxml2 build must run on macOS." >&2
      exit 1
    fi

    cmake_args+=(
      -DCMAKE_OSX_ARCHITECTURES=arm64
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
      -DLIBXML2_WITH_THREADS=ON
    )

    export MACOSX_DEPLOYMENT_TARGET="$deployment_target"
    ;;

  *)
    echo "Unknown libxml2 target '$target'." >&2
    exit 2
    ;;
esac

build_jobs="${LIBXML2_BUILD_JOBS:-${FFMPEG_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}}"

"${configure[@]}" "${cmake_args[@]}"
cmake --build "$build_dir" --parallel "$build_jobs"
cmake --install "$build_dir"

static_library="$prefix/lib/libxml2.a"
pkg_config_file="$prefix/lib/pkgconfig/libxml-2.0.pc"

for artifact in "$static_library" "$pkg_config_file"; do
  if [[ ! -f "$artifact" ]]; then
    echo "libxml2 did not produce '$artifact'." >&2
    exit 1
  fi
done

# FFmpeg probes <libxml2/libxml/xmlversion.h>, while its sources include
# <libxml/parser.h>, so a non-system prefix must expose both include roots.
sed -i.bak -E 's|^(Cflags:.*)$|\1 -I${includedir}|' "$pkg_config_file"
rm -f -- "$pkg_config_file.bak"

if ! grep -Fq -- '-I${includedir}/libxml2' "$pkg_config_file" ||
  ! grep -Fq -- '-I${includedir}' "$pkg_config_file"; then
  echo "libxml2 pkg-config metadata does not expose both required include roots." >&2
  exit 1
fi

if [[ "$target" == browser-wasm-st ]] && grep -q -- '-pthread' "$pkg_config_file"; then
  echo "Single-threaded libxml2 unexpectedly requires pthreads." >&2
  exit 1
fi

printf "Built libxml2 %s for '%s' in %s\n" \
  "$(sed -n 's/^Version: *//p' "$pkg_config_file")" "$target" "$prefix"
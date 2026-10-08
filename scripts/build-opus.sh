#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
opus_dir="$repo_root/opus"

if [[ $# -ne 3 ]]; then
  echo "Usage: build-opus.sh <osx-arm64|win-x64|win-arm64> <prefix> <build-dir>" >&2
  exit 2
fi

target="$1"
prefix="$2"
build_dir="$3"

if [[ "$target" == win-* ]]; then
  export MSYS2_ARG_CONV_EXCL='*'
  prefix="$(cygpath -m "$prefix")"
  build_dir="$(cygpath -m "$build_dir")"
  opus_dir="$(cygpath -m "$opus_dir")"
fi

if [[ ! -f "$opus_dir/CMakeLists.txt" ]]; then
  echo "Opus is not initialized at '$opus_dir'. Run 'git submodule update --init -- opus'." >&2
  exit 1
fi

for tool in cmake ninja; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "'$tool' is required to build Opus." >&2
    exit 1
  fi
done

cmake_args=(
  -G Ninja
  -S "$opus_dir"
  -B "$build_dir"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$prefix"
  -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DBUILD_SHARED_LIBS=OFF
  -DOPUS_BUILD_SHARED_LIBRARY=OFF
  -DOPUS_BUILD_TESTING=OFF
  -DOPUS_BUILD_PROGRAMS=OFF
  -DOPUS_INSTALL_PKG_CONFIG_MODULE=ON
)

case "$target" in
  osx-arm64)
    if [[ "$(uname -s)" != Darwin ]]; then
      echo "The osx-arm64 Opus build must run on macOS." >&2
      exit 1
    fi
    cmake_args+=(
      -DCMAKE_OSX_ARCHITECTURES=arm64
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-11.0}"
      -DOPUS_MAY_HAVE_NEON=OFF
      -DOPUS_PRESUME_NEON=ON
      "-DCMAKE_C_FLAGS=-DOPUS_ARM_MAY_HAVE_NEON -DOPUS_ARM_MAY_HAVE_NEON_INTR"
    )
    ;;
  win-x64 | win-arm64)
    if [[ "$target" == win-x64 ]]; then
      triple=x86_64-pc-windows-msvc
      processor=AMD64
    else
      triple=aarch64-pc-windows-msvc
      processor=ARM64
      cmake_args+=(
        -DOPUS_MAY_HAVE_NEON=OFF
        -DOPUS_PRESUME_NEON=ON
        "-DCMAKE_C_FLAGS=-DOPUS_ARM_MAY_HAVE_NEON -DOPUS_ARM_MAY_HAVE_NEON_INTR"
      )
    fi
    cmake_args+=(
      -DCMAKE_SYSTEM_NAME=Windows
      -DCMAKE_SYSTEM_PROCESSOR="$processor"
      -DCMAKE_C_COMPILER=clang-cl
      -DCMAKE_C_COMPILER_TARGET="$triple"
      -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
      -DOPUS_STATIC_RUNTIME=ON
    )
    ;;
  *)
    echo "Unknown Opus target '$target'." >&2
    exit 2
    ;;
esac

rm -rf -- "$build_dir" "$prefix"
build_jobs="${OPUS_BUILD_JOBS:-${FFMPEG_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN)}}"
cmake "${cmake_args[@]}"
cmake --build "$build_dir" --parallel "$build_jobs"
cmake --install "$build_dir"

printf "Built static Opus for '%s' in %s\n" "$target" "$prefix"
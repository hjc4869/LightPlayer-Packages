#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rid="${1:?Usage: build-sqlite-vec.sh <linux-x64|linux-arm64|win-x64|win-arm64|osx-x64|osx-arm64|android-x64|android-arm64>}"
build_dir="${SQLITE_VEC_BUILD_DIR:-$root/artifacts/build/sqlite-vec-$rid}"
prefix="${SQLITE_VEC_ARTIFACTS_DIR:-$root/artifacts}/sqlite-vec-$rid"
cmake_args=(-G Ninja -DCMAKE_BUILD_TYPE=Release "-DSQLITE_VEC_RID=$rid")

case "$rid" in
  linux-x64|linux-arm64)
    arch=x86_64
    [[ "$rid" != linux-arm64 ]] || arch=aarch64
    if [[ "$(uname -s)" != Linux || "$(uname -m)" != "$arch" ]]; then
      printf 'Build %s on a native %s Linux host.\n' "$rid" "$arch" >&2
      exit 1
    fi
    cmake_args+=("-DCMAKE_C_COMPILER=${CC:-cc}")
    ;;
  win-x64|win-arm64)
    if [[ "${OS:-}" != Windows_NT ]]; then
      printf 'Build %s on Windows with Visual Studio 2022 C++ tools installed.\n' "$rid" >&2
      exit 1
    fi
    arch=x64
    [[ "$rid" != win-arm64 ]] || arch=ARM64
    cmake_args=(-G 'Visual Studio 17 2022' -A "$arch" "-DSQLITE_VEC_RID=$rid")
    ;;
  osx-x64|osx-arm64)
    if [[ "$(uname -s)" != Darwin ]]; then
      printf 'Build %s on macOS with Xcode command-line tools installed.\n' "$rid" >&2
      exit 1
    fi
    arch=x86_64
    [[ "$rid" != osx-arm64 ]] || arch=arm64
    cmake_args+=("-DCMAKE_OSX_ARCHITECTURES=$arch"
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-11.0}")
    ;;
  android-x64|android-arm64)
    ndk="${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to Android NDK r28c or newer}"
    abi=x86_64
    [[ "$rid" != android-arm64 ]] || abi=arm64-v8a
    cmake_args+=("-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake"
      "-DANDROID_ABI=$abi" "-DANDROID_PLATFORM=android-${ANDROID_API_LEVEL:-27}")
    ;;
  *)
    printf 'Unsupported sqlite-vec RID: %s\n' "$rid" >&2
    exit 1
    ;;
esac

cmake -S "$root/scripts/sqlite-vec" -B "$build_dir" "${cmake_args[@]}"
cmake --build "$build_dir" --config Release --parallel "${JOBS:-3}"
cmake --install "$build_dir" --config Release --prefix "$prefix"

if [[ "$rid" == android-* ]]; then
  mkdir -p "$prefix/licenses/toolchain"
  cp "$ndk/toolchains/llvm/prebuilt/"*/NOTICE "$prefix/licenses/toolchain/NOTICE.toolchain"
elif [[ "$rid" == osx-* ]]; then
  codesign --force --sign - "$prefix/vec0.dylib"
fi
printf 'Built extension-only sqlite-vec for %s: %s\n' "$rid" "$prefix"
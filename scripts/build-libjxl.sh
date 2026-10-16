#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
libjxl_dir="$repo_root/libjxl"
lcms_dir="$repo_root/lcms2"

if [[ $# -ne 3 ]]; then
  cat >&2 <<'EOF'
Usage: build-libjxl.sh <target> <prefix> <build-dir>

Targets:
  browser-wasm-st  Emscripten, no shared memory (single-threaded FFmpeg package)
  browser-wasm-mt  Emscripten with pthreads
  android-arm64    Android NDK, aarch64
  android-x64      Android NDK, x86_64
  osx-arm64        macOS, Apple silicon
  ios-arm64        iOS devices, ARM64 (static only)
  iossimulator-arm64  iOS simulator, ARM64 (static only)
  win-x64          Windows, clang-cl/MSVC ABI, x86_64
  win-arm64        Windows, clang-cl/MSVC ABI, aarch64
EOF
  exit 2
fi

target="$1"
prefix="$2"
build_dir="$3"

if [[ "$target" == win-* ]]; then
  export MSYS2_ARG_CONV_EXCL='*'
  prefix="$(cygpath -m "$prefix")"
  build_dir="$(cygpath -m "$build_dir")"
  libjxl_dir="$(cygpath -m "$libjxl_dir")"
  lcms_dir="$(cygpath -m "$lcms_dir")"
fi

if [[ ! -f "$libjxl_dir/CMakeLists.txt" ]]; then
  echo "libjxl is not initialized at '$libjxl_dir'. Run 'git submodule update --init'." >&2
  exit 1
fi

if [[ ! -f "$lcms_dir/CMakeLists.txt" ]]; then
  echo "LCMS is not initialized at '$lcms_dir'. Run 'git submodule update --init lcms2'." >&2
  exit 1
fi

for tool in cmake ninja; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "'$tool' is required to build libjxl." >&2
    exit 1
  fi
done

for dependency in brotli highway; do
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
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$prefix"
  -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_INSTALL_INCLUDEDIR=include
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
)
jxl_args=(
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_TESTING=OFF
  -DJPEGXL_ENABLE_SKCMS=OFF
  -DJPEGXL_FORCE_SYSTEM_LCMS2=ON
  -DJPEGXL_ENABLE_TOOLS=OFF
  -DJPEGXL_ENABLE_DEVTOOLS=OFF
  -DJPEGXL_ENABLE_BENCHMARK=OFF
  -DJPEGXL_ENABLE_EXAMPLES=OFF
  -DJPEGXL_ENABLE_MANPAGES=OFF
  -DJPEGXL_ENABLE_DOXYGEN=OFF
  -DJPEGXL_ENABLE_JNI=OFF
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
lcms_threads=ON

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
    wasm_flags=-msimd128

    if [[ "$target" == browser-wasm-st ]]; then
      # JPEGXL_ENABLE_WASM_THREADS adds -pthread, which marks the objects as
      # shared memory and makes them unlinkable into a single-threaded module.
      jxl_args+=(-DJPEGXL_ENABLE_WASM_THREADS=OFF)
      lcms_threads=OFF
    else
      jxl_args+=(-DJPEGXL_ENABLE_WASM_THREADS=ON)
      wasm_flags+=' -pthread'
    fi
    cmake_args+=("-DCMAKE_C_FLAGS=$wasm_flags" "-DCMAKE_CXX_FLAGS=$wasm_flags"
      "-DCMAKE_EXE_LINKER_FLAGS=$wasm_flags")
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

  ios-arm64 | iossimulator-arm64)
    sdk=iphoneos
    [[ "$target" != iossimulator-arm64 ]] || sdk=iphonesimulator
    cmake_args+=(
      -DCMAKE_SYSTEM_NAME=iOS
      -DCMAKE_MACOSX_BUNDLE=OFF
      -DCMAKE_OSX_ARCHITECTURES=arm64
      "-DCMAKE_OSX_SYSROOT=$(xcrun --sdk "$sdk" --show-sdk-path)"
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
    )
    ;;

  win-x64 | win-arm64)
    if [[ "$target" == win-x64 ]]; then
      triple=x86_64-pc-windows-msvc
      processor=AMD64
    else
      triple=aarch64-pc-windows-msvc
      processor=ARM64
    fi

    cmake_args+=(
      -DCMAKE_SYSTEM_NAME=Windows
      -DCMAKE_SYSTEM_PROCESSOR="$processor"
      -DCMAKE_C_COMPILER=clang-cl
      -DCMAKE_CXX_COMPILER=clang-cl
      -DCMAKE_C_COMPILER_TARGET="$triple"
      -DCMAKE_CXX_COMPILER_TARGET="$triple"
      -DCMAKE_NM="$(cygpath -m "$(command -v llvm-nm)")"
      -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
    )
    jxl_args+=(
      -DJPEGXL_ENABLE_HWY_AVX3=ON
      -DJPEGXL_ENABLE_HWY_AVX3_SPR=ON
      -DJPEGXL_ENABLE_HWY_AVX3_ZEN4=ON
    )
    ;;

  *)
    echo "Unknown libjxl target '$target'." >&2
    exit 2
    ;;
esac

build_jobs="${LIBJXL_BUILD_JOBS:-${FFMPEG_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}}"

"${configure[@]}" "${cmake_args[@]}" -S "$lcms_dir" -B "$build_dir/lcms2" \
  -DLCMS2_BUILD_SHARED=OFF -DLCMS2_BUILD_STATIC=ON \
  -DLCMS2_BUILD_TOOLS=OFF -DLCMS2_BUILD_TESTS=OFF \
  "-DLCMS2_WITH_THREADS=$lcms_threads"
cmake --build "$build_dir/lcms2" --parallel "$build_jobs"
cmake --install "$build_dir/lcms2"
lcms_archive="$prefix/lib/liblcms2.a"
if [[ "$target" == win-* ]]; then
  lcms_archive="$prefix/lib/lcms2.lib"
fi
"${configure[@]}" "${cmake_args[@]}" "${jxl_args[@]}" \
  -S "$libjxl_dir" -B "$build_dir" \
  "-DLCMS2_INCLUDE_DIR=$prefix/include" "-DLCMS2_LIBRARY=$lcms_archive"
cmake --build "$build_dir" --parallel "$build_jobs"
cmake --install "$build_dir"

nm_tool="$(sed -n 's/^CMAKE_NM:[^=]*=//p' "$build_dir/CMakeCache.txt")"
if [[ "$target" == browser-wasm-* ]]; then
  nm_tool="$(command -v emnm)"
fi
if [[ ! -x "$nm_tool" ]]; then
  echo "CMake did not select an executable nm tool: '$nm_tool'." >&2
  exit 1
fi
shopt -s nullglob
installed_archives=("$prefix/lib"/*.a "$prefix/lib"/*.lib)
shopt -u nullglob
if [[ ${#installed_archives[@]} -eq 0 ]]; then
  echo "No installed libjxl archives found in '$prefix/lib'." >&2
  exit 1
fi
"$nm_tool" -g "${installed_archives[@]}" > "$build_dir/installed-symbols.txt"
awk -v target="$target" '
  NF >= 2 {
    symbol = $NF;
    if (target == "osx-arm64" || target == "ios-arm64" || target == "iossimulator-arm64") sub(/^_/, "", symbol);
    if (index(symbol, "skcms_") || symbol == "powf_") {
      print "Unexpected skcms definition or reference in LCMS build: " symbol;
      failed = 1;
    }
  }
  END { exit failed }' "$build_dir/installed-symbols.txt"

pkg_config_files=(
  "$prefix/lib/pkgconfig/libjxl.pc"
  "$prefix/lib/pkgconfig/libjxl_cms.pc"
  "$prefix/lib/pkgconfig/libjxl_threads.pc"
  "$prefix/lib/pkgconfig/libhwy.pc"
  "$prefix/lib/pkgconfig/libbrotlicommon.pc"
  "$prefix/lib/pkgconfig/libbrotlidec.pc"
  "$prefix/lib/pkgconfig/libbrotlienc.pc"
)

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
  win-*) cxx_runtime_libs="-llibcpmt" ;;
  *) cxx_runtime_libs="-lc++" ;;
esac

for pkg_config_file in "${pkg_config_files[@]}"; do
  sed -i.bak -E "s/-l(c\\+\\+|stdc\\+\\+)( |\$)/$cxx_runtime_libs\\2/g" "$pkg_config_file"
  rm -f -- "$pkg_config_file.bak"
  if [[ "$target" == win-* ]]; then
    sed -i.bak -E "s/-ljxl-static( |\$)/-ljxl\\1/g; s/ -lm( |\$)/\\1/g; s/^Libs\\.private:.*/& $cxx_runtime_libs/" "$pkg_config_file"
    rm -f -- "$pkg_config_file.bak"
  fi
done

# libjxl_threads.pc only lists '-lm' even though the runner is std::thread based.
threads_pkg_config_file="$prefix/lib/pkgconfig/libjxl_threads.pc"
sed -i.bak -E "s/^Libs\\.private:.*/& $cxx_runtime_libs/" "$threads_pkg_config_file"
rm -f -- "$threads_pkg_config_file.bak"

printf "Built libjxl %s for '%s' in %s\n" \
  "$(sed -n 's/^Version: *//p' "$prefix/lib/pkgconfig/libjxl.pc")" "$target" "$prefix"

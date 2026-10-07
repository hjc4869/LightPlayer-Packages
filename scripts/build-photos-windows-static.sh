#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"
case "$target" in
  win-x64) triple=x86_64-pc-windows-msvc; processor=AMD64; vc_arch=x64 ;;
  win-arm64) triple=aarch64-pc-windows-msvc; processor=ARM64; vc_arch=arm64 ;;
  *) echo 'Usage: build-photos-windows-static.sh <win-x64|win-arm64>' >&2; exit 2 ;;
esac

if [[ "${VSCMD_ARG_TGT_ARCH:-}" != "$vc_arch" ]]; then
  echo "Run in MSYS2 with the Visual Studio '$vc_arch' target environment inherited." >&2
  exit 1
fi

build_root="$repo_root/artifacts/build/photos-$target-static"
prefix="$build_root/install"
output="$repo_root/artifacts/photos-$target-static"
build_jobs="${PHOTOS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

rm -rf -- "$build_root" "$output"
mkdir -p "$prefix" "$output"

# Match FFmpeg's Windows MSVC ABI and static CRT, not the MinGW DLL objects.
cmake_args=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR="$processor"
  -DCMAKE_C_COMPILER=clang-cl -DCMAKE_C_COMPILER_TARGET="$triple"
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
  -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$prefix")"
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR=include
)

for library in libjpeg-turbo zlib lcms2; do
  source_dir="$build_root/$library-source"
  build_dir="$build_root/$library-build"
  mkdir -p "$source_dir"
  git -C "$repo_root/$library" archive HEAD | tar -x -C "$source_dir"
  case "$library" in
    libjpeg-turbo)
      library_args=(-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_JPEG8=ON
        -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF -DWITH_SIMD=OFF
        -DWITH_CRT_DLL=OFF)
      ;;
    zlib)
      library_args=(-DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON -DZLIB_BUILD_TESTING=OFF)
      ;;
    lcms2)
      library_args=(-DLCMS2_BUILD_SHARED=OFF -DLCMS2_BUILD_STATIC=ON
        -DLCMS2_BUILD_TOOLS=OFF -DLCMS2_BUILD_TESTS=OFF -DLCMS2_WITH_THREADS=OFF
        -DLCMS2_WITH_FASTFLOAT=OFF -DLCMS2_WITH_THREADED_PLUGIN=OFF)
      ;;
  esac
  MSYS2_ARG_CONV_EXCL='*' cmake -S "$(cygpath -m "$source_dir")" \
    -B "$(cygpath -m "$build_dir")" "${cmake_args[@]}" "${library_args[@]}"
  cmake --build "$(cygpath -m "$build_dir")" --parallel "$build_jobs"
  cmake --install "$(cygpath -m "$build_dir")"
  if [[ "$library" == libjpeg-turbo ]]; then
    jpeg_namespace="$build_root/jpeg-namespace.h"
    llvm-nm --extern-only --defined-only --just-symbol-name "$prefix/lib/jpeg-static.lib" |
      awk '/^[A-Za-z_][A-Za-z0-9_]*$/' | LC_ALL=C sort -u |
      awk '{ printf "#define %s lightstudio_photos_%s\n", $1, $1 }' > "$jpeg_namespace"
    MSYS2_ARG_CONV_EXCL='*' cmake -S "$(cygpath -m "$source_dir")" \
      -B "$(cygpath -m "$build_dir")" "-DCMAKE_C_FLAGS=/FI\"$(cygpath -m "$jpeg_namespace")\""
    cmake --build "$(cygpath -m "$build_dir")" --clean-first --parallel "$build_jobs"
    cmake --install "$(cygpath -m "$build_dir")"
  fi
done

# Use LibRaw's upstream MSVC static target in a disposable source tree.
# LIBRAW_NODLL is supplied by that target; do not define CMS_DLL for static LCMS.
source_dir="$build_root/libraw-source"
mkdir -p "$source_dir"
git -C "$repo_root/libraw" archive HEAD | tar -x -C "$source_dir"
pushd "$source_dir" >/dev/null
MSYS2_ARG_CONV_EXCL='*' nmake -nologo -f Makefile.msvc 'lib\libraw_static.lib' \
  "CC=clang-cl --target=$triple" \
  "COPT=/nologo /O2 /MT /EHsc /I. /I\"$(cygpath -m "$prefix/include")\" /FI\"$(cygpath -m "$jpeg_namespace")\" /DWIN32 /D_WIN32_WINNT=0x0A00 /D_CRT_SECURE_NO_WARNINGS /DLIBRAW_NOTHREADS /DUSE_LCMS2 /DUSE_JPEG /DUSE_ZLIB"
popd >/dev/null

cp "$source_dir/lib/libraw_static.lib" "$output/libraw.lib"
cp "$prefix/lib/lcms2.lib" "$output/liblcms2.lib"
cp "$prefix/lib/jpeg-static.lib" "$output/jpeg.lib"
cp "$prefix/lib/zs.lib" "$output/zlib.lib"

printf "Built Photos MSVC static libraries for '%s' in %s\n" "$target" "$output"
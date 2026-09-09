#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-linux-x64}"
build_root="$repo_root/artifacts/build/photos-$target"
prefix="$build_root/install"
output="$repo_root/artifacts/photos-$target"
build_jobs="${PHOTOS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

if [[ $# -gt 1 ]]; then
  echo 'Usage: build-photos.sh <linux-x64|linux-arm64|win-x64|win-arm64|android-arm64|android-x64|osx-arm64|osx-x64|browser-wasm|browser-wasm-mt>' >&2
  exit 2
fi

configure=(env)
compression_cmake=(cmake)
compression_args=(-DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_C_VISIBILITY_PRESET=hidden)
configure_args=(--enable-shared --disable-static)
thread_args=(--with-threads)
smoke_flags=()
raw_ldflags='-no-undefined -avoid-version'
export CC=gcc CXX=g++ AR=ar RANLIB=ranlib NM=nm STRIP=strip
export CFLAGS='-O2' CXXFLAGS='-O2' CPPFLAGS='' LDFLAGS=''

case "$target" in
  linux-x64)
    [[ "$(uname -sm)" == 'Linux x86_64' ]] || { echo 'linux-x64 requires x86_64 Linux.' >&2; exit 1; }
    command -v patchelf >/dev/null || { echo 'patchelf is required for Linux builds.' >&2; exit 1; }
    CFLAGS+=' -fPIC -march=x86-64 -mtune=generic'
    CXXFLAGS="$CFLAGS"
    ;;
  linux-arm64)
    [[ "$(uname -s)" == Linux ]] || { echo 'linux-arm64 requires Linux.' >&2; exit 1; }
    command -v patchelf >/dev/null || { echo 'patchelf is required for Linux builds.' >&2; exit 1; }
    CFLAGS+=' -fPIC -march=armv8-a'
    CXXFLAGS="$CFLAGS"
    if [[ "$(uname -m)" != aarch64 ]]; then
      CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++
      AR=aarch64-linux-gnu-ar RANLIB=aarch64-linux-gnu-ranlib
      NM=aarch64-linux-gnu-nm STRIP=aarch64-linux-gnu-strip
      configure_args+=(--host=aarch64-linux-gnu)
      compression_args+=(-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64)
      command -v qemu-aarch64 >/dev/null || { echo 'qemu-user is required to smoke-test the arm64 cross-build.' >&2; exit 1; }
    fi
    ;;
  win-x64)
    mingw_prefix="${MINGW_PREFIX:-x86_64-w64-mingw32-}"
    CC="${mingw_prefix}gcc-win32"
    CXX="${mingw_prefix}g++-win32"
    AR="${mingw_prefix}ar"
    RANLIB="${mingw_prefix}ranlib"
    NM="${mingw_prefix}nm"
    STRIP="${mingw_prefix}strip"
    configure_args+=(--host="${mingw_prefix%-}")
    compression_args+=(-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=x86_64)
    CPPFLAGS='-DCMS_DLL_BUILD -DLIBRAW_BUILDLIB -DLIBRAW_WIN32_DLLDEFS'
    LDFLAGS='-static-libstdc++ -static-libgcc'
    windows_link_flags=(-static-libstdc++ -static-libgcc)
    windows_smoke_flags=(-static-libgcc)
    thread_args=(--without-threads)
    ;;
  win-arm64)
    llvm_mingw_home="${LLVM_MINGW_HOME:-$repo_root/artifacts/toolchains/llvm-mingw-20260908-ucrt-ubuntu-22.04-x86_64}"
    mingw_prefix="$llvm_mingw_home/bin/aarch64-w64-mingw32-"
    CC="${mingw_prefix}clang" CXX="${mingw_prefix}clang++"
    AR="${mingw_prefix}ar" RANLIB="${mingw_prefix}ranlib"
    NM="${mingw_prefix}nm" STRIP="${mingw_prefix}strip"
    if [[ ! -x "$CC" ]]; then
      echo 'Run scripts/setup-photos-llvm-mingw.sh or set LLVM_MINGW_HOME to an LLVM-MinGW installation.' >&2
      exit 1
    fi
    configure_args+=(--host=aarch64-w64-mingw32)
    compression_args+=(-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=aarch64)
    CPPFLAGS='-DCMS_DLL_BUILD -DLIBRAW_BUILDLIB -DLIBRAW_WIN32_DLLDEFS -D_WIN32_WINNT=0x0a00'
    windows_link_flags=(-static)
    windows_smoke_flags=(-static)
    thread_args=(--without-threads)
    ;;
  android-arm64 | android-x64)
    android_ndk_home="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_ROOT:-/usr/lib/android-ndk}}}"
    android_api="${ANDROID_API_LEVEL:-21}"
    ndk_host=linux-x86_64
    [[ "$(uname -s)" != Darwin ]] || ndk_host=darwin-x86_64
    toolchain_bin="$android_ndk_home/toolchains/llvm/prebuilt/$ndk_host/bin"
    triple=aarch64-linux-android
    [[ "$target" != android-x64 ]] || triple=x86_64-linux-android
    CC="$toolchain_bin/${triple}${android_api}-clang"
    CXX="$toolchain_bin/${triple}${android_api}-clang++"
    AR="$toolchain_bin/llvm-ar"
    RANLIB="$toolchain_bin/llvm-ranlib"
    NM="$toolchain_bin/llvm-nm"
    STRIP="$toolchain_bin/llvm-strip"
    CFLAGS+=' -fPIC'
    CXXFLAGS="$CFLAGS"
    LDFLAGS='-Wl,-z,max-page-size=16384'
    configure_args+=(--host="$triple")
    android_abi=arm64-v8a
    [[ "$target" != android-x64 ]] || android_abi=x86_64
    compression_args+=("-DCMAKE_TOOLCHAIN_FILE=$android_ndk_home/build/cmake/android.toolchain.cmake"
      "-DANDROID_ABI=$android_abi" "-DANDROID_PLATFORM=android-$android_api")
    output="$repo_root/artifacts/photos-android/$target"
    ;;
  osx-arm64 | osx-x64)
    [[ "$(uname -s)" == Darwin ]] || { echo 'macOS targets require Xcode on macOS.' >&2; exit 1; }
    export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
    architecture=arm64
    host=aarch64-apple-darwin
    if [[ "$target" == osx-x64 ]]; then
      architecture=x86_64
      host=x86_64-apple-darwin
    fi
    CC=clang CXX=clang++
    CFLAGS+=" -arch $architecture -isysroot $(xcrun --sdk macosx --show-sdk-path) -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="$CFLAGS"
    configure_args=(--enable-shared --enable-static --host="$host")
    compression_args+=("-DCMAKE_OSX_ARCHITECTURES=$architecture"
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET")
    smoke_flags=(-arch "$architecture" "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET")
    ;;
  browser-wasm | browser-wasm-mt)
    configure=(emconfigure)
    compression_cmake=(emcmake cmake)
    CC=emcc CXX=em++ AR=emar RANLIB=emranlib NM=emnm STRIP=emstrip
    configure_args=(--disable-shared --enable-static --host=wasm32-unknown-emscripten)
    CXXFLAGS+=' -fwasm-exceptions'
    smoke_flags=(-fwasm-exceptions -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1 -sENVIRONMENT=node)
    if [[ "$target" == browser-wasm-mt ]]; then
      CFLAGS+=' -pthread'
      CXXFLAGS+=' -pthread'
      LDFLAGS='-pthread'
      smoke_flags+=(-pthread -sPTHREAD_POOL_SIZE=1)
    else
      CPPFLAGS='-DLIBRAW_NOTHREADS'
      thread_args=(--without-threads)
    fi
    ;;
  *)
    echo "Unknown Photos target: $target" >&2
    exit 2
    ;;
esac

for tool in git tar autoreconf automake make pkg-config cmake "$CC" "$CXX" "$AR" "$RANLIB"; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done

for library in libraw lcms2; do
  if [[ ! -f "$repo_root/$library/configure.ac" ]]; then
    echo "Run 'git submodule update --init libraw lcms2' first." >&2
    exit 1
  fi
done

rm -rf -- "$build_root" "$output"
mkdir -p "$prefix" "$output"

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
export EM_PKG_CONFIG_PATH="$PKG_CONFIG_PATH"

for library in libjpeg-turbo zlib; do
  source_dir="$build_root/$library-source"
  build_dir="$build_root/$library-build"
  if [[ ! -f "$repo_root/$library/CMakeLists.txt" ]]; then
    echo "Run 'git submodule update --init libjpeg-turbo zlib' first." >&2
    exit 1
  fi
  mkdir -p "$source_dir"
  git -C "$repo_root/$library" archive HEAD | tar -x -C "$source_dir"
  if [[ "$library" == libjpeg-turbo ]]; then
    library_args=(-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_JPEG8=ON
      -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF -DWITH_SIMD=OFF)
  else
    library_args=(-DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON -DZLIB_BUILD_TESTING=OFF)
  fi
  "${compression_cmake[@]}" -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR=include \
    "-DCMAKE_C_COMPILER=$CC" "-DCMAKE_AR=$(command -v "$AR")" \
    "-DCMAKE_RANLIB=$(command -v "$RANLIB")" \
    "${compression_args[@]}" "${library_args[@]}"
  cmake --build "$build_dir" --parallel "$build_jobs"
  cmake --install "$build_dir"
  if [[ "$library" == libjpeg-turbo && "$target" == browser-wasm* ]]; then
    jpeg_symbols="$build_root/jpeg-symbols.txt"
    jpeg_namespace="$build_root/jpeg-namespace.h"
    "$NM" --extern-only --defined-only --just-symbol-name "$prefix/lib/libjpeg.a" |
      awk '/^[A-Za-z_][A-Za-z0-9_]*$/' | LC_ALL=C sort -u > "$jpeg_symbols"
    awk '/^[A-Za-z_][A-Za-z0-9_]*$/ { printf "#define %s lightstudio_photos_%s\n", $1, $1 }' \
      "$jpeg_symbols" > "$jpeg_namespace"
    grep -q '^#define jpeg_CreateDecompress ' "$jpeg_namespace"
    "${compression_cmake[@]}" -S "$source_dir" -B "$build_dir" \
      "-DCMAKE_C_FLAGS=$CFLAGS -include $jpeg_namespace"
    cmake --build "$build_dir" --parallel "$build_jobs"
    cmake --install "$build_dir"
  fi
done
if [[ "$target" == win-* ]]; then
  cp "$prefix/lib/libzs.a" "$prefix/lib/libz.a"
fi
for library in libjpeg libz; do
  test -f "$prefix/lib/$library.a"
done
CPPFLAGS+=" -I$prefix/include"
LDFLAGS+=" -L$prefix/lib"

for library in lcms2 libraw; do
  source_dir="$build_root/$library-source"
  build_dir="$build_root/$library-build"
  mkdir -p "$source_dir" "$build_dir"
  git -C "$repo_root/$library" archive HEAD | tar -x -C "$source_dir"
  pushd "$source_dir" >/dev/null
  autoreconf -fi
  popd >/dev/null
  pushd "$build_dir" >/dev/null
  if [[ "$library" == lcms2 ]]; then
    "${configure[@]}" "$source_dir/configure" --prefix="$prefix" --libdir="$prefix/lib" \
      "${configure_args[@]}" "${thread_args[@]}" --without-jpeg --without-tiff --without-zlib
    make -C src -j"$build_jobs" liblcms2_la_LDFLAGS='-no-undefined -avoid-version'
    make -C src install liblcms2_la_LDFLAGS='-no-undefined -avoid-version'
    make -C include install
    make install-pkgconfigDATA
  else
    if [[ "$target" == win-* || "$target" == android-* ]]; then
      configure_args+=(--disable-shared --enable-static)
    fi
    if [[ "$target" == browser-wasm* ]]; then
      CPPFLAGS+=" -include $jpeg_namespace"
    fi
    "${configure[@]}" "$source_dir/configure" --prefix="$prefix" --libdir="$prefix/lib" \
      "${configure_args[@]}" --disable-examples --disable-openmp \
      --enable-jpeg --enable-zlib --enable-lcms
    for feature in USE_LCMS2 USE_JPEG USE_ZLIB; do
      grep -q -- "-D$feature" Makefile || { echo "LibRaw did not enable $feature" >&2; exit 1; }
    done
    make -j"$build_jobs" lib/libraw.la "lib_libraw_la_LDFLAGS=$raw_ldflags"
    make install-libLTLIBRARIES install-nobase_includeHEADERS \
      lib_LTLIBRARIES=lib/libraw.la "lib_libraw_la_LDFLAGS=$raw_ldflags"
  fi
  popd >/dev/null
done

case "$target" in
  linux-x64 | linux-arm64)
    cp "$prefix/lib/libraw.so" "$prefix/lib/liblcms2.so" "$output/"
    patchelf --set-rpath "\$ORIGIN" "$output/libraw.so"
    for library in "$output"/*.so; do
      dependencies="$(readelf -d "$library")"
      if grep -Eq 'NEEDED.*(libgomp|libjpeg|libz\.so)' <<<"$dependencies"; then
        echo "Unexpected external dependency in $library" >&2
        exit 1
      fi
    done
    "$CC" "$repo_root/tests/photos/smoke.c" -L"$output" \
      -Wl,-rpath,"$output" -lraw -llcms2 -o "$build_root/smoke"
    if [[ "$target" == linux-arm64 && "$(uname -m)" != aarch64 ]]; then
      qemu-aarch64 -L /usr/aarch64-linux-gnu "$build_root/smoke"
    else
      env -u LD_LIBRARY_PATH "$build_root/smoke"
    fi
    ;;
  android-arm64 | android-x64)
    "$CXX" -shared -static-libstdc++ -Wl,-z,max-page-size=16384 \
      -Wl,-soname,libraw.so -Wl,--whole-archive "$prefix/lib/libraw.a" \
      -Wl,--no-whole-archive "$prefix/lib/libjpeg.a" "$prefix/lib/libz.a" \
      -L"$prefix/lib" -llcms2 -lm -o "$prefix/lib/libraw.so"
    cp "$prefix/lib/libraw.so" "$prefix/lib/liblcms2.so" "$output/"
    mkdir -p "$output/licenses"
    cp "$android_ndk_home/NOTICE.toolchain" "$output/licenses/"
    for library in "$output"/*.so; do
      dependencies="$("$toolchain_bin/llvm-readelf" -d "$library")"
      if grep -Eq 'NEEDED.*(libc\+\+_shared|libomp|libjpeg|libz\.so)' <<<"$dependencies"; then
        echo "Unexpected Android runtime dependency in $library" >&2
        exit 1
      fi
    done
    "$CC" "$repo_root/tests/photos/smoke.c" -L"$output" -lraw -llcms2 -o "$build_root/smoke"
    ;;
  win-x64 | win-arm64)
    "$CXX" -shared "${windows_link_flags[@]}" \
      -Wl,--whole-archive "$prefix/lib/libraw.a" -Wl,--no-whole-archive \
      "$prefix/lib/libjpeg.a" "$prefix/lib/libz.a" \
      "$prefix/lib/liblcms2.dll.a" -lws2_32 \
      -Wl,--out-implib,"$prefix/lib/libraw.dll.a" -o "$prefix/bin/libraw.dll"
    cp "$prefix/bin/libraw.dll" "$prefix/bin/liblcms2.dll" "$output/"
    mkdir -p "$output/licenses"
    if [[ "$target" == win-arm64 ]]; then
      cp "$llvm_mingw_home/LICENSE.TXT" "$output/licenses/LLVM-MinGW-LICENSE.txt"
      cp "$llvm_mingw_home/aarch64-w64-mingw32/share/mingw32/COPYING.MinGW-w64.txt" \
        "$llvm_mingw_home/aarch64-w64-mingw32/share/mingw32/COPYING.MinGW-w64-runtime.txt" \
        "$output/licenses/"
    else
      cp /usr/share/doc/gcc-mingw-w64-base/copyright "$output/licenses/GCC-copyright.txt"
      cp /usr/share/doc/mingw-w64-common/copyright "$output/licenses/MinGW-copyright.txt"
      cp /usr/share/common-licenses/GPL-3 "$output/licenses/GPL-3.txt"
    fi
    for library in "$output"/*.dll; do
      dependencies="$("${mingw_prefix}objdump" -p "$library")"
      if grep -Ei 'DLL Name:.*(libgcc|libstdc\+\+|libc\+\+|libunwind|libwinpthread|libssp|libgomp|jpeg|zlib|libz\.)' <<<"$dependencies"; then
        echo "Unexpected compiler runtime DLL dependency in $library" >&2
        exit 1
      fi
    done
    "$CC" "$repo_root/tests/photos/smoke.c" "${windows_smoke_flags[@]}" \
      "$prefix/lib/libraw.dll.a" "$prefix/lib/liblcms2.dll.a" -o "$output/photos-smoke.exe"
    if [[ "$target" == win-arm64 ]]; then
      for binary in "$output"/*.dll "$output/photos-smoke.exe"; do
        headers="$("$llvm_mingw_home/bin/llvm-readobj" --file-headers --coff-imports "$binary")"
        grep -Fq 'Machine: IMAGE_FILE_MACHINE_ARM64' <<<"$headers" || {
          echo "Not a native Windows ARM64 binary: $binary" >&2
          exit 1
        }
        if grep -Ei 'Name:.*(libc\+\+|libunwind|libwinpthread|libssp|jpeg|zlib)' <<<"$headers"; then
          echo "Unexpected Windows ARM64 dependency in $binary" >&2
          exit 1
        fi
      done
    fi
    ;;
  osx-arm64 | osx-x64)
    cp "$prefix/lib/libraw.dylib" "$prefix/lib/liblcms2.dylib" \
      "$prefix/lib/libraw.a" "$prefix/lib/liblcms2.a" \
      "$prefix/lib/libjpeg.a" "$prefix/lib/libz.a" "$output/"
    install_name_tool -id @rpath/libraw.dylib "$output/libraw.dylib"
    install_name_tool -id @rpath/liblcms2.dylib "$output/liblcms2.dylib"
    install_name_tool -change "$prefix/lib/liblcms2.dylib" \
      @loader_path/liblcms2.dylib "$output/libraw.dylib"
    codesign --force --sign - "$output/libraw.dylib" "$output/liblcms2.dylib"
    dependencies="$(otool -L "$output/libraw.dylib")"
    if grep -Eq 'libjpeg|libz[.0-9]*\.dylib' <<<"$dependencies"; then
      echo 'macOS LibRaw must embed JPEG and zlib.' >&2
      exit 1
    fi
    "$CC" "${smoke_flags[@]}" "$repo_root/tests/photos/smoke.c" \
      -L"$output" -Wl,-rpath,"$output" -lraw -llcms2 -o "$build_root/smoke"
    "$build_root/smoke"
    "$CC" "${smoke_flags[@]}" "$repo_root/tests/photos/smoke.c" \
      "$output/libraw.a" "$output/liblcms2.a" "$output/libjpeg.a" "$output/libz.a" \
      -lc++ -o "$build_root/smoke-static"
    "$build_root/smoke-static"
    ;;
  browser-wasm | browser-wasm-mt)
    cp "$prefix/lib/libraw.a" "$prefix/lib/liblcms2.a" "$prefix/lib/libz.a" "$output/"
    "$AR" qL "$output/libraw.a" "$prefix/lib/libjpeg.a"
    "$RANLIB" "$output/libraw.a"
    jpeg_conflicts="$(LC_ALL=C comm -12 "$jpeg_symbols" \
      <("$NM" --extern-only --just-symbol-name "$output/libraw.a" | LC_ALL=C sort -u))"
    if [[ -n "$jpeg_conflicts" ]]; then
      printf 'LibRaw exposes or imports unprefixed JPEG symbols:\n%s\n' "$jpeg_conflicts" >&2
      exit 1
    fi
    "$CC" "${smoke_flags[@]}" -c "$repo_root/tests/photos/smoke.c" -o "$build_root/smoke.o"
    "$CXX" "${smoke_flags[@]}" "$build_root/smoke.o" \
      "$output/libraw.a" "$output/liblcms2.a" "$output/libz.a" \
      -o "$build_root/smoke.js"
    node "$build_root/smoke.js"
    ;;
esac
printf "Built Photos libraries for '%s' in %s\n" "$target" "$output"
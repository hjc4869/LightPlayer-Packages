#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?Usage: build-webgpu.sh <linux-x64|linux-arm64|android-arm64|android-x64>}"
BUILD_DIR="${WEBGPU_BUILD_DIR:-$ROOT_DIR/artifacts/build/webgpu-$TARGET}"
PREFIX="$ROOT_DIR/artifacts/webgpu-$TARGET"
PROFILE="$ROOT_DIR/scripts/webgpu-native-bindings.py"
PYTHON="${PYTHON:-python3}"
DAWN_TAG="$("$PYTHON" "$PROFILE" version --field DawnTag)"
DAWN_SHA1="$("$PYTHON" "$PROFILE" version --field DawnArchiveSha1)"

cmake_args=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DBUILD_SHARED_LIBS=OFF
  "-DLIGHTSTUDIO_DAWN_TAG=$DAWN_TAG" "-DLIGHTSTUDIO_DAWN_ARCHIVE_SHA1=$DAWN_SHA1"
  -DDAWN_BUILD_MONOLITHIC_LIBRARY=SHARED -DDAWN_ENABLE_INSTALL=ON
  -DDAWN_FETCH_DEPENDENCIES=ON -DDAWN_BUILD_SAMPLES=OFF -DDAWN_BUILD_TESTS=OFF
  -DDAWN_BUILD_PROTOBUF=OFF -DDAWN_SUPPORTS_CXX_MODULES=OFF
  -DDAWN_ENABLE_VULKAN=ON -DDAWN_ENABLE_NULL=OFF -DDAWN_ENABLE_DESKTOP_GL=OFF
  -DDAWN_ENABLE_OPENGLES=OFF -DDAWN_USE_X11=OFF -DDAWN_USE_WAYLAND=OFF
  -DDAWN_USE_GLFW=OFF -DDAWN_ENABLE_SPIRV_VALIDATION=OFF
  -DTINT_BUILD_TESTS=OFF -DTINT_BUILD_CMD_TOOLS=OFF -DTINT_BUILD_IR_BINARY=OFF
  -DTINT_BUILD_SPV_READER=OFF -DTINT_BUILD_WGSL_WRITER=ON -DTINT_BUILD_GLSL_VALIDATOR=OFF)
case "$TARGET" in
  linux-x64|linux-arm64)
    expected_arch=x86_64
    [[ "$TARGET" != linux-arm64 ]] || expected_arch=aarch64
    if [[ "$(uname -m)" != "$expected_arch" ]]; then
      printf 'Build %s on a native %s Linux host.\n' "$TARGET" "$expected_arch" >&2
      exit 1
    fi
    cmake_args+=("-DCMAKE_C_COMPILER=${CC:-clang}" "-DCMAKE_CXX_COMPILER=${CXX:-clang++}"
      '-DCMAKE_SHARED_LINKER_FLAGS=-static-libstdc++ -static-libgcc -Wl,--exclude-libs,libstdc++.a:libgcc.a:libgcc_eh.a')
    sysroot_kind=linux-glibc
    sysroot_version="$(getconf GNU_LIBC_VERSION)"
    ;;
  android-arm64|android-x64)
    android_abi=arm64-v8a
    [[ "$TARGET" != android-x64 ]] || android_abi=x86_64
    android_ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-/usr/lib/android-ndk}}"
    cmake_args+=("-DCMAKE_TOOLCHAIN_FILE=$android_ndk/build/cmake/android.toolchain.cmake"
      "-DANDROID_ABI=$android_abi" "-DANDROID_PLATFORM=android-${ANDROID_API:-27}"
      -DANDROID_STL=c++_static
      '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,--exclude-libs,libc++_static.a:libc++abi.a:libunwind.a')
    sysroot_kind=android-ndk
    sysroot_version="$(awk -F '= *' '/^Pkg.Revision/ {print $2}' "$android_ndk/source.properties"); API ${ANDROID_API:-27}"
    ;;
  *)
    printf 'Unsupported WebGPU target: %s\n' "$TARGET" >&2
    exit 1
    ;;
esac

cmake -S "$ROOT_DIR/scripts/webgpu" -B "$BUILD_DIR" -G Ninja "${cmake_args[@]}"
cmake --build "$BUILD_DIR" --target webgpu_dawn dawn_proc --parallel "${JOBS:-8}"
mkdir -p "$PREFIX/licenses/dawn" "$PREFIX/licenses/toolchain"
dawn_library="$(find "$BUILD_DIR/_deps/dawn-build" -type f -name libwebgpu_dawn.so -print -quit)"
if [[ -z "$dawn_library" ]]; then
  printf 'Missing shared Dawn library in %s\n' "$BUILD_DIR" >&2
  exit 1
fi
cp -L "$dawn_library" "$PREFIX/libwebgpu_dawn.so"
cp "$BUILD_DIR/_deps/dawn-src/LICENSE" "$PREFIX/licenses/dawn/"
while IFS= read -r -d '' license_file; do
  relative_path="${license_file#"$BUILD_DIR/_deps/dawn-src/"}"
  destination="$PREFIX/licenses/dependencies/$relative_path"
  mkdir -p "$(dirname "$destination")"
  cp "$license_file" "$destination"
done < <(find "$BUILD_DIR/_deps/dawn-src/third_party" -type f \
  \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'LICENSE-*' -o -iname 'COPYING*' -o -iname 'NOTICE*' -o -iname 'COPYRIGHT*' \) \
  ! -path '*/.git/*' -print0)
if [[ "$TARGET" == linux-* ]]; then
  gcc_license="$(find /usr/share/doc -path '*/gcc-*/copyright' -type f -print -quit)"
  cp "$gcc_license" "$PREFIX/licenses/toolchain/GCC-copyright.txt"
  cp /usr/share/common-licenses/GPL-3 "$PREFIX/licenses/toolchain/GPL-3.txt"
else
  cp "$android_ndk/NOTICE" "$android_ndk/NOTICE.toolchain" "$PREFIX/licenses/toolchain/"
fi
"$PYTHON" "$PROFILE" stage "$PREFIX" "$BUILD_DIR" "$TARGET" \
  --sysroot-kind "$sysroot_kind" --sysroot-version "$sysroot_version"
printf 'Dawn %s\nArchive SHA1: %s\nRID: %s\nBackend: Vulkan\nABI/header provenance: native-bindings/profiles/%s/profile.json\n' \
  "$DAWN_TAG" "$DAWN_SHA1" "$TARGET" "$TARGET" > "$PREFIX/build-info.txt"
printf 'Built standalone Dawn %s: %s\n' "$DAWN_TAG" "$PREFIX"
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?Usage: build-webgpu.sh <linux-x64|linux-arm64|android-arm64|android-x64|osx-arm64|ios-arm64|iossimulator-arm64|win-x64|win-arm64>}"
BUILD_DIR="${WEBGPU_BUILD_DIR:-$ROOT_DIR/artifacts/build/webgpu-$TARGET}"
PREFIX="$ROOT_DIR/artifacts/webgpu-$TARGET"
PROFILE="$ROOT_DIR/scripts/webgpu-native-bindings.py"
PYTHON="${PYTHON:-python3}"
DAWN_CHROMIUM_VERSION="$("$PYTHON" "$PROFILE" version --field DawnChromiumVersion)"
DAWN_REVISION="$("$PYTHON" "$PROFILE" version --field DawnRevision)"

cmake_args=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DBUILD_SHARED_LIBS=OFF
  "-DLIGHTSTUDIO_DAWN_REVISION=$DAWN_REVISION"
  -DDAWN_BUILD_MONOLITHIC_LIBRARY=SHARED -DDAWN_ENABLE_INSTALL=ON
  -DDAWN_FETCH_DEPENDENCIES=ON -DDAWN_BUILD_SAMPLES=OFF -DDAWN_BUILD_TESTS=OFF
  -DDAWN_BUILD_PROTOBUF=OFF -DDAWN_SUPPORTS_CXX_MODULES=OFF
  -DDAWN_ENABLE_VULKAN=OFF -DDAWN_ENABLE_METAL=OFF -DDAWN_ENABLE_D3D11=OFF
  -DDAWN_ENABLE_D3D12=OFF -DDAWN_ENABLE_NULL=OFF -DDAWN_ENABLE_DESKTOP_GL=OFF
  -DDAWN_ENABLE_OPENGLES=OFF -DDAWN_USE_X11=OFF -DDAWN_USE_WAYLAND=OFF
  -DDAWN_USE_GLFW=OFF -DDAWN_ENABLE_SPIRV_VALIDATION=OFF
  -DTINT_BUILD_TESTS=OFF -DTINT_BUILD_CMD_TOOLS=OFF -DTINT_BUILD_IR_BINARY=OFF
  -DTINT_BUILD_SPV_READER=OFF -DTINT_BUILD_WGSL_WRITER=ON -DTINT_BUILD_GLSL_VALIDATOR=OFF)
library_name=libwebgpu_dawn.so
backend=Vulkan
case "$TARGET" in
  linux-x64|linux-arm64)
    expected_arch=x86_64
    [[ "$TARGET" != linux-arm64 ]] || expected_arch=aarch64
    if [[ "$(uname -m)" != "$expected_arch" ]]; then
      printf 'Build %s on a native %s Linux host.\n' "$TARGET" "$expected_arch" >&2
      exit 1
    fi
    cmake_args+=(-DDAWN_ENABLE_VULKAN=ON "-DCMAKE_C_COMPILER=${CC:-clang}" "-DCMAKE_CXX_COMPILER=${CXX:-clang++}"
      '-DCMAKE_SHARED_LINKER_FLAGS=-static-libstdc++ -static-libgcc -Wl,--exclude-libs,libstdc++.a:libgcc.a:libgcc_eh.a')
    sysroot_kind=linux-glibc
    sysroot_version="$(getconf GNU_LIBC_VERSION)"
    ;;
  android-arm64|android-x64)
    android_abi=arm64-v8a
    [[ "$TARGET" != android-x64 ]] || android_abi=x86_64
    android_ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-/usr/lib/android-ndk}}"
    cmake_args+=(-DDAWN_ENABLE_VULKAN=ON "-DCMAKE_TOOLCHAIN_FILE=$android_ndk/build/cmake/android.toolchain.cmake"
      "-DANDROID_ABI=$android_abi" "-DANDROID_PLATFORM=android-${ANDROID_API:-27}"
      -DANDROID_STL=c++_static
      '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,--exclude-libs,libc++_static.a:libc++abi.a:libunwind.a')
    sysroot_kind=android-ndk
    sysroot_version="$(awk -F '= *' '/^Pkg.Revision/ {print $2}' "$android_ndk/source.properties"); API ${ANDROID_API:-27}"
    ;;
  osx-arm64|ios-arm64|iossimulator-arm64)
    apple_sdk=macosx
    deployment_target="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
    library_name=libwebgpu_dawn.dylib
    if [[ "$TARGET" != osx-arm64 ]]; then
      apple_sdk=iphoneos
      [[ "$TARGET" != iossimulator-arm64 ]] || apple_sdk=iphonesimulator
      deployment_target="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"
      library_name=libwebgpu_dawn.a
      cmake_args+=(-DCMAKE_SYSTEM_NAME=iOS -DDAWN_BUILD_MONOLITHIC_LIBRARY=STATIC)
    fi
    cmake_args+=(-DDAWN_ENABLE_METAL=ON -DCMAKE_OSX_ARCHITECTURES=arm64
      "-DCMAKE_OSX_SYSROOT=$(xcrun --sdk "$apple_sdk" --show-sdk-path)"
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=$deployment_target" -DCMAKE_INSTALL_NAME_DIR=@rpath)
    backend=Metal
    sysroot_kind=apple-sdk
    sysroot_version="$apple_sdk $(xcrun --sdk "$apple_sdk" --show-sdk-version); deployment $deployment_target"
    ;;
  win-x64|win-arm64)
    windows_arch=x86_64
    [[ "$TARGET" != win-arm64 ]] || windows_arch=aarch64
    cmake_args+=(-DDAWN_ENABLE_D3D12=ON -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl
      "-DCMAKE_C_COMPILER_TARGET=$windows_arch-pc-windows-msvc"
      "-DCMAKE_CXX_COMPILER_TARGET=$windows_arch-pc-windows-msvc"
      -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DABSL_MSVC_STATIC_RUNTIME=ON -DDAWN_FORCE_SYSTEM_COMPONENT_LOAD=ON
      -DDAWN_USE_BUILT_DXC=OFF -DDAWN_USE_AGILITY_SDK=OFF)
    library_name=webgpu_dawn.dll
    backend=D3D12
    sysroot_kind=windows-sdk
    sysroot_version="${WindowsSDKVersion:?Initialize an MSVC developer environment before building WebGPU}"
    ;;
  *)
    printf 'Unsupported WebGPU target: %s\n' "$TARGET" >&2
    exit 1
    ;;
esac

cmake -S "$ROOT_DIR/scripts/webgpu" -B "$BUILD_DIR" -G Ninja "${cmake_args[@]}"
cmake --build "$BUILD_DIR" --target webgpu_dawn dawn_proc --parallel "${JOBS:-8}"
mkdir -p "$PREFIX/licenses/dawn" "$PREFIX/licenses/toolchain"
dawn_library="$(find "$BUILD_DIR/_deps/dawn-build" -type f -name "$library_name" -print -quit)"
if [[ -z "$dawn_library" ]]; then
  printf 'Missing Dawn library %s in %s\n' "$library_name" "$BUILD_DIR" >&2
  exit 1
fi
cp -L "$dawn_library" "$PREFIX/$library_name"
if [[ "$TARGET" == win-* ]]; then
  cp "$(find "$BUILD_DIR/_deps/dawn-build" -type f -name webgpu_dawn.lib -print -quit)" "$PREFIX/webgpu_dawn.lib"
fi
if [[ "$TARGET" == android-* ]]; then
  ndk_host=linux-x86_64
  [[ "$(uname -s)" != Darwin ]] || ndk_host=darwin-x86_64
  "$android_ndk/toolchains/llvm/prebuilt/$ndk_host/bin/llvm-strip" --strip-unneeded "$PREFIX/libwebgpu_dawn.so"
fi
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
elif [[ "$TARGET" == android-* ]]; then
  cp "$android_ndk/NOTICE" "$android_ndk/NOTICE.toolchain" "$PREFIX/licenses/toolchain/"
fi
"$PYTHON" "$PROFILE" stage "$PREFIX" "$BUILD_DIR" "$TARGET" \
  --sysroot-kind "$sysroot_kind" --sysroot-version "$sysroot_version"
printf 'Chromium %s\nDawn revision: %s\nRID: %s\nBackend: %s\nABI/header provenance: native-bindings/profiles/%s/profile.json\n' \
  "$DAWN_CHROMIUM_VERSION" "$DAWN_REVISION" "$TARGET" "$backend" "$TARGET" > "$PREFIX/build-info.txt"
printf 'Built standalone Dawn %s (Chromium %s): %s\n' "$DAWN_REVISION" "$DAWN_CHROMIUM_VERSION" "$PREFIX"
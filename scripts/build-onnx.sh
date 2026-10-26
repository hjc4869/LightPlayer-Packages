#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?Usage: build-onnx.sh <linux-x64|linux-arm64|android-arm64|android-x64|osx-x64|osx-arm64|ios-arm64|iossimulator-arm64>}"
ONNX_VERSION=1.30.0
ONNX_REVISION=f2c39fe2f838cf35ce7da92824f5a5e3ee6e88a7
SOURCE_DIR="${ONNX_SOURCE_DIR:-$ROOT_DIR/artifacts/build/onnxruntime-src}"
BUILD_DIR="${ONNX_BUILD_DIR:-$ROOT_DIR/artifacts/build/onnx-$TARGET}"
PREFIX="$ROOT_DIR/artifacts/onnx-$TARGET"

platform_args=(--build_shared_lib)
cmake_generator=Ninja
cmake_args=(CMAKE_POSITION_INDEPENDENT_CODE=ON onnxruntime_BUILD_UNIT_TESTS=OFF)
providers=CPU
native_name=libonnxruntime.so
case "$TARGET" in
  linux-x64|linux-arm64)
    providers+=', WebGPU'
    platform_args+=(--use_webgpu static_lib)
    expected_arch=x86_64
    [[ "$TARGET" != linux-arm64 ]] || expected_arch=aarch64
    if [[ "$(uname -m)" != "$expected_arch" ]]; then
      printf 'Build %s on a native %s Linux host.\n' "$TARGET" "$expected_arch" >&2
      exit 1
    fi
    cmake_args+=("CMAKE_C_COMPILER=${CC:-clang}" "CMAKE_CXX_COMPILER=${CXX:-clang++}"
      onnxruntime_BUILD_DAWN_SHARED_LIBRARY=ON
      "CMAKE_INSTALL_RPATH=\$ORIGIN" CMAKE_BUILD_WITH_INSTALL_RPATH=ON
      'CMAKE_SHARED_LINKER_FLAGS=-static-libstdc++ -static-libgcc -Wl,--exclude-libs,libstdc++.a:libgcc.a:libgcc_eh.a')
    ;;
  android-arm64|android-x64)
    providers+=', WebGPU'
    android_abi=arm64-v8a
    [[ "$TARGET" != android-x64 ]] || android_abi=x86_64
    android_ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-/usr/lib/android-ndk}}"
    android_sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}"
    platform_args+=(--android --android_abi "$android_abi" --android_api "${ANDROID_API:-27}"
      --android_ndk_path "$android_ndk" --android_sdk_path "$android_sdk"
      --use_webgpu static_lib)
    cmake_args+=(onnxruntime_BUILD_DAWN_SHARED_LIBRARY=ON ANDROID_STL=c++_static
      "CMAKE_INSTALL_RPATH=\$ORIGIN" CMAKE_BUILD_WITH_INSTALL_RPATH=ON
      'CMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,--exclude-libs,libc++_static.a:libc++abi.a:libunwind.a')
    ;;
  osx-arm64|osx-x64)
    providers+=', CoreML'
    native_name=libonnxruntime.dylib
    arch=arm64
    [[ "$TARGET" != osx-x64 ]] || arch=x86_64
    platform_args+=(--use_coreml --osx_arch "$arch" --apple_deploy_target "${MACOSX_DEPLOYMENT_TARGET:-15.0}")
    cmake_args+=('CMAKE_INSTALL_RPATH=@loader_path' CMAKE_BUILD_WITH_INSTALL_RPATH=ON)
    ;;
  ios-arm64|iossimulator-arm64)
    providers+=', CoreML'
    native_name=libonnxruntime.a
    cmake_generator=Xcode
    apple_sdk=iphoneos
    [[ "$TARGET" != iossimulator-arm64 ]] || apple_sdk=iphonesimulator
    platform_args=(--ios --use_coreml --osx_arch arm64 --apple_sysroot "$apple_sdk"
      --apple_deploy_target "${IPHONEOS_DEPLOYMENT_TARGET:-15.0}")
    cmake_args+=(onnxruntime_BUILD_SHARED_LIB=OFF BUILD_SHARED_LIBS=OFF
      CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO)
    ;;
  *)
    printf 'Unsupported ONNX target: %s\n' "$TARGET" >&2
    exit 1
    ;;
esac

if [[ ! -d "$SOURCE_DIR" ]]; then
  git clone --branch "v$ONNX_VERSION" --depth 1 --filter=blob:none \
    https://github.com/microsoft/onnxruntime.git "$SOURCE_DIR"
fi
if [[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" != "$ONNX_REVISION" ]]; then
  printf 'Expected ONNX Runtime commit %s in %s\n' "$ONNX_REVISION" "$SOURCE_DIR" >&2
  exit 1
fi

"${PYTHON:-python3}" "$SOURCE_DIR/tools/ci_build/build.py" \
  --build_dir "$BUILD_DIR" \
  --config Release --update --build --parallel "${JOBS:-8}" \
  --skip_tests --skip_submodule_sync --skip_pip_install \
  --cmake_generator "$cmake_generator" \
  --compile_no_warning_as_error --no_telemetry \
  "${platform_args[@]}" --cmake_extra_defines "${cmake_args[@]}"

mkdir -p "$PREFIX/licenses/onnxruntime"
if [[ "$TARGET" == ios-arm64 || "$TARGET" == iossimulator-arm64 ]]; then
  cmake --build "$BUILD_DIR/Release" --config Release --target re2 --parallel "${JOBS:-8}"
  archives=()
  while IFS= read -r -d '' archive; do
    archives+=("$archive")
  done < <(find "$BUILD_DIR/Release" -type f -name '*.a' -path "*/Release-$apple_sdk/*" -print0)
  xcrun --sdk "$apple_sdk" libtool -static -o "$PREFIX/$native_name" "${archives[@]}"
else
  cp -L "$BUILD_DIR/Release/$native_name" "$PREFIX/$native_name"
fi
if [[ "$TARGET" == linux-* || "$TARGET" == android-* ]]; then
  dawn_library="$(find "$BUILD_DIR/Release" -type f -name libwebgpu_dawn.so -print -quit)"
  if [[ -z "$dawn_library" ]]; then
    printf 'Missing shared Dawn library in %s\n' "$BUILD_DIR/Release" >&2
    exit 1
  fi
  cp -L "$dawn_library" "$PREFIX/libwebgpu_dawn.so"
fi
cp "$SOURCE_DIR/LICENSE" "$SOURCE_DIR/ThirdPartyNotices.txt" "$PREFIX/licenses/onnxruntime/"
while IFS= read -r -d '' license_file; do
  relative_path="${license_file#"$BUILD_DIR/Release/_deps/"}"
  destination="$PREFIX/licenses/dependencies/$relative_path"
  mkdir -p "$(dirname "$destination")"
  cp "$license_file" "$destination"
done < <(find "$BUILD_DIR/Release/_deps" -type f \
  \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'LICENSE-*' -o -iname 'COPYING*' -o -iname 'NOTICE*' -o -iname 'COPYRIGHT*' -o -iname 'ThirdPartyNotices.txt' \) \
  ! -path '*/.git/*' ! -name '*.orig' -print0)

case "$TARGET" in
  linux-*)
    mkdir -p "$PREFIX/licenses/toolchain"
    gcc_license="$(find /usr/share/doc -path '*/gcc-*/copyright' -type f -print -quit)"
    cp "$gcc_license" "$PREFIX/licenses/toolchain/GCC-copyright.txt"
    cp /usr/share/common-licenses/GPL-3 "$PREFIX/licenses/toolchain/GPL-3.txt"
    ;;
  android-*)
    mkdir -p "$PREFIX/licenses/toolchain"
    cp "$android_ndk/NOTICE" "$android_ndk/NOTICE.toolchain" "$PREFIX/licenses/toolchain/"
    ;;
  osx-*)
    install_name_tool -id "@rpath/$native_name" "$PREFIX/$native_name"
    codesign --force --sign - "$PREFIX/$native_name"
    ;;
esac
printf 'ONNX Runtime %s\nCommit: %s\nRID: %s\nExecution providers: %s\nTelemetry: disabled\n' \
  "$ONNX_VERSION" "$ONNX_REVISION" "$TARGET" "$providers" > "$PREFIX/build-info.txt"
if [[ "$TARGET" == linux-* || "$TARGET" == android-* ]]; then
  printf 'WebGPU: shared Dawn (libwebgpu_dawn.so)\n' >> "$PREFIX/build-info.txt"
fi
if [[ "$TARGET" == android-* ]]; then
  printf 'Android API: %s\nAndroid ABI: %s\n' "${ANDROID_API:-27}" "$android_abi" >> "$PREFIX/build-info.txt"
fi
printf 'Built %s with %s: %s\n' "$TARGET" "$providers" "$PREFIX"
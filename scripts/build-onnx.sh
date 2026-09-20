#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?Usage: build-onnx.sh <linux-x64|linux-arm64|osx-x64|osx-arm64>}"
ONNX_VERSION=1.30.0
ONNX_REVISION=f2c39fe2f838cf35ce7da92824f5a5e3ee6e88a7
SOURCE_DIR="${ONNX_SOURCE_DIR:-$ROOT_DIR/artifacts/build/onnxruntime-src}"
BUILD_DIR="${ONNX_BUILD_DIR:-$ROOT_DIR/artifacts/build/onnx-$TARGET}"
PREFIX="$ROOT_DIR/artifacts/onnx-$TARGET"

platform_args=(--build_shared_lib)
cmake_args=(CMAKE_POSITION_INDEPENDENT_CODE=ON onnxruntime_BUILD_UNIT_TESTS=OFF)
providers='CPU, WebGPU'
native_name=libonnxruntime.so
case "$TARGET" in
  linux-x64|linux-arm64)
    expected_arch=x86_64
    [[ "$TARGET" != linux-arm64 ]] || expected_arch=aarch64
    if [[ "$(uname -m)" != "$expected_arch" ]]; then
      printf 'Build %s on a native %s Linux host.\n' "$TARGET" "$expected_arch" >&2
      exit 1
    fi
    cmake_args+=("CMAKE_C_COMPILER=${CC:-clang}" "CMAKE_CXX_COMPILER=${CXX:-clang++}"
      'CMAKE_SHARED_LINKER_FLAGS=-static-libstdc++ -static-libgcc -Wl,--exclude-libs,libstdc++.a:libgcc.a:libgcc_eh.a')
    ;;
  osx-arm64|osx-x64)
    providers+=', CoreML'
    native_name=libonnxruntime.dylib
    arch=arm64
    [[ "$TARGET" != osx-x64 ]] || arch=x86_64
    platform_args+=(--use_coreml --osx_arch "$arch" --apple_deploy_target "${MACOSX_DEPLOYMENT_TARGET:-15.0}")
    cmake_args+=('CMAKE_INSTALL_RPATH=@loader_path' CMAKE_BUILD_WITH_INSTALL_RPATH=ON)
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
  --cmake_generator Ninja --use_webgpu static_lib \
  --compile_no_warning_as_error --no_telemetry \
  "${platform_args[@]}" --cmake_extra_defines "${cmake_args[@]}"

mkdir -p "$PREFIX/licenses/onnxruntime"
cp -L "$BUILD_DIR/Release/$native_name" "$PREFIX/$native_name"
cp "$SOURCE_DIR/onnxruntime/test/testdata/mul_1.onnx" "$PREFIX/smoke.onnx"
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
    dependencies="$(readelf -d "$PREFIX/$native_name")"
    if [[ "$dependencies" == *libstdc++* || "$dependencies" == *libgcc_s* || "$dependencies" == *libdawn* ]]; then
      printf 'Unexpected unbundled native dependency:\n%s\n' "$dependencies" >&2
      exit 1
    fi
    mkdir -p "$PREFIX/licenses/toolchain"
    gcc_license="$(find /usr/share/doc -path '*/gcc-*/copyright' -type f -print -quit)"
    [[ -n "$gcc_license" ]]
    cp "$gcc_license" "$PREFIX/licenses/toolchain/GCC-copyright.txt"
    cp /usr/share/common-licenses/GPL-3 "$PREFIX/licenses/toolchain/GPL-3.txt"
    ;;
  osx-*)
    install_name_tool -id "@rpath/$native_name" "$PREFIX/$native_name"
    codesign --force --sign - "$PREFIX/$native_name"
    ;;
esac
printf 'ONNX Runtime %s\nCommit: %s\nRID: %s\nExecution providers: %s\nWebGPU: embedded Dawn\nTelemetry: disabled\n' \
  "$ONNX_VERSION" "$ONNX_REVISION" "$TARGET" "$providers" > "$PREFIX/build-info.txt"
printf 'Built %s with %s (embedded Dawn/WebGPU): %s\n' "$TARGET" "$providers" "$PREFIX"
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

capture_build() {
  printf 'ARG:%s\n' "$@"
  exit 0
}

git() {
  [[ "$*" == "-C $ONNX_SOURCE_DIR rev-parse HEAD" ]] || return 1
  printf '%s\n' "${ONNX_REVISION:?}"
}

export -f capture_build git
export PYTHON=capture_build ONNX_SOURCE_DIR="$root"

check_case() {
  local label="$1" msvc_host="$2" process_arch="$3" native_arch="$4" rid="$5" expected="$6"
  local output
  output="$(VSCMD_ARG_HOST_ARCH="$msvc_host" PROCESSOR_ARCHITECTURE="$process_arch" \
    PROCESSOR_ARCHITEW6432="$native_arch" bash "$root/scripts/build-onnx.sh" "$rid")"
  if [[ "$expected" == native ]]; then
    [[ "$output" == *ARG:onnxruntime_CROSS_COMPILING=OFF* ]]
    [[ "$output" == *'Native Windows ARM64:'* ]]
  else
    [[ "$output" != *ARG:onnxruntime_CROSS_COMPILING=* ]]
  fi
  [[ "$output" == *'ARG:Visual Studio 17 2022'* ]]
  [[ "$output" == *ARG:onnxruntime_ENABLE_DAWN_BACKEND_D3D12=ON* ]]
  [[ "$output" == *ARG:onnxruntime_ENABLE_DAWN_BACKEND_VULKAN=OFF* ]]
  [[ "$output" == *ARG:--enable_msvc_static_runtime* ]]
  if [[ "$rid" == win-arm64 ]]; then
    [[ "$output" == *ARG:--arm64* ]]
  else
    [[ "$output" != *ARG:--arm64* ]]
  fi
  printf 'PASS: %s\n' "$label"
}

check_case 'MSVC ARM64 with missing process architecture' arm64 '' '' win-arm64 native
check_case 'MSVC ARM64 with AMD64 process architecture' arm64 AMD64 '' win-arm64 native
check_case 'case-insensitive MSVC host' ARM64 '' '' win-arm64 native
check_case 'native Windows fallback' '' ARM64 '' win-arm64 native
check_case 'emulated process native-OS fallback' '' AMD64 ARM64 win-arm64 native
check_case 'x64 MSVC cross compiler' x64 AMD64 '' win-arm64 cross
check_case 'x64 fallback cross compiler' '' AMD64 '' win-arm64 cross
check_case 'unknown host' '' '' '' win-arm64 cross
check_case 'win-x64 unchanged' arm64 ARM64 '' win-x64 cross
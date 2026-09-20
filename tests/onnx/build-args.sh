#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

git() {
  [[ "$*" == "-C $ONNX_SOURCE_DIR rev-parse HEAD" ]]
  printf '%s\n' f2c39fe2f838cf35ce7da92824f5a5e3ee6e88a7
}

uname() {
  [[ "$1" == -m ]]
  case "$ONNX_TEST_RID" in
    linux-arm64) printf 'aarch64\n' ;;
    *) printf 'x86_64\n' ;;
  esac
}

check_build_args() {
  local webgpu=0 coreml=0
  while (( $# > 0 )); do
    case "$1" in
      --use_webgpu)
        [[ "${2:-}" == static_lib ]]
        webgpu=1
        ;;
      --use_coreml) coreml=1 ;;
    esac
    shift
  done
  [[ "$webgpu" == 1 ]]
  case "$ONNX_TEST_RID" in
    osx-*) [[ "$coreml" == 1 ]] ;;
    linux-*) [[ "$coreml" == 0 ]] ;;
  esac
  printf 'PASS: %s provider build arguments, including static Dawn/WebGPU.\n' "$ONNX_TEST_RID"
  exit 0
}

export -f git uname check_build_args
for rid in linux-x64 linux-arm64 osx-x64 osx-arm64; do
  ONNX_TEST_RID="$rid" ONNX_SOURCE_DIR="$root" \
    PYTHON=check_build_args bash "$root/scripts/build-onnx.sh" "$rid"
done
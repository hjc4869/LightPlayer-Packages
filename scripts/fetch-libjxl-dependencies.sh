#!/usr/bin/env bash

# libjxl carries ten nested submodules, including a multi-gigabyte test corpus.
# Only these two are needed to build the decoder, so 'submodules: recursive'
# is deliberately avoided.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
libjxl_dir="$repo_root/libjxl"

if [[ ! -f "$libjxl_dir/CMakeLists.txt" ]]; then
  echo "libjxl is not initialized at '$libjxl_dir'. Run 'git submodule update --init'." >&2
  exit 1
fi

git -C "$libjxl_dir" submodule update --init --depth 1 -- \
  third_party/brotli \
  third_party/highway

git -C "$repo_root" submodule update --init --depth 1 -- lcms2

for dependency in brotli highway; do
  if [[ -z "$(ls -A "$libjxl_dir/third_party/$dependency" 2>/dev/null)" ]]; then
    echo "libjxl's '$dependency' submodule is still empty." >&2
    exit 1
  fi
done

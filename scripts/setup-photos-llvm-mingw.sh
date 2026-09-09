#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=20260908
archive_name="llvm-mingw-$version-ucrt-ubuntu-22.04-x86_64"
toolchains="$repo_root/artifacts/toolchains"
archive="$toolchains/$archive_name.tar.xz"
checksum=2258c745e3155870c80793f3e8c80b28fbde11b9ff73c4c78783635b3440b092

if [[ "$(uname -sm)" != 'Linux x86_64' ]]; then
  echo 'The pinned LLVM-MinGW toolchain requires x86_64 Linux (Ubuntu 22.04 or compatible).' >&2
  exit 1
fi

mkdir -p "$toolchains"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://github.com/mstorsjo/llvm-mingw/releases/download/$version/$archive_name.tar.xz" \
    --output "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
if [[ ! -x "$toolchains/$archive_name/bin/aarch64-w64-mingw32-clang" ]]; then
  tar -xJf "$archive" -C "$toolchains"
fi
"$toolchains/$archive_name/bin/aarch64-w64-mingw32-clang" --version
printf 'LLVM-MinGW installed at %s\n' "$toolchains/$archive_name"
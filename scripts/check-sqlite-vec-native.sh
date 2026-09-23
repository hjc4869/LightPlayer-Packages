#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rid="${1:?Usage: check-sqlite-vec-native.sh <rid> [artifact-directory]}"
prefix="${2:-${SQLITE_VEC_ARTIFACTS_DIR:-$root/artifacts}/sqlite-vec-$rid}"
native_name=vec0.so
case "$rid" in
  linux-x64|linux-arm64) ;;
  android-x64|android-arm64) native_name=libvec0.so ;;
  win-x64|win-arm64) native_name=vec0.dll ;;
  osx-x64|osx-arm64) native_name=vec0.dylib ;;
  browser-wasm|browser-wasm-mt) native_name=libvec0.a ;;
  *) printf 'Unsupported sqlite-vec RID: %s\n' "$rid" >&2; exit 1 ;;
esac
library="$prefix/$native_name"
test -s "$library"
test -s "$prefix/licenses/sqlite-vec/LICENSE-MIT"
grep -Fx "RID: $rid" "$prefix/build-info.txt"
if [[ "$rid" == browser-wasm* ]]; then
  grep -Fx 'SQLite linking: static calls to application-provided SQLite; no SQLite engine' "$prefix/build-info.txt"
else
  grep -Fx 'SQLite linking: extension API table only; no SQLite engine' "$prefix/build-info.txt"
fi

case "$rid" in
  browser-wasm|browser-wasm-mt)
    members="$(emar t "$library")"
    [[ "$members" == sqlite-vec.c.o ]]
    magic="$(emar p "$library" sqlite-vec.c.o | od -An -tx1 -w8 | sed -n '1p')"
    [[ "$magic" == ' 00 61 73 6d 01 00 00 00' ]]
    symbols="$("${LLVM_NM:-emnm}" --defined-only "$library")"
    grep -Eq '[[:space:]]sqlite3_vec_init$' <<< "$symbols"
    if grep -Eq '[[:space:]]sqlite3_(open|prepare|step|exec|close)' <<< "$symbols"; then
      printf 'SQLite engine symbols must not be embedded in vec0.\n' >&2
      exit 1
    fi
    threads=OFF
    [[ "$rid" != browser-wasm-mt ]] || threads=ON
    grep -Fx "WASM threads: $threads" "$prefix/build-info.txt"
    ;;
  linux-*|android-*)
    header="$(readelf -h "$library")"
    grep -Eq 'Class:[[:space:]]+ELF64' <<< "$header"
    machine='Advanced Micro Devices X86-64'
    [[ "$rid" != *-arm64 ]] || machine=AArch64
    grep -F "$machine" <<< "$header"
    dependencies="$(readelf -d "$library" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
    while IFS= read -r dependency; do
      case "$rid:$dependency" in
        linux-*:libc.so.6|linux-*:libm.so.6|linux-*:ld-linux-x86-64.so.2|linux-*:ld-linux-aarch64.so.1) ;;
        android-*:libc.so|android-*:libm.so|android-*:libdl.so) ;;
        *) printf 'Unexpected native dependency: %s\n' "$dependency" >&2; exit 1 ;;
      esac
    done <<< "$dependencies"
    symbols="$(nm -D --defined-only "$library")"
    grep -Eq '[[:space:]]sqlite3_vec_init$' <<< "$symbols"
    if grep -Eq '[[:space:]]sqlite3_(open|prepare|step|exec|close)' <<< "$symbols"; then
      printf 'SQLite engine symbols must not be embedded in vec0.\n' >&2
      exit 1
    fi
    if [[ "$rid" == android-* ]]; then
      test -s "$prefix/licenses/toolchain/NOTICE.toolchain"
      while IFS= read -r alignment; do
        if (( alignment < 0x4000 )); then
          printf 'Android LOAD alignment is below 16 KB: %s\n' "$alignment" >&2
          exit 1
        fi
      done < <(readelf -lW "$library" | awk '$1 == "LOAD" { print $NF }')
    else
      highest="$(readelf --version-info "$library" | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)*' | sort -Vu | tail -n 1)"
      if [[ "$(printf '%s\n' 2.39 "${highest#GLIBC_}" | sort -V | tail -n 1)" != 2.39 ]]; then
        printf 'Linux release requires %s, above the glibc 2.39 ceiling.\n' "$highest" >&2
        exit 1
      fi
      printf 'Maximum glibc requirement: %s\n' "$highest"
    fi
    ;;
  win-*)
    machine='8664 machine'
    [[ "$rid" != win-arm64 ]] || machine='AA64 machine'
    headers="$(dumpbin -nologo -headers "$library")"
    grep -Fi "$machine" <<< "$headers"
    exports="$(dumpbin -nologo -exports "$library")"
    grep -Eq '[[:space:]]sqlite3_vec_init[[:space:]]*$' <<< "$exports"
    if grep -Eq '[[:space:]]sqlite3_(open|prepare|step|exec|close)' <<< "$exports"; then
      printf 'SQLite engine symbols must not be embedded in vec0.\n' >&2
      exit 1
    fi
    dependencies="$(dumpbin -nologo -dependents "$library" | tr -d '\r' | awk 'NF == 1 && /\.[dD][lL][lL]$/ { print tolower($1) }')"
    if grep -Ei 'sqlite|vcruntime|msvcp|libgcc|libstdc\+\+' <<< "$dependencies"; then
      printf 'vec0 must not import SQLite or a separately deployed compiler runtime.\n' >&2
      exit 1
    fi
    ;;
  osx-*)
    arch=x86_64
    [[ "$rid" != osx-arm64 ]] || arch=arm64
    lipo "$library" -verify_arch "$arch"
    exports="$(nm -gU "$library")"
    grep -Eq '[[:space:]]_sqlite3_vec_init$' <<< "$exports"
    dependencies="$(otool -L "$library" | tail -n +2 | awk '{ print $1 }')"
    while IFS= read -r dependency; do
      case "$dependency" in
        @rpath/vec0.dylib|/usr/lib/libSystem.B.dylib) ;;
        *) printf 'Unexpected native dependency: %s\n' "$dependency" >&2; exit 1 ;;
      esac
    done <<< "$dependencies"
    codesign --verify "$library"
    ;;
esac
printf 'PASS: %s architecture, entry point, extension-only dependencies, and notices.\n' "$rid"
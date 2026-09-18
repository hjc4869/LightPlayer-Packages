#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rid="${1:?Usage: check-onnx-native.sh <rid>}"
prefix="$root/artifacts/onnx-$rid"

case "$rid" in
  linux-*|android-*)
    library="$prefix/libonnxruntime.so"
    readelf_tool="${READELF:-readelf}"
    header="$("$readelf_tool" -h "$library")"
    dependencies="$("$readelf_tool" -d "$library")"
    exports="$("$readelf_tool" --dyn-syms --wide "$library")"
    [[ "$exports" == *OrtGetApiBase* ]]
    case "$rid" in
      *-arm64) [[ "$header" == *AArch64* ]] ;;
      *-x64) [[ "$header" == *X86-64* || "$header" == *x86-64* ]] ;;
      *) exit 1 ;;
    esac
    if [[ "$dependencies" == *libstdc++* || "$dependencies" == *libgcc_s* ||
          "$dependencies" == *libc++_shared* || "$dependencies" == *libdawn* ||
          "$dependencies" == *libonnxruntime_providers* ]]; then
      printf 'Unbundled dependency for %s:\n%s\n' "$rid" "$dependencies" >&2
      exit 1
    fi
    if [[ "$rid" == android-* ]]; then
      segments="$("$readelf_tool" -lW "$library")"
      while read -r alignment; do
        (( alignment >= 16384 ))
      done < <(awk '/LOAD/ { print $NF }' <<< "$segments")
      [[ -s "$prefix/licenses/toolchain/NOTICE.toolchain" ]]
    else
      versions="$("$readelf_tool" --version-info "$library")"
      maximum="$(grep -oE 'GLIBC_[0-9.]+' <<< "$versions" | sort -Vu | tail -1)"
      maximum="${maximum#GLIBC_}"
      baseline="${ONNX_MAX_GLIBC:-2.39}"
      newest="$(printf '%s\n' "$maximum" "$baseline" | sort -V | tail -1)"
      if [[ "$newest" != "$baseline" ]]; then
        printf '%s requires glibc %s, newer than release baseline %s. Use the pinned Linux image.\n' "$rid" "$maximum" "$baseline" >&2
        exit 1
      fi
      printf '%s maximum GLIBC_%s (limit %s)\n' "$rid" "$maximum" "$baseline"
      [[ -s "$prefix/licenses/toolchain/GCC-copyright.txt" ]]
      [[ -s "$prefix/licenses/toolchain/GPL-3.txt" ]]
    fi
    printf '%s\n' "$dependencies" | grep NEEDED
    ;;
  osx-*)
    library="$prefix/libonnxruntime.dylib"
    arch=arm64
    [[ "$rid" != osx-x64 ]] || arch=x86_64
    lipo "$library" -verify_arch "$arch"
    dependencies="$(otool -L "$library")"
    while read -r dependency; do
      case "$dependency" in
        /usr/lib/*|/System/Library/*|@rpath/libonnxruntime.dylib) ;;
        *) printf 'Unbundled macOS dependency: %s\n' "$dependency" >&2; exit 1 ;;
      esac
    done < <(awk 'NR > 1 { print $1 }' <<< "$dependencies")
    exports="$(nm -gU "$library")"
    [[ "$exports" == *_OrtGetApiBase* ]]
    codesign --verify "$library"
    ;;
  win-*)
    library="$prefix/onnxruntime.dll"
    exports="$(MSYS_NO_PATHCONV=1 dumpbin /EXPORTS "$(cygpath -w "$library")")"
    [[ "$exports" == *OrtGetApiBase* ]]
    for native_name in onnxruntime.dll dxcompiler.dll dxil.dll; do
      [[ -s "$prefix/$native_name" ]]
      windows_path="$(cygpath -w "$prefix/$native_name")"
      dependencies="$(MSYS_NO_PATHCONV=1 dumpbin /DEPENDENTS "$windows_path")"
      header="$(MSYS_NO_PATHCONV=1 dumpbin /HEADERS "$windows_path")"
      case "$rid" in
        win-arm64) [[ "$header" == *'machine (ARM64)'* ]] ;;
        win-x64) [[ "$header" == *'machine (x64)'* ]] ;;
        *) exit 1 ;;
      esac
      if grep -Ei '(vcruntime|msvcp|libgcc|libstdc|webgpu_dawn|onnxruntime_providers).*\.dll' <<< "$dependencies"; then
        printf 'Unbundled Windows runtime dependency in %s.\n' "$native_name" >&2
        exit 1
      fi
    done
    [[ -s "$prefix/licenses/dependencies/dawn-src/third_party/directx-shader-compiler/src/LICENSE.TXT" ]]
    [[ -s "$prefix/licenses/dependencies/dawn-src/third_party/directx-shader-compiler/src/ThirdPartyNotices.txt" ]]
    [[ -s "$prefix/licenses/toolchain/windows-sdk/sdk_license.rtf" ]]
    [[ -s "$prefix/licenses/toolchain/windows-sdk/sdk_third_party_notices.rtf" ]]
    ;;
  *) printf 'Unsupported RID: %s\n' "$rid" >&2; exit 1 ;;
esac

[[ -s "$library" && -s "$prefix/build-info.txt" ]]
[[ -s "$prefix/licenses/dependencies/dawn-src/LICENSE" ]]
[[ -s "$prefix/licenses/onnxruntime/LICENSE" ]]
[[ -s "$prefix/licenses/onnxruntime/ThirdPartyNotices.txt" ]]
printf 'PASS: %s native architecture, exports, dependencies, and licenses.\n' "$rid"
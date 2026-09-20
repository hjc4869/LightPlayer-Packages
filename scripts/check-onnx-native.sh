#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rid="${1:?Usage: check-onnx-native.sh <rid>}"
prefix="$root/artifacts/onnx-$rid"

case "$rid" in
  linux-*)
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
    [[ -s "$prefix/licenses/dependencies/dawn-src/LICENSE" ]]
    [[ -s "$prefix/licenses/toolchain/GCC-copyright.txt" ]]
    [[ -s "$prefix/licenses/toolchain/GPL-3.txt" ]]
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
    [[ "$exports" == *_OrtSessionOptionsAppendExecutionProvider_CoreML* ]]
    codesign --verify "$library"
    ;;
  *) printf 'Unsupported RID: %s\n' "$rid" >&2; exit 1 ;;
esac

[[ -s "$library" && -s "$prefix/build-info.txt" ]]
[[ -s "$prefix/licenses/onnxruntime/LICENSE" ]]
[[ -s "$prefix/licenses/onnxruntime/ThirdPartyNotices.txt" ]]
printf 'PASS: %s native architecture, exports, dependencies, and licenses.\n' "$rid"
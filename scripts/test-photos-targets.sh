#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/tests/photos/targets.proj"

for flavor in wasm wasm-mt; do
  threads=false
  [[ "$flavor" != wasm-mt ]] || threads=true
  dotnet msbuild "$project" -nologo -v:minimal -p:RuntimeIdentifier=browser-wasm \
    -p:WasmEnableThreads="$threads" -p:ExpectedWasmCount=3 -p:ExpectedStaticCount=0 -p:ExpectedFlavor="$flavor"
done

dotnet msbuild "$project" -nologo -v:minimal -p:TargetPlatformIdentifier=browser \
  -p:ExpectedWasmCount=3 -p:ExpectedStaticCount=0 -p:ExpectedFlavor=wasm

for runtime in osx-arm64 osx-x64 linux-x64 linux-arm64 win-x64 win-arm64 android-arm64 android-x64; do
  for aot in true false; do
    for static in true false; do
      expected=0
      if [[ "$runtime" == osx-* && "$aot" == true && "$static" == true ]]; then
        expected=4
      fi
      dotnet msbuild "$project" -nologo -v:minimal -p:RuntimeIdentifier="$runtime" \
        -p:PublishAot="$aot" -p:EnableStaticPhotos="$static" \
        -p:ExpectedWasmCount=0 -p:ExpectedStaticCount="$expected"
    done
  done
done

if dotnet msbuild "$project" -nologo -v:quiet -p:RuntimeIdentifier=browser-wasm \
  -p:WasmEnableExceptionHandling=false -p:ExpectedWasmCount=3 -p:ExpectedStaticCount=0 -p:ExpectedFlavor=wasm; then
  echo 'Disabling wasm exception handling should have failed.' >&2
  exit 1
fi
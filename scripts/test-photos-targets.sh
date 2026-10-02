#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/tests/photos/targets.proj"

for framework in '' v8.0 v10.0 v11.0 v12.0; do
  emsdk=em3
  [[ "$framework" != v11.0 && "$framework" != v12.0 ]] || emsdk=em6
  for platform in rid class-library; do
    platform_args=(-p:RuntimeIdentifier=browser-wasm)
    [[ "$platform" != class-library ]] || platform_args=(-p:TargetPlatformIdentifier=browser)
    for flavor in wasm wasm-mt; do
      threads=false
      [[ "$flavor" != wasm-mt ]] || threads=true
      dotnet msbuild "$project" -nologo -v:minimal "${platform_args[@]}" \
        -p:TargetFrameworkVersion="$framework" -p:WasmEnableThreads="$threads" \
        -p:ExpectedWasmCount=3 -p:ExpectedStaticCount=0 -p:ExpectedFlavor="$flavor-$emsdk"
    done
  done
done

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
  -p:WasmEnableExceptionHandling=false -p:ExpectedWasmCount=3 -p:ExpectedStaticCount=0 -p:ExpectedFlavor=wasm-em3; then
  echo 'Disabling wasm exception handling should have failed.' >&2
  exit 1
fi
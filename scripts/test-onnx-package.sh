#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rid="${1:-linux-x64}"
version="${2:-1.30.0-test.1}"
test_root="$root/artifacts/build/onnx-package-tests/$rid"
project="$root/package/onnx/LightStudio.Onnx.csproj"
consumer="$root/tests/onnx/consumer/OnnxConsumer.csproj"
mkdir -p "$test_root/empty"

pack_args=("-p:OnnxRuntimeIdentifiers=$rid" -p:OnnxAllowPartialPackage=true "-p:PackageVersion=$version")
restore_args=("-p:OnnxPackageVersion=$version" "-p:RestoreAdditionalProjectSources=$test_root/packages"
  "-p:RestorePackagesPath=$test_root/restore")

dotnet pack "$project" -c Release -o "$test_root/packages" "${pack_args[@]}"
package="$test_root/packages/LightStudio.Onnx.$version.nupkg"
dotnet run --project "$consumer" -c Release "${restore_args[@]}" -- --check-package "$package" "$rid"

expected_failure() {
  local message="$1"
  shift
  if "$@" > "$test_root/expected-error.log" 2>&1; then
    printf 'Expected failure containing: %s\n' "$message" >&2
    exit 1
  fi
  if ! grep -Fq "$message" "$test_root/expected-error.log"; then
    cat "$test_root/expected-error.log" >&2
    exit 1
  fi
}

expected_failure 'Missing ONNX artifact' dotnet msbuild "$project" -nologo -t:ValidateOnnxArtifacts \
  "${pack_args[@]}" "-p:OnnxArtifactsPath=$test_root/empty"
expected_failure 'Release packages must contain all eight' dotnet msbuild "$project" -nologo -t:ValidateOnnxArtifacts \
  "-p:OnnxRuntimeIdentifiers=$rid" "-p:PackageVersion=$version"
expected_failure 'Partial ONNX packages require a prerelease' dotnet msbuild "$project" -nologo -t:ValidateOnnxArtifacts \
  "-p:OnnxRuntimeIdentifiers=$rid" -p:OnnxAllowPartialPackage=true -p:PackageVersion=1.30.0
expected_failure 'does not ship browser-wasm' dotnet msbuild "$consumer" -nologo -t:ValidateLightStudioOnnxPlatform \
  "${restore_args[@]}" -p:RuntimeIdentifier=browser-wasm -p:WasmEnableThreads=true
expected_failure 'does not support RuntimeIdentifier' dotnet msbuild "$consumer" -nologo -t:ValidateLightStudioOnnxPlatform \
  "${restore_args[@]}" -p:RuntimeIdentifier=linux-musl-x64
expected_failure 'requires Android API 27' dotnet msbuild "$consumer" -nologo -t:ValidateLightStudioOnnxPlatform \
  "${restore_args[@]}" -p:TargetPlatformIdentifier=android -p:SupportedOSPlatformVersion=26.0
expected_failure 'Remove conflicting Microsoft ONNX Runtime references' dotnet msbuild "$consumer" -nologo -t:ValidateLightStudioOnnxPlatform \
  "${restore_args[@]}" -p:OnnxTestConflictingReference=true

if [[ "$rid" != android-* ]]; then
  dotnet publish "$consumer" -c Release -r "$rid" --self-contained true \
    "${restore_args[@]}" -o "$test_root/publish"
  executable="$test_root/publish/OnnxConsumer"
  native_name=libonnxruntime.so
  case "$rid" in
    win-*) executable="$executable.exe"; native_name=onnxruntime.dll ;;
    osx-*) native_name=libonnxruntime.dylib ;;
  esac
  cmp "$root/artifacts/onnx-$rid/$native_name" "$test_root/publish/$native_name"
  if [[ "${ONNX_SKIP_EXECUTION:-0}" != 1 ]]; then
    "$executable" --cpu-smoke "$root/artifacts/onnx-$rid/smoke.onnx"
    if [[ "${ONNX_TEST_GPU:-0}" == 1 ]]; then
      "$executable" --gpu-smoke "$root/artifacts/onnx-$rid/smoke.onnx"
    fi
  fi
fi
printf 'PASS: %s package layout, release guards, platform guards, and native asset selection.\n' "$rid"
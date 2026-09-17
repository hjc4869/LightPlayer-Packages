#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rid="${1:-linux-x64}"
version="${2:-0.1.9-test.1}"
test_base="$root/artifacts/build/sqlite-vec-package-tests/$rid"
mkdir -p "$test_base"
test_root="$(mktemp -d "$test_base/run.XXXXXX")"
project="$root/package/sqlite-vec/LightStudio.sqlite-vec.csproj"
consumer="$root/tests/sqlite-vec/consumer/SqliteVecConsumer.csproj"
mkdir -p "$test_root/empty"

pack_args=("-p:SqliteVecRuntimeIdentifiers=$rid" -p:SqliteVecAllowPartialPackage=true "-p:PackageVersion=$version")
restore_args=("-p:SqliteVecPackageVersion=$version" "-p:RestoreAdditionalProjectSources=$test_root/packages"
  "-p:RestorePackagesPath=$test_root/restore")

dotnet pack "$project" -c Release -o "$test_root/packages" "${pack_args[@]}"
package="$test_root/packages/LightStudio.sqlite-vec.$version.nupkg"
dotnet run --project "$consumer" -c Release "${restore_args[@]}" -- --test-build-info
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

expected_failure 'Missing sqlite-vec artifact' dotnet msbuild "$project" -nologo -t:ValidateSqliteVecArtifacts \
  "${pack_args[@]}" "-p:SqliteVecArtifactsPath=$test_root/empty"
expected_failure 'Release packages must contain all eight' dotnet msbuild "$project" -nologo -t:ValidateSqliteVecArtifacts \
  "-p:SqliteVecRuntimeIdentifiers=$rid" "-p:PackageVersion=$version"
expected_failure 'Partial sqlite-vec packages require a prerelease' dotnet msbuild "$project" -nologo -t:ValidateSqliteVecArtifacts \
  "-p:SqliteVecRuntimeIdentifiers=$rid" -p:SqliteVecAllowPartialPackage=true -p:PackageVersion=0.1.9
expected_failure 'Unsupported sqlite-vec RIDs' dotnet msbuild "$project" -nologo -t:ValidateSqliteVecArtifacts \
  -p:SqliteVecRuntimeIdentifiers=browser-wasm -p:SqliteVecAllowPartialPackage=true "-p:PackageVersion=$version"
expected_failure 'does not support RuntimeIdentifier' dotnet msbuild "$consumer" -nologo -t:ValidateLightStudioSqliteVecPlatform \
  "${restore_args[@]}" -p:RuntimeIdentifier=browser-wasm
expected_failure 'does not support RuntimeIdentifier' dotnet msbuild "$consumer" -nologo -t:ValidateLightStudioSqliteVecPlatform \
  "${restore_args[@]}" -p:RuntimeIdentifier=linux-musl-x64
expected_failure 'requires Android API 27' dotnet msbuild "$consumer" -nologo -t:ValidateLightStudioSqliteVecPlatform \
  "${restore_args[@]}" -p:TargetPlatformIdentifier=android -p:SupportedOSPlatformVersion=26.0

if [[ "$rid" != android-* ]]; then
  dotnet publish "$consumer" -c Release -r "$rid" --self-contained true \
    "${restore_args[@]}" -o "$test_root/publish"
  executable="$test_root/publish/SqliteVecConsumer"
  native_name=vec0.so
  case "$rid" in
    win-*) executable="$executable.exe"; native_name=vec0.dll ;;
    osx-*) native_name=vec0.dylib ;;
  esac
  cmp "$root/artifacts/sqlite-vec-$rid/$native_name" "$test_root/publish/$native_name"
  if [[ "$rid" == win-* ]]; then
    "$executable" --probe-winsqlite | tee "$root/artifacts/sqlite-vec-$rid/winsqlite3-check.txt"
  fi
  "$executable" --smoke
fi
printf 'PASS: %s package layout, release/platform guards, and native asset selection.\n' "$rid"
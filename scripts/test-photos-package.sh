#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$repo_root/artifacts/build/photos-package-tests"
project="$repo_root/package/photos/LightStudio.Photos.csproj"

for library in libraw liblcms2; do
  test -f "$repo_root/artifacts/photos-linux-x64/$library.so" || {
    echo 'Build linux-x64 before running the NuGet consumer test.' >&2
    exit 1
  }
done

rm -rf -- "$test_root"
mkdir -p "$test_root/artifacts"

for target in linux-x64 linux-arm64 win-x64 win-arm64 android-arm64 android-x64 osx-arm64 osx-x64 browser-wasm browser-wasm-mt; do
  relative="photos-$target"
  case "$target" in
    linux-*) extensions=(so) ;;
    win-*) extensions=(dll) ;;
    android-*) relative="photos-android/$target"; extensions=(so) ;;
    osx-*) extensions=(dylib a) ;;
    browser-*) extensions=(a) ;;
  esac
  mkdir -p "$test_root/artifacts/$relative"
  if [[ -d "$repo_root/artifacts/$relative/licenses" ]]; then
    cp -R "$repo_root/artifacts/$relative/licenses" "$test_root/artifacts/$relative/"
  fi
  for extension in "${extensions[@]}"; do
    libraries=(libraw liblcms2)
    [[ "$extension" != a ]] || libraries+=(libjpeg libz)
    for library in "${libraries[@]}"; do
      source="$repo_root/artifacts/$relative/$library.$extension"
      destination="$test_root/artifacts/$relative/$library.$extension"
      if [[ -f "$source" ]]; then
        cp "$source" "$destination"
      else
        touch "$destination"
      fi
    done
  done
done

dotnet pack "$project" -o "$test_root/packages" -p:PackageVersion=0.0.0-test \
  -p:PhotosArtifactsPath="$test_root/artifacts"
package="$test_root/packages/LightStudio.Photos.0.0.0-test.nupkg"
unzip -q "$package" -d "$test_root/extracted"

for runtime in linux-x64 linux-arm64 win-x64 win-arm64 android-arm64 android-x64 osx-arm64 osx-x64; do
  test -d "$test_root/extracted/runtimes/$runtime/native"
done
test -f "$test_root/extracted/runtimes/win-arm64/native/libraw.dll"
test -f "$test_root/extracted/runtimes/win-arm64/native/liblcms2.dll"
test -f "$test_root/extracted/licenses/LLVM-MinGW/LLVM-MinGW-LICENSE.txt"
test -f "$test_root/extracted/licenses/LLVM-MinGW/COPYING.MinGW-w64-runtime.txt"
for runtime in osx-arm64 osx-x64 wasm wasm-mt; do
  test -f "$test_root/extracted/static/$runtime/libraw.a"
  test -f "$test_root/extracted/static/$runtime/liblcms2.a"
  test -f "$test_root/extracted/static/$runtime/libjpeg.a"
  test -f "$test_root/extracted/static/$runtime/libz.a"
done
test -f "$test_root/extracted/licenses/libjpeg-turbo/README.ijg"
test -f "$test_root/extracted/licenses/zlib/LICENSE"
for folder in build buildTransitive; do
  test -f "$test_root/extracted/$folder/LightStudio.Photos.props"
  test -f "$test_root/extracted/$folder/LightStudio.Photos.targets"
done
if find "$test_root/extracted/runtimes" -name '*.a' | grep .; then
  echo 'Static archives must not be NuGet runtime assets.' >&2
  exit 1
fi

dotnet run --project "$repo_root/tests/photos/consumer/Photos.Consumer.csproj" \
  -p:PhotosPackageVersion=0.0.0-test -p:RestoreAdditionalProjectSources="$test_root/packages" \
  -p:RestorePackagesPath="$test_root/restore"

dotnet publish "$repo_root/tests/photos/consumer/Photos.Consumer.csproj" \
  --runtime win-arm64 --self-contained false -p:UseAppHost=false \
  -p:PhotosPackageVersion=0.0.0-test -p:RestoreAdditionalProjectSources="$test_root/packages" \
  -p:RestorePackagesPath="$test_root/restore" --output "$test_root/win-arm64-publish"
for library in libraw liblcms2; do
  cmp "$test_root/artifacts/photos-win-arm64/$library.dll" "$test_root/win-arm64-publish/$library.dll"
done

for artifact in "$test_root"/artifacts/photos-*/*.{so,dll,dylib,a} \
  "$test_root"/artifacts/photos-android/android-*/*.so \
  "$test_root"/artifacts/photos-win-*/licenses/*.txt \
  "$test_root"/artifacts/photos-android/android-arm64/licenses/NOTICE.toolchain; do
  [[ -f "$artifact" ]] || continue
  mv "$artifact" "$artifact.missing"
  if dotnet msbuild "$project" -nologo -v:quiet -t:ValidatePhotosArtifacts \
      -p:PhotosArtifactsPath="$test_root/artifacts" > "$test_root/missing.log" 2>&1; then
    echo "Missing artifact was not rejected: $artifact" >&2
    exit 1
  fi
  grep -Fq 'Missing Photos artifact' "$test_root/missing.log"
  mv "$artifact.missing" "$artifact"
done

printf 'NuGet layout, Linux P/Invoke, Windows ARM64 publish selection, and missing-artifact guards passed. Nonlocal binaries are fixtures; do not publish this test package.\n'
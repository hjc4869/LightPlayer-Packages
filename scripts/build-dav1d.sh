#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dav1d_dir="$repo_root/dav1d"

if [[ $# -ne 3 ]]; then
  cat >&2 <<'EOF'
Usage: build-dav1d.sh <target> <prefix> <build-dir>

Targets:
  browser-wasm-st  Emscripten, no shared memory (single-threaded FFmpeg package)
  browser-wasm-mt  Emscripten with pthreads
  android-arm64    Android NDK, aarch64
  android-x64      Android NDK, x86_64
  osx-arm64        macOS, Apple silicon
EOF
  exit 2
fi

target="$1"
prefix="$2"
build_dir="$3"

if [[ ! -f "$dav1d_dir/meson.build" ]]; then
  echo "dav1d is not initialized at '$dav1d_dir'. Run 'git submodule update --init'." >&2
  exit 1
fi

for tool in meson ninja; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "'$tool' is required to build dav1d." >&2
    exit 1
  fi
done

rm -rf -- "$build_dir" "$prefix"
mkdir -p "$build_dir"

cross_file="$build_dir/cross.ini"

meson_args=(
  --prefix "$prefix"
  --libdir lib
  --buildtype release
  --default-library static
  -Denable_tools=false
  -Denable_tests=false
  -Denable_examples=false
)

# meson always passes '-pthread' for dependency('threads') on Emscripten, which
# marks the objects as shared memory and makes them unlinkable into a
# single-threaded module. This wrapper drops those flags for that variant only.
write_single_threaded_emcc_wrapper() {
  local wrapper="$1" real_emcc
  real_emcc="$(command -v emcc)"
  cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "\$@"; do
  case "\$arg" in
    -pthread|-sPTHREAD_POOL_SIZE=*|-sUSE_PTHREADS=*|-matomics|-mbulk-memory) continue ;;
  esac
  args+=("\$arg")
done
exec "$real_emcc" "\${args[@]}"
EOF
  chmod +x "$wrapper"
}

require_ndk_tool() {
  if [[ ! -x "$1" ]]; then
    echo "Expected the NDK to provide '$1'." >&2
    exit 1
  fi
}

case "$target" in
  browser-wasm-st | browser-wasm-mt)
    for tool in emcc em++ emar emranlib; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "'$tool' is required to build dav1d for browser-wasm." >&2
        exit 1
      fi
    done

    if [[ "$target" == browser-wasm-st ]]; then
      cc="$build_dir/emcc-single-threaded"
      write_single_threaded_emcc_wrapper "$cc"
    else
      cc="$(command -v emcc)"
    fi

    cat >"$cross_file" <<EOF
[binaries]
c = '$cc'
cpp = '$(command -v em++)'
ar = '$(command -v emar)'
ranlib = '$(command -v emranlib)'
pkg-config = 'pkg-config'

[host_machine]
system = 'emscripten'
cpu_family = 'wasm32'
cpu = 'wasm32'
endian = 'little'
EOF

    # The consuming application decides the Emscripten thread pool size.
    meson_args+=(--cross-file "$cross_file" -Denable_asm=false -Db_staticpic=false -Dc_thread_count=0)
    ;;

  android-arm64 | android-x64)
    android_api="${ANDROID_API_LEVEL:-21}"
    android_ndk_home="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_ROOT:-}}}"

    if [[ -z "$android_ndk_home" || ! -d "$android_ndk_home" ]]; then
      echo "Android NDK not found. Set ANDROID_NDK_HOME to a valid NDK installation." >&2
      exit 1
    fi

    shopt -s nullglob
    prebuilt_dirs=("$android_ndk_home"/toolchains/llvm/prebuilt/*/)
    shopt -u nullglob

    if [[ ${#prebuilt_dirs[@]} -eq 0 ]]; then
      echo "No LLVM toolchain was found under '$android_ndk_home/toolchains/llvm/prebuilt'." >&2
      exit 1
    fi

    toolchain_bin="${prebuilt_dirs[0]%/}/bin"

    if [[ "$target" == android-arm64 ]]; then
      triple=aarch64-linux-android
      meson_cpu_family=aarch64
      meson_cpu=aarch64
    else
      triple=x86_64-linux-android
      meson_cpu_family=x86_64
      meson_cpu=x86_64
    fi

    cc="$toolchain_bin/${triple}${android_api}-clang"
    cxx="$toolchain_bin/${triple}${android_api}-clang++"
    ar="$toolchain_bin/llvm-ar"
    ranlib="$toolchain_bin/llvm-ranlib"
    strip="$toolchain_bin/llvm-strip"

    for tool in "$cc" "$cxx" "$ar" "$ranlib" "$strip"; do
      require_ndk_tool "$tool"
    done

    {
      cat <<EOF
[binaries]
c = '$cc'
cpp = '$cxx'
ar = '$ar'
ranlib = '$ranlib'
strip = '$strip'
pkg-config = 'pkg-config'
EOF

      if [[ "$target" == android-x64 ]]; then
        if ! command -v nasm >/dev/null 2>&1; then
          echo "'nasm' is required to assemble the dav1d x86_64 optimizations." >&2
          exit 1
        fi
        echo "nasm = '$(command -v nasm)'"
      fi

      cat <<EOF

[host_machine]
system = 'android'
cpu_family = '$meson_cpu_family'
cpu = '$meson_cpu'
endian = 'little'
EOF
    } >"$cross_file"

    meson_args+=(--cross-file "$cross_file" -Denable_asm=true -Db_staticpic=true)
    ;;

  osx-arm64)
    deployment_target="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

    if [[ "$(uname -s)" != "Darwin" ]]; then
      echo "The osx-arm64 dav1d build must run on macOS." >&2
      exit 1
    fi

    # The toolchain clang is invoked directly (not through the /usr/bin shim), so
    # it has no implicit SDK and needs an explicit -isysroot.
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"

    cat >"$cross_file" <<EOF
[binaries]
c = '$(xcrun --sdk macosx --find clang)'
cpp = '$(xcrun --sdk macosx --find clang++)'
ar = '$(xcrun --sdk macosx --find ar)'
ranlib = '$(xcrun --sdk macosx --find ranlib)'
strip = '$(xcrun --sdk macosx --find strip)'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$sdk_path', '-mmacosx-version-min=$deployment_target']
c_link_args = ['-arch', 'arm64', '-isysroot', '$sdk_path', '-mmacosx-version-min=$deployment_target']

[host_machine]
system = 'darwin'
subsystem = 'macos'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

    export MACOSX_DEPLOYMENT_TARGET="$deployment_target"

    meson_args+=(--cross-file "$cross_file" -Denable_asm=true -Db_staticpic=true)
    ;;

  *)
    echo "Unknown dav1d target '$target'." >&2
    exit 2
    ;;
esac

meson setup "${meson_args[@]}" "$build_dir" "$dav1d_dir"
meson install -C "$build_dir"

static_library="$prefix/lib/libdav1d.a"
pkg_config_file="$prefix/lib/pkgconfig/dav1d.pc"

for artifact in "$static_library" "$pkg_config_file"; do
  if [[ ! -f "$artifact" ]]; then
    echo "dav1d did not produce '$artifact'." >&2
    exit 1
  fi
done

if [[ "$target" == browser-wasm-st ]]; then
  # meson records the threads dependency flags in dav1d.pc even though the
  # objects were built without them; leaving them would make FFmpeg emit a
  # shared-memory build.
  sed -i.bak -E 's/ -pthread//g; s/ -sPTHREAD_POOL_SIZE=[0-9]+//g' "$pkg_config_file"
  rm -f -- "$pkg_config_file.bak"

  if grep -q 'pthread' "$pkg_config_file"; then
    echo "Failed to remove the pthread flags from '$pkg_config_file'." >&2
    exit 1
  fi
fi

printf "Built dav1d %s for '%s' in %s\n" \
  "$(sed -n 's/^Version: *//p' "$pkg_config_file")" "$target" "$prefix"

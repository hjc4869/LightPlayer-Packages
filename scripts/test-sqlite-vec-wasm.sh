#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rid="${1:?Usage: test-sqlite-vec-wasm.sh <browser-wasm|browser-wasm-mt>}"
flags=()
case "$rid" in
  browser-wasm) flags+=(-DSQLITE_THREADSAFE=0) ;;
  browser-wasm-mt) flags+=(-pthread -sPTHREAD_POOL_SIZE=1 -DSQLITE_THREADSAFE=1) ;;
  *) printf 'Unsupported WASM variant: %s\n' "$rid" >&2; exit 1 ;;
esac
build_dir="${SQLITE_VEC_BUILD_DIR:-$root/artifacts/build/sqlite-vec-$rid}"
prefix="${SQLITE_VEC_ARTIFACTS_DIR:-$root/artifacts}/sqlite-vec-$rid"
sqlite_source="$build_dir/_deps/sqlite_headers-src"
test_dir="$build_dir/smoke"
mkdir -p "$test_dir"

bash "$root/scripts/check-sqlite-vec-native.sh" "$rid" "$prefix"
emcc -O2 "${flags[@]}" -DSQLITE_OMIT_LOAD_EXTENSION -sENVIRONMENT=node -sEXIT_RUNTIME=1 \
  -sWASM_ASYNC_COMPILATION=0 -I"$sqlite_source" \
  "$root/tests/sqlite-vec/wasm-smoke.c" "$prefix/libvec0.a" "$sqlite_source/sqlite3.c" \
  -o "$test_dir/smoke.cjs"
node "$test_dir/smoke.cjs"
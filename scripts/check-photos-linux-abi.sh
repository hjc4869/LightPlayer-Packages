#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$repo_root/artifacts/photos-linux-x64}"

for library in libraw liblcms2; do
  versions="$(readelf --version-info "$output/$library.so")"
  for family in GLIBC GLIBCXX CXXABI; do
    case "$family" in
      GLIBC) limit=2.17 ;;
      GLIBCXX) limit=3.4.19 ;;
      CXXABI) limit=1.3.7 ;;
    esac
    required="$(grep -oE "${family}_[0-9.]+" <<<"$versions" | sed "s/${family}_//" | sort -Vu | tail -n 1 || true)"
    [[ -n "$required" ]] || continue
    highest="$(printf '%s\n%s\n' "$required" "$limit" | sort -V | tail -n 1)"
    if [[ "$highest" != "$limit" ]]; then
      echo "$library requires $family $required, newer than the $limit baseline." >&2
      exit 1
    fi
    printf '%s: %s %s (maximum %s)\n' "$library" "$family" "$required" "$limit"
  done
done
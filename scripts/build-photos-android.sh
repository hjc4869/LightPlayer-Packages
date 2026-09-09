#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/build-photos.sh" android-arm64
"$script_dir/build-photos.sh" android-x64
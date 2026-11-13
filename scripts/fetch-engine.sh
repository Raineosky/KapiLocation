#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine_path=Vendor/idevice/libidevice_ffi.a
engine_hash=05e6f58f082ee9f866a60763debe9b016e003005d424ac227b8d459686a2b575
if [ ! -f "$engine_path" ]; then
  curl --fail --location --retry 3 \
    'https://raw.githubusercontent.com/ChrisMack32/Locus/83c8fb324983728e8f44759cfd834dc637ee38b5/Vendor/idevice/libidevice_ffi.a' \
    --output "$engine_path.download"
  printf '%s  %s\n' "$engine_hash" "$engine_path.download" | shasum -a 256 -c -
  mv "$engine_path.download" "$engine_path"
fi
printf '%s  %s\n' "$engine_hash" "$engine_path" | shasum -a 256 -c -

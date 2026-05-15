#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== vtracer-ffi Universal Binary Build ==="

rustup target add aarch64-apple-darwin x86_64-apple-darwin

echo "--- Building arm64 ---"
cargo build --release --target aarch64-apple-darwin

echo "--- Building x86_64 ---"
cargo build --release --target x86_64-apple-darwin

OUT="../DraftCanvas/Vendor/vtracer"
mkdir -p "$OUT"

echo "--- lipo ---"
lipo -create \
  target/aarch64-apple-darwin/release/libvtracer_ffi.a \
  target/x86_64-apple-darwin/release/libvtracer_ffi.a \
  -output "$OUT/libvtracer_ffi.a"

cp vtracer_ffi.h "$OUT/vtracer_ffi.h" 2>/dev/null || true

echo "=== Done ==="
echo "Output: $OUT/libvtracer_ffi.a"
file "$OUT/libvtracer_ffi.a"
lipo -info "$OUT/libvtracer_ffi.a"

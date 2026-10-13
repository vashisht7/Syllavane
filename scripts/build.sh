#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-engines.py
python3 scripts/patch-whisper.py
cmake -S vendor/llama -B vendor/llama/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DGGML_NATIVE=OFF -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build vendor/llama/build --target llama-server -j 4
cmake -S vendor/whisper -B vendor/whisper/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DGGML_NATIVE=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=ON -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build vendor/whisper/build --target whisper-server -j 4
swift test
swift build -c release
swift scripts/icon.swift Resources/IconSizes
mkdir -p Resources/AppIcon.iconset
for size in 16 32 128 256 512; do
  cp "Resources/IconSizes/icon_${size}.png" "Resources/AppIcon.iconset/icon_${size}x${size}.png"
  double=$((size * 2))
  cp "Resources/IconSizes/icon_${double}.png" "Resources/AppIcon.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
python3 scripts/package.py

#!/bin/bash
set -e
cd "$(dirname "$0")"
mkdir -p bin

echo "Compiling native PipeWire visualizer..."
rustc -O src/visualizer.rs -o bin/lumania-vis

echo "Compiling native Wallpaper Color Engine..."
rustc -O src/wallpaper_colors.rs -o bin/lumania-colors

echo "Compiling native System Status & Network Engine..."
rustc -O src/status_backend.rs -o bin/lumania-status

echo "Compiling native GPUI Settings & Update App..."
cargo build --release --manifest-path app/Cargo.toml
cp app/target/release/lumania-app bin/lumania-app-bin
chmod +x bin/lumania-app-bin

echo "Build complete: bin/lumania-vis, bin/lumania-colors, bin/lumania-status, and bin/lumania-app-bin"

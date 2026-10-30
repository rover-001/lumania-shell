#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Compiling native PipeWire visualizer..."
rustc -O visualizer.rs -o lumania-vis

echo "Compiling native Wallpaper Color Engine..."
rustc -O wallpaper_colors.rs -o lumania-colors

echo "Compiling native System Status & Network Engine..."
rustc -O status_backend.rs -o lumania-status

echo "Compiling native GPUI Settings & Update App..."
(cd lumania-app && cargo build --release)
cp lumania-app/target/release/lumania-app ./lumania-app-bin
chmod +x ./lumania-app-bin

echo "Build complete: lumania-vis, lumania-colors, lumania-status, and lumania-app"

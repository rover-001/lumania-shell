#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Compiling native PipeWire visualizer..."
rustc -O visualizer.rs -o lumania-vis

echo "Compiling native Wallpaper Color Engine..."
rustc -O wallpaper_colors.rs -o lumania-colors

echo "Compiling native System Status & Network Engine..."
rustc -O status_backend.rs -o lumania-status

echo "Build complete: lumania-vis, lumania-colors, and lumania-status"

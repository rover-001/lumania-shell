#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Compiling native PipeWire visualizer..."
rustc -O visualizer.rs -o lumania-vis
echo "Build complete: lumania-vis"

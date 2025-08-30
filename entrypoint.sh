#!/usr/bin/env bash
set -euo pipefail

# Define vars
GITHUB_ACTIONS=${GITHUB_ACTIONS:-false}
GITHUB_SHA=${GITHUB_SHA:-"main"}

# Inputs
CPY_TARGET=${CPY_TARGET:-"build"}
CPY_PLATFORM=${CPY_PLATFORM}
CPY_BOARD=${CPY_BOARD}

git checkout "$GITHUB_SHA"
python tools/ci_fetch_deps.py ${CPY_PLATFORM}
pip3 install --upgrade -r requirements-dev.txt
pip3 install --upgrade -r requirements-doc.txt
make -j$(nproc) -C mpy-cross

# Build
if [ "$CPY_TARGET" = "build" ]; then
    echo "Building CircuitPython: $CPY_PLATFORM:$CPY_BOARD"
    make -j$(nproc) -C ports/"$CPY_PLATFORM" BOARD="$CPY_BOARD"
    mkdir -p .build
    mv ports/"$CPY_PLATFORM"/build-"$CPY_BOARD"/* .build/
    echo "Build artifacts are located at: .build"
fi
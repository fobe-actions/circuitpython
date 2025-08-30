#!/usr/bin/env bash
set -euo pipefail

# Define vars (use safe defaults so -u won't fail)
: "${GITHUB_ACTIONS:=false}"
: "${GITHUB_SHA:=main}"

# Inputs (provide safe defaults)
: "${CPY_TARGET:=build}"
: "${CPY_PLATFORM:=}"
: "${CPY_BOARD:=}"
: "${CPY_BOARDS:=}"
: "${CPY_FLAGS:=}"
: "${CPY_DEBUG:=}"
: "${CPY_TRANSLATION:=en_US}"

git checkout "${GITHUB_SHA}"
make -C ports/"${CPY_PLATFORM}" fetch-port-submodules
pip3 install --upgrade -r requirements-dev.txt
pip3 install --upgrade -r requirements-doc.txt
make -j"$(nproc)" -C mpy-cross

# Espressif IDF
if [[ ${CPY_PLATFORM} == "espressif" ]]; then
	export IDF_PATH=/workspace/ports/espressif/esp-idf
	export IDF_TOOLS_PATH=/workspace/.idf_tools
	export ESP_ROM_ELF_DIR=/workspace/.idf_tools
	source "${IDF_PATH}/export.sh"
fi

# Build
if [[ ${CPY_TARGET} == "build" ]]; then
	echo "Building CircuitPython: ${CPY_PLATFORM}:${CPY_BOARD}"
	make -j"$(nproc)" -C "ports/${CPY_PLATFORM}" "${CPY_FLAGS}" BOARD="${CPY_BOARD}" DEBUG="${CPY_DEBUG}" TRANSLATION="${CPY_TRANSLATION}"
	echo "Build artifacts are located at: /workspace/ports/${CPY_PLATFORM}/build-${CPY_BOARD}"
fi

# Release
if [[ ${CPY_TARGET} == "release" ]]; then
	echo "Building CircuitPython release: ${CPY_PLATFORM}:${CPY_BOARDS}"
	cd ./tools && BOARDS="${CPY_BOARDS}" python3 -u build_release_files.py
	echo "Build artifacts are located at: /workspace/bin"
fi

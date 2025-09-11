#!/usr/bin/env bash

set -euo pipefail

WORKSPACE=/workspace
JOBS=$(nproc)

# Define vars (use safe defaults so -u won't fail)
: "${GITHUB_ACTIONS:=false}"
# Inputs (provide safe defaults)
: "${REPO_REMOTE:=origin}"
: "${REPO_REF:=main}"
: "${BOARD:=}"
: "${TRANSLATION:=en_US}"

# Reset to the target SHA
git fetch upstream --tags --prune --force
git fetch origin --tags --prune --force
git fetch "${REPO_REMOTE}" "${REPO_REF}"
git reset --hard FETCH_HEAD
git repack -d

pip3 install --upgrade -r requirements-dev.txt
pip3 install --upgrade -r requirements-doc.txt

# Espressif IDF
if [[ ${CPY_PORT} == "espressif" ]]; then
	export IDF_PATH=/workspace/ports/espressif/esp-idf
    git submodule update --init --depth=1 --recursive ${IDF_PATH}
	export IDF_TOOLS_PATH=/workspace/.idf_tools
	export ESP_ROM_ELF_DIR=/workspace/.idf_tools
    /workspace/ports/espressif/esp-idf/install.sh
	# trunk-ignore(shellcheck/SC1091)
	source "${IDF_PATH}/export.sh"
    pip3 install --upgrade minify-html jsmin sh requests-cache
fi

make -j"${JOBS}" -C mpy-cross
make -C ports/"${CPY_PORT}" fetch-port-submodules

FW_DATE=$(date '+%Y%m%d')
FW_TAG="-${FW_DATE}-$(python3 py/version.py)"
echo "Repository firmware CircuitPython version: ${FW_TAG}"


# Build
echo "Build ${CPY_PORT} firmware: ${BOARD}"
mkdir -p "${WORKSPACE}/bin"

function copy_artefacts {
    local dest_dir=$1
    local descr=$2
    local fw_tag=$3
    local build_dir=$4
    shift 4
    for ext in "$@"; do
        dest=${dest_dir}/${descr}${fw_tag}.${ext}
        if [[ -r ${build_dir}/firmware.${ext} ]]; then
            mv "${build_dir}"/firmware."${ext}" "${dest}"
            elif [[ -r ${build_dir}/circuitpython.${ext} ]]; then
            mv "${build_dir}"/circuitpython."${ext}" "${dest}"
            # trunk-ignore(shellcheck/SC2292)
            # trunk-ignore(shellcheck/SC2166)
            elif [ "${ext}" = app-bin -a -r "${build_dir}"/circuitpython-firmware.bin ]; then
            # esp32 has circuitpython-firmware.bin which is just the application
            mv "${build_dir}"/circuitpython-firmware.bin "${dest}"
        fi
    done
}

function build_board {
    echo "building ${BOARD}"
    make -j"${JOBS}" -C ports/"${CPY_PORT}" BOARD="${BOARD}" TRANSLATION="${TRANSLATION}"
    copy_artefacts "${WORKSPACE}/bin" "${BOARD}" "${FW_TAG}" ports/"${CPY_PORT}"/build-"${BOARD}" "$@"
}

if [[ ${CPY_PORT} == "espressif" ]]; then
    build_board bin elf map uf2 app-bin
fi

if [[ ${CPY_PORT} == "nordic" ]]; then
    build_board bin hex uf2
fi
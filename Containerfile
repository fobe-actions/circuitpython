FROM python:3.13-bookworm AS base

ENV PIP_ROOT_USER_ACTION=ignore

# Apt dependencies
RUN apt-get update && apt-get install -y \
    jq jdupes build-essential \
    libgpiod-dev libyaml-cpp-dev libbluetooth-dev libusb-1.0-0-dev libi2c-dev libuv1-dev \
    libx11-dev libinput-dev libxkbcommon-x11-dev \
    openssl libssl-dev libulfius-dev liborcania-dev \
    git git-lfs gettext cmake mtools floppyd dosfstools ninja-build \
    && rm -rf /var/lib/apt/lists/*

FROM base AS repo
ARG BUILD_REPO="https://github.com/adafruit/circuitpython.git"
ARG BUILD_REF="main"
ARG BUILD_FORK_REPO="https://github.com/fobe-projects/circuitpython.git"
ARG BUILD_FORK_REF="main"

WORKDIR /workspace

RUN git config --global --add safe.directory /workspace \
    && git config --global protocol.file.allow always \
    && git clone --depth 1 --filter=tree:0 "${BUILD_REPO}" /workspace \
    && cd /workspace && git checkout "${BUILD_REF}" \
    && git submodule update --init --filter=blob:none data extmod lib tools frozen \
    && git fetch --no-recurse-submodules --shallow-since="2021-07-01" --tags "${BUILD_REPO}" HEAD \
    && git fetch --no-recurse-submodules --shallow-since="2021-07-01" origin \
    && git repack -d \
    && git remote add fork "${BUILD_FORK_REPO}" \
    && git fetch fork --filter=tree:0 \
    && git fetch --no-recurse-submodules --filter=tree:0 fork "${BUILD_FORK_REF}" \
    && git checkout -b fork-branch "fork/${BUILD_FORK_REF}" \
    && git repack -d

RUN pip3 install --upgrade -r requirements-doc.txt \
    && pip3 install --upgrade -r requirements-dev.txt \
    && pip3 install --upgrade huffman

FROM repo AS port

ARG ARM_TOOLCHAIN_EABI_VERSION="14.2.rel1"
ARG ARM_TOOLCHAIN_ELF_VERSION="13.3.rel1"
ARG BUILD_PLATFORM

# Broadcom
RUN if [ "${BUILD_PLATFORM}" = "broadcom" ]; then \
    git submodule sync --recursive; \
    git submodule update --init --recursive --filter=tree:0 ports/broadcom/firmware; \
fi

RUN if [ "${BUILD_PLATFORM}" != "zephyr-cp" ]; then \
    make -C ports/"${BUILD_PLATFORM}" fetch-port-submodules; \
fi

RUN if [ "${BUILD_PLATFORM}" != "espressif" ] && [ "${BUILD_PLATFORM}" != "zephyr-cp" ] && [ "${BUILD_PLATFORM}" != "litex" ] && [ "${BUILD_PLATFORM}" != "none" ]; then \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/$ARM_TOOLCHAIN_EABI_VERSION/binrel/arm-gnu-toolchain-$ARM_TOOLCHAIN_EABI_VERSION-aarch64-arm-none-eabi.tar.xz"; \
    elif [ "$ARCH" = "amd64" ]; then \
        TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/$ARM_TOOLCHAIN_EABI_VERSION/binrel/arm-gnu-toolchain-$ARM_TOOLCHAIN_EABI_VERSION-x86_64-arm-none-eabi.tar.xz"; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        exit 1; \
    fi && \
    mkdir -p /usr/local/arm-none-eabi && \
    curl -fsSL "$TOOLCHAIN_URL" | tar -xJ -C /usr/local/arm-none-eabi --strip-components=1 && \
    for f in /usr/local/arm-none-eabi/bin/arm-none-eabi-*; do \
        ln -sf "$f" /usr/local/bin/$(basename "$f"); \
    done \
fi

# Broadcom
RUN if [ "${BUILD_PLATFORM}" = "broadcom" ]; then \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/$ARM_TOOLCHAIN_ELF_VERSION/binrel/arm-gnu-toolchain-$ARM_TOOLCHAIN_ELF_VERSION-aarch64-aarch64-none-elf.tar.xz"; \
    elif [ "$ARCH" = "amd64" ]; then \
        TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/$ARM_TOOLCHAIN_ELF_VERSION/binrel/arm-gnu-toolchain-$ARM_TOOLCHAIN_ELF_VERSION-x86_64-aarch64-none-elf.tar.xz"; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        exit 1; \
    fi && \
    mkdir -p /usr/local/arm-none-elf && \
    curl -fsSL "$TOOLCHAIN_URL" | tar -xJ -C /usr/local/arm-none-elf --strip-components=1 && \
    for f in /usr/local/arm-none-elf/bin/arm-none-elf-*; do \
        ln -sf "$f" /usr/local/bin/$(basename "$f"); \
    done \
fi

# Nordic
RUN if [ "${BUILD_PLATFORM}" = "nordic" ]; then \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        TOOLCHAIN_URL="https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/aarch64-unknown-linux-gnu/nrfutil"; \
    elif [ "$ARCH" = "amd64" ]; then \
        TOOLCHAIN_URL="https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/x86_64-unknown-linux-gnu/nrfutil"; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        exit 1; \
    fi && curl -fsSL "$TOOLCHAIN_URL" -o nrfutil;\
    chmod +x nrfutil; \
    ./nrfutil install nrf5sdk-tools; \
    mv nrfutil /usr/local/bin; \
    nrfutil -V; \
fi

# Espressif IDF
ENV IDF_PATH=/workspace/ports/espressif/esp-idf
ENV IDF_TOOLS_PATH=/workspace/.idf_tools
ENV ESP_ROM_ELF_DIR=/workspace/.idf_tools
RUN if [ "${BUILD_PLATFORM}" = "espressif" ]; then \
    git submodule update --init --depth=1 --recursive ${IDF_PATH}; \
    $IDF_PATH/install.sh; \
    bash -c "source ${IDF_PATH}/export.sh && pip3 install --upgrade minify-html jsmin sh requests-cache"; \
    rm -rf $IDF_TOOLS_PATH/dist; \
fi

# Litex
RUN if [ "${BUILD_PLATFORM}" = "litex" ]; then \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        TOOLCHAIN_URL="https://static.dev.sifive.com/dev-tools/riscv64-unknown-elf-gcc-8.3.0-2019.08.0-x86_64-linux-centos6.tar.gz"; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        exit 1; \
    fi && curl -fsSL "$TOOLCHAIN_URL" -o riscv64-unknown-elf-gcc-8.3.0-2019.08.0-x86_64-linux-centos6.tar.gz;\
    tar -C /usr --strip-components=1 -xaf riscv64-unknown-elf-gcc-8.3.0-2019.08.0-x86_64-linux-centos6.tar.gz; \
    rm -rf riscv64-unknown-elf-gcc-8.3.0-2019.08.0-x86_64-linux-centos6.tar.gz; \
fi

# Zephyr
RUN if [ "${BUILD_PLATFORM}" = "zephyr-cp" ]; then \
    cd ports/zephyr-cp \
    && pip install west \
    && west init -l zephyr-config \
    && west update \
    && west zephyr-export \
    && pip install -r zephyr/scripts/requirements.txt \
    && west sdk install; \
fi

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]
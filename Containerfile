FROM python:3.13-slim-bookworm AS base

ENV PIP_ROOT_USER_ACTION=ignore

WORKDIR /workspace

# Apt dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && apt-get install -y \
    jq jdupes build-essential \
    libgpiod-dev libyaml-cpp-dev libbluetooth-dev libusb-1.0-0-dev libi2c-dev libuv1-dev \
    libx11-dev libinput-dev libxkbcommon-x11-dev \
    openssl libssl-dev libulfius-dev liborcania-dev \
    git git-lfs gettext cmake mtools floppyd dosfstools ninja-build \
    parted zip wget curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --upgrade pip setuptools wheel build huffman poetry

FROM base AS repo

ARG WORKSPACE_REPO="https://github.com/fobe-projects/circuitpython.git"
ARG WORKSPACE_REPO_UPSTREAM="https://github.com/adafruit/circuitpython.git"
ARG WORKSPACE_REPO_REMOTE="origin"
ARG WORKSPACE_REPO_REF="main"

RUN git config --global --add safe.directory /workspace \
    && git clone "${WORKSPACE_REPO}" /workspace \
    && git remote add upstream "${WORKSPACE_REPO_UPSTREAM}" \
    && git fetch upstream --tags --prune --force \
    && git fetch origin --tags --prune --force \
    && git reset --hard "${WORKSPACE_REPO_REMOTE}/${WORKSPACE_REPO_REF}" \
    && git repack -d

ARG WORKSPACE_BUILD_REMOTE="origin"
ARG WORKSPACE_BUILD_REF="main"
RUN echo "Hard reset repository to: ${WORKSPACE_REPO_REMOTE}/${WORKSPACE_REPO_REF}" \
    && git fetch upstream --tags --prune --force \
    && git fetch origin --tags --prune --force \
    && git fetch "${WORKSPACE_BUILD_REMOTE}" "${WORKSPACE_BUILD_REF}" \
    && git reset --hard FETCH_HEAD \
    && git repack -d \
    && echo "Repository firmware MicroPython version: $(git describe --tags --dirty --always --match 'v[1-9].*')" \
    && echo "Repository firmware CircuitPython version: $(python3 py/version.py)"

RUN git submodule update --init --depth=1 --filter=blob:none data extmod lib tools frozen \
    && git repack -d

RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --upgrade -r requirements-doc.txt \
    && pip3 install --upgrade -r requirements-dev.txt

FROM repo AS arm

ARG ARM_TOOLCHAIN_EABI_VERSION="14.2.rel1"
RUN --mount=type=cache,target=/tmp/arm-toolchain-eabi-cache,id=arm-toolchain-eabi-${ARM_TOOLCHAIN_EABI_VERSION} \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/$ARM_TOOLCHAIN_EABI_VERSION/binrel/arm-gnu-toolchain-$ARM_TOOLCHAIN_EABI_VERSION-aarch64-arm-none-eabi.tar.xz"; \
        TOOLCHAIN_ARCHIVE="/tmp/arm-toolchain-eabi-cache/arm-gnu-toolchain-$ARM_TOOLCHAIN_EABI_VERSION-aarch64-arm-none-eabi.tar.xz"; \
    elif [ "$ARCH" = "amd64" ]; then \
        TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/$ARM_TOOLCHAIN_EABI_VERSION/binrel/arm-gnu-toolchain-$ARM_TOOLCHAIN_EABI_VERSION-x86_64-arm-none-eabi.tar.xz"; \
        TOOLCHAIN_ARCHIVE="/tmp/arm-toolchain-eabi-cache/arm-gnu-toolchain-$ARM_TOOLCHAIN_EABI_VERSION-x86_64-arm-none-eabi.tar.xz"; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        exit 1; \
    fi && \
    mkdir -p /usr/local/arm-none-eabi && \
    if [ ! -f "$TOOLCHAIN_ARCHIVE" ]; then \
        curl -fsSL "$TOOLCHAIN_URL" -o "$TOOLCHAIN_ARCHIVE"; \
    fi && \
    tar -xJf "$TOOLCHAIN_ARCHIVE" -C /usr/local/arm-none-eabi --strip-components=1 && \
    for f in /usr/local/arm-none-eabi/bin/arm-none-eabi-*; do \
        ln -sf "$f" /usr/local/bin/$(basename "$f"); \
    done

FROM arm AS analog

ENV CPY_PORT=analog

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM arm AS atmel-samd

ENV CPY_PORT=atmel-samd

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM arm AS broadcom

ENV CPY_PORT=broadcom

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

ARG ARM_TOOLCHAIN_ELF_VERSION="13.3.rel1"
RUN --mount=type=cache,target=/tmp/arm-toolchain-elf-cache,id=arm-toolchain-elf-${ARM_TOOLCHAIN_ELF_VERSION} \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/$ARM_TOOLCHAIN_ELF_VERSION/binrel/arm-gnu-toolchain-$ARM_TOOLCHAIN_ELF_VERSION-aarch64-aarch64-none-elf.tar.xz"; \
        TOOLCHAIN_ARCHIVE="/tmp/arm-toolchain-elf-cache/arm-gnu-toolchain-$ARM_TOOLCHAIN_ELF_VERSION-aarch64-arm-none-elf.tar.xz"; \
    elif [ "$ARCH" = "amd64" ]; then \
        TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/$ARM_TOOLCHAIN_ELF_VERSION/binrel/arm-gnu-toolchain-$ARM_TOOLCHAIN_ELF_VERSION-x86_64-aarch64-none-elf.tar.xz"; \
        TOOLCHAIN_ARCHIVE="/tmp/arm-toolchain-elf-cache/arm-gnu-toolchain-$ARM_TOOLCHAIN_ELF_VERSION-x86_64-arm-none-elf.tar.xz"; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        exit 1; \
    fi && \
    mkdir -p /usr/local/arm-none-elf && \
    if [ ! -f "$TOOLCHAIN_ARCHIVE" ]; then \
        curl -fsSL "$TOOLCHAIN_URL" -o "$TOOLCHAIN_ARCHIVE"; \
    fi && \
    tar -xJf "$TOOLCHAIN_ARCHIVE" -C /usr/local/arm-none-elf --strip-components=1 && \
    for f in /usr/local/arm-none-elf/bin/arm-none-elf-*; do \
        ln -sf "$f" /usr/local/bin/$(basename "$f"); \
    done

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM arm AS cxd56

ENV CPY_PORT=cxd56

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM repo AS espressif

ENV CPY_PORT=espressif

ENV IDF_PATH=/workspace/ports/espressif/esp-idf
ENV IDF_TOOLS_PATH=/workspace/.idf_tools
ENV ESP_ROM_ELF_DIR=/workspace/.idf_tools

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

RUN cd ${IDF_PATH} \
    && git submodule update --init --depth=1 --recursive \
    && git repack -d \
    && cd /workspace \
    && git repack -d

RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=cache,target=/workspace/.idf_tools/dist \
    "${IDF_PATH}"/install.sh > /dev/null 2>&1 \
    && bash -c "source ${IDF_PATH}/export.sh && pip3 install --upgrade minify-html jsmin sh requests-cache"

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM repo AS litex

ENV CPY_PORT=litex

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

# Apt dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && apt-get install -y \
    gcc-riscv64-unknown-elf \
    && rm -rf /var/lib/apt/lists/*


COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM arm AS mimxrt10xx

ENV CPY_PORT=mimxrt10xx

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM arm AS nordic

ENV CPY_PORT=nordic

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

RUN --mount=type=cache,target=/tmp/nrfutil-cache,id=nrfutil-tools \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        TOOLCHAIN_URL="https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/aarch64-unknown-linux-gnu/nrfutil"; \
        TOOLCHAIN_ARCHIVE="/tmp/nrfutil-cache/nrfutil-arm64"; \
    elif [ "$ARCH" = "amd64" ]; then \
        TOOLCHAIN_URL="https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/x86_64-unknown-linux-gnu/nrfutil"; \
        TOOLCHAIN_ARCHIVE="/tmp/nrfutil-cache/nrfutil-amd64"; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        exit 1; \
    fi && \
    mkdir -p /usr/local/nrfutil && \
    if [ ! -f "$TOOLCHAIN_ARCHIVE" ]; then \
        curl -fsSL "$TOOLCHAIN_URL" -o "$TOOLCHAIN_ARCHIVE"; \
    fi && \
    cp "$TOOLCHAIN_ARCHIVE" /usr/local/nrfutil/nrfutil && \
    chmod +x /usr/local/nrfutil/nrfutil && \
    /usr/local/nrfutil/nrfutil install nrf5sdk-tools; \
    ln -sf /usr/local/nrfutil/nrfutil /usr/local/bin/nrfutil

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM arm AS raspberrypi

ENV CPY_PORT=raspberrypi

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM arm AS renode

ENV CPY_PORT=renode

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM arm AS stm

ENV CPY_PORT=stm

RUN make -C ports/"${CPY_PORT}" fetch-port-submodules && git repack -d

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

FROM repo AS zephyr-cp

ENV CPY_PORT=zephyr-cp

RUN cd ports/zephyr-cp \
    && pip install west \
    && west init -l zephyr-config \
    && west update \
    && west zephyr-export \
    && pip install -r zephyr/scripts/requirements.txt \
    && west sdk install \
    && git repack -d \
    && cd /workspace \
    && git repack -d

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]
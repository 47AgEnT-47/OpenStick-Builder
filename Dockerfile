FROM ubuntu:24.04

# Отключаем интерактив
ENV DEBIAN_FRONTEND=noninteractive

# Ставим пакеты (добавлен git!)
RUN apt-get update && apt-get install -y \
    git \
    android-sdk-libsparse-utils \
    autoconf \
    automake \
    binfmt-support \
    cmake \
    debian-archive-keyring \
    debootstrap \
    mmdebstrap \
    device-tree-compiler \
    fdisk \
    g++-aarch64-linux-gnu \
    gcc-aarch64-linux-gnu \
    gcc-arm-none-eabi \
    libtool \
    make \
    pkg-config \
    python3-cryptography \
    python3-pyasn1-modules \
    python3-pycryptodome \
    qemu-user-static \
    unzip \
    wget \
    && echo "--- TOP 100 LARGEST DIRECTORIES ---" \
    && du -ah /usr | sort -rh | head -n 100 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && find /usr/lib/arm-none-eabi/newlib -name "*.a" -exec strip --strip-debug {} + \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/locale

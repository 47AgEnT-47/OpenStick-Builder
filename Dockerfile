FROM ubuntu:24.04

# Отключаем интерактив и ставим пакеты
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    android-sdk-libsparse-utils autoconf automake binfmt-support \
    cmake debian-archive-keyring debootstrap mmdebstrap \
    device-tree-compiler fdisk g++-aarch64-linux-gnu \
    gcc-aarch64-linux-gnu gcc-arm-none-eabi libtool \
    make pkg-config python3-cryptography python3-pyasn1-modules \
    python3-pycryptodome qemu-user-static unzip wget \
    && rm -rf /var/lib/apt/lists/*

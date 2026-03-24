#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
SRCDIR=$(pwd)/src

# build and install gt
(
cd src/libusbgx/
autoreconf -i
)

mkdir -p build
(
cd build
PKG_CONFIG_PATH=${CHROOT}/usr/lib/aarch64-linux-gnu/pkgconfig \
    ${SRCDIR}/libusbgx/configure \
        --host aarch64-linux-gnu \
        --prefix=/usr \
        --with-sysroot=${CHROOT}
)
make -j$(nproc) -C build DESTDIR=$(pwd)/dist CFLAGS="--sysroot=${CHROOT}" install
make -j$(nproc) -C build CFLAGS="--sysroot=${CHROOT}" install

rm -rf build/*
PKG_CONFIG_PATH=${CHROOT}/usr/lib/pkgconfig:${CHROOT}/usr/lib/aarch64-linux-gnu/pkgconfig \
    cmake -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
        -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
        -DCMAKE_C_FLAGS=-I$(pwd)/dist/usr/include \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_SYSROOT=${CHROOT} \
        -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
        -S ${SRCDIR}/gt/source \
        -B build

make -j$(nproc) -C build DESTDIR=$(pwd)/dist install

rm -rf dist/usr/share dist/usr/lib/cmake dist/usr/lib/pkgconfig \
    dist/usr/lib/*a dist/usr/bin/ga* dist/usr/bin/s* dist/usr/include

cp -a configs/templates dist/etc/gt

# Монтируем файловые системы для работы chroot
mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/

# Удаляем dev-пакеты
chroot ${CHROOT} apt purge -y \
    build-essential \
    libconfig-dev \
    libc6-dev \
    linux-libc-dev

# Очищаем зависимости и кэш
chroot ${CHROOT} apt autoremove -y
chroot ${CHROOT} apt clean

# Размонтируем
umount ${CHROOT}/proc ${CHROOT}/sys ${CHROOT}/dev

# Создаём чистый rootfs.tgz для последующей сборки образов
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .

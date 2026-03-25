#!/bin/sh

CHROOT=${CHROOT=$(pwd)/rootfs}
export DEBIAN_FRONTEND=noninteractive

# Подготовка папок
rm -f rootfs.raw boot.raw
mkdir -p files mnt

# --- Сборка BOOT ---
dd if=/dev/zero of=boot.raw bs=1M count=64 status=none
mkfs.ext2 -F boot.raw
mount boot.raw mnt
tar xf rootfs.tgz -C mnt ./boot --exclude='./boot/linux.efi' --strip-components=2
umount mnt

# --- Сборка ROOTFS ---
dd if=/dev/zero of=rootfs.raw bs=1M count=1536 status=none
mkfs.ext4 -F rootfs.raw
mount rootfs.raw mnt

# Распаковка (сразу отсекаем мусор)
tar xpf rootfs.tgz -C mnt --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*' \
    --exclude='./usr/share/doc' --exclude='./usr/share/man' --exclude='./usr/share/locale' \
    --exclude='./usr/share/info' --exclude='./usr/include'

# Монтирование
mount -t proc /proc mnt/proc
mount -t sysfs /sys mnt/sys
mount -o bind /dev mnt/dev
mount -o bind /dev/pts mnt/dev/pts

# 1. Жесткая очистка софта (APT ЖИВ)
INSTALLED_PURGE=$(chroot mnt dpkg-query -W -f='${db:Status-Status} ${Package}\n' \
    "python3*" "python-*" "perl*" "libpython*" "libperl*" "vim*" "nano*" "gdb*" "git*" "gcc*" "g++*" "make*" "build-essential" 2>/dev/null \

    | awk '$1=="installed" {print $2}')

# Оставляем критическую базу для работы APT и DPKG
SAFE_LIST=$(echo "$INSTALLED_PURGE" | grep -vE "perl-base|gcc-[0-9]+-base|libgcc-s1|libstdc\+\+|apt|dpkg|libperl")

if [ -n "$SAFE_LIST" ]; then
    echo "Force removing: $SAFE_LIST"
    chroot mnt dpkg --purge --force-depends $SAFE_LIST || true
fi

# 2. Чистка модулей ядра
KVER=$(ls mnt/lib/modules | head -n 1)
KDIR="mnt/lib/modules/$KVER/kernel"
if [ -d "$KDIR" ]; then
    rm -rf "$KDIR/drivers/media" "$KDIR/drivers/gpu" "$KDIR/drivers/sound" \
           "$KDIR/drivers/hid" "$KDIR/drivers/iio" "$KDIR/drivers/input/joystick" \
           "$KDIR/drivers/input/tablet" "$KDIR/drivers/nfc" "$KDIR/drivers/bluetooth" \
           "$KDIR/sound" "$KDIR/net/bluetooth" "$KDIR/net/nfc"
    find "$KDIR/fs" -mindepth 1 -maxdepth 1 -not -name "ext*" -not -name "fat" -not -name "vfat" -not -name "nls" -exec rm -rf {} +
fi

# 3. ТОТАЛЬНАЯ зачистка файловой системы (Удаляем ВСЁ лишнее)
rm -rf mnt/usr/include \
       mnt/usr/share/doc/* \
       mnt/usr/share/man/* \
       mnt/usr/share/info/* \
       mnt/usr/share/locale/* \
       mnt/usr/share/common-licenses/* \
       mnt/usr/share/bash-completion \
       mnt/usr/share/help/* \
       mnt/usr/share/gnome/help/* \
       mnt/usr/share/omf/* \
       mnt/usr/share/zsh \
       mnt/usr/share/fish \
       mnt/usr/share/terminfo/* \
       mnt/usr/share/i18n \
       mnt/usr/share/zoneinfo/* \
       mnt/usr/share/icons/* \
       mnt/usr/share/pixmaps/* \
       mnt/var/lib/apt/lists/* \
       mnt/var/cache/apt/archives/* \
       mnt/var/log/* \
       mnt/root/.cache \
       mnt/tmp/*

# Оставляем минимальный terminfo для SSH
mkdir -p mnt/usr/share/terminfo/l mnt/usr/share/terminfo/x
touch mnt/usr/share/terminfo/l/linux mnt/usr/share/terminfo/x/xterm

# 4. Агрессивный STRIP (срезаем символы)
find mnt/lib/modules -name "*.ko" -exec strip --strip-debug {} + 2>/dev/null || true
find mnt/usr/bin mnt/usr/sbin mnt/usr/lib mnt/lib mnt/bin mnt/sbin \
     -type f -exec strip --strip-all {} + 2>/dev/null || true

# 5. Чистка базы пакетов (оставляем только status, удаляем списки файлов)
# ВНИМАНИЕ: это сэкономит место, но apt не сможет удалять текущие пакеты
rm -rf mnt/var/lib/dpkg/info/*.md5sums
rm -rf mnt/var/lib/dpkg/info/*.list
rm -rf mnt/var/lib/dpkg/info/*.shlibs

# Финальный штрих
cp -a dist/* mnt/ 2>/dev/null || true

# Размонтирование
umount mnt/dev/pts mnt/dev mnt/sys mnt/proc mnt

# Оптимизация размера
shrink_raw() {
    FILE=$1
    e2fsck -f -y "$FILE"
    resize2fs -M "$FILE"
    BLOCK_COUNT=$(dumpe2fs -h "$FILE" | grep "Block count" | awk '{print $3}')
    BLOCK_SIZE=$(dumpe2fs -h "$FILE" | grep "Block size" | awk '{print $3}')
    truncate -s $((BLOCK_COUNT * BLOCK_SIZE)) "$FILE"
}

shrink_raw rootfs.raw
shrink_raw boot.raw

echo "Final sizes:"
ls -lh rootfs.raw boot.raw

img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

echo "Done!"

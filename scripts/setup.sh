#!/bin/sh
set -e

CHROOT=${CHROOT=$(pwd)/rootfs}
mkdir -p mnt files

# --- 1. СБОРКА BOOT (64MB) ---
dd if=/dev/zero of=boot.raw bs=1M count=64 status=none
mkfs.ext2 -F boot.raw
mount boot.raw mnt
tar xf rootfs.tgz -C mnt ./boot --exclude='./boot/linux.efi' --strip-components=2
umount mnt

# --- 2. ПОДГОТОВКА ROOTFS (1.5GB sparse) ---
dd if=/dev/zero of=rootfs.raw bs=1M count=1536 status=none
mkfs.ext4 -F rootfs.raw
mount rootfs.raw mnt

# Распаковка с жестким фильтром (сразу отсекаем 150-200МБ мусора)
tar xpf rootfs.tgz -C mnt --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*' \
    --exclude='./usr/share/doc' --exclude='./usr/share/man' --exclude='./usr/share/locale' \
    --exclude='./usr/share/info' --exclude='./usr/include' --exclude='./usr/share/icons'

# Монтирование для работы внутри
mount -t proc /proc mnt/proc
mount -t sysfs /sys mnt/sys
mount -o bind /dev mnt/dev
mount -o bind /dev/pts mnt/dev/pts

# --- 3. УДАЛЕНИЕ ВРЕМЕННОГО СОФТА (Оставляем APT и сервисы) ---
# Удаляем компиляторы и dev-пакеты, которые были нужны только для сборки
EXTRA_PURGE="build-essential gcc-14* g++-14* cpp-14* binutils* libc6-dev linux-libc-dev libconfig-dev make patch gdb git"
INSTALLED_PURGE=$(chroot mnt dpkg-query -W -f='${db:Status-Status} ${Package}\n' $EXTRA_PURGE 2>/dev/null | awk '$1=="installed" {print $2}')

if [ -n "$INSTALLED_PURGE" ]; then
    echo "Cleaning build tools: $INSTALLED_PURGE"
    chroot mnt dpkg --purge --force-depends $INSTALLED_PURGE || true
fi

# --- 4. ТОТАЛЬНАЯ ХИРУРГИЧЕСКАЯ ЧИСТКА (Вырезаем ВСЁ мясо) ---
# Чистим системные папки от остатков
rm -rf mnt/usr/include/* \
       mnt/usr/share/doc/* \
       mnt/usr/share/man/* \
       mnt/usr/share/info/* \
       mnt/usr/share/locale/* \
       mnt/usr/share/common-licenses/* \
       mnt/usr/share/bash-completion/* \
       mnt/usr/share/help/* \
       mnt/usr/share/icons/* \
       mnt/usr/share/pixmaps/* \
       mnt/usr/share/zoneinfo/* \
       mnt/usr/share/i18n/* \
       mnt/usr/share/terminfo/* \
       mnt/usr/lib/gcc/* \
       mnt/usr/src/* \
       mnt/var/lib/apt/lists/* \
       mnt/var/cache/apt/archives/* \
       mnt/var/log/* \
       mnt/root/.cache \
       mnt/tmp/*

# Удаляем статические библиотеки (.a), они не нужны для работы программ
find mnt/usr/lib mnt/lib -name "*.a" -delete

# Оставляем минимальный конфиг для терминала (чтобы SSH не тупил)
mkdir -p mnt/usr/share/terminfo/l mnt/usr/share/terminfo/x
touch mnt/usr/share/terminfo/l/linux mnt/usr/share/terminfo/x/xterm

# --- 5. АГРЕССИВНЫЙ STRIP (Срезаем отладочные символы) ---
# Это уменьшит бинарники (NetworkManager, ModemManager и т.д.) в 2-3 раза
find mnt/usr/bin mnt/usr/sbin mnt/usr/lib mnt/lib mnt/bin mnt/sbin \
     -type f -exec strip --strip-all {} + 2>/dev/null || true

# Чистим модули ядра (оставляем только сеть и FS)
KVER=$(ls mnt/lib/modules | head -n 1)
find "mnt/lib/modules/$KVER/kernel" -name "*.ko" -exec strip --strip-debug {} + 2>/dev/null || true

# --- 6. ОЧИСТКА БАЗЫ ПАКЕТОВ ---
# Удаляем списки файлов и контрольные суммы (APT будет работать, но база станет крошечной)
rm -rf mnt/var/lib/dpkg/info/*.md5sums
rm -rf mnt/var/lib/dpkg/info/*.list
rm -rf mnt/var/lib/dpkg/info/*.shlibs

# Размонтирование
umount mnt/dev/pts mnt/dev mnt/sys mnt/proc mnt

# --- 7. ФИНАЛЬНАЯ ОПТИМИЗАЦИЯ РАЗМЕРА ---
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

# Конвертация в sparse для прошивки
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

echo "Done! Sparse images created in 'files/' folder."
echo "Final sizes:"
ls -lh rootfs.raw boot.raw

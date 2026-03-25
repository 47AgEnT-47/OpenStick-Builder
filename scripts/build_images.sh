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
# Копируем только ядро и конфиг, остальное (dtb/initrd) по ситуации
tar xf rootfs.tgz -C mnt ./boot --exclude='./boot/linux.efi' --strip-components=2
umount mnt

# --- Сборка ROOTFS ---
dd if=/dev/zero of=rootfs.raw bs=1M count=1536 status=none
mkfs.ext4 -F rootfs.raw
mount rootfs.raw mnt

# Распаковка (исключаем тяжелые каталоги сразу при распаковке)
tar xpf rootfs.tgz -C mnt --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*' \
    --exclude='./usr/share/doc' --exclude='./usr/share/man' --exclude='./usr/share/locale'

# Монтирование для работы chroot
mount -t proc /proc mnt/proc
mount -t sysfs /sys mnt/sys
mount -o bind /dev mnt/dev
mount -o bind /dev/pts mnt/dev/pts

# 1. Удаляем только то, что реально установлено в системе
# Ищем пакеты по маскам и удаляем их скопом
INSTALLED_PURGE=$(chroot mnt dpkg-query -W -f='${Package}\n' \
    "python3*" "python-*" "perl*" "libpython*" "libperl*" "vim*" "nano*" "gdb*" "git*" "gcc*" "g++*" "make*" "build-essential" \
    2>/dev/null || true)

if [ -n "$INSTALLED_PURGE" ]; then
    chroot mnt apt-get purge -y $INSTALLED_PURGE
fi

chroot mnt apt-get autoremove -y --purge
chroot mnt apt-get clean

# 2. Чистка модулей ядра (оставляем только сеть и ext4)
# Удаляем звук, видео, джойстики, лишние ФС
KVER=$(ls mnt/lib/modules | head -n 1)
KDIR="mnt/lib/modules/$KVER/kernel"
if [ -d "$KDIR" ]; then
    rm -rf "$KDIR/drivers/media" "$KDIR/drivers/gpu" "$KDIR/drivers/sound" \
           "$KDIR/drivers/hid" "$KDIR/drivers/iio" "$KDIR/drivers/input/joystick" \
           "$KDIR/drivers/input/tablet" "$KDIR/drivers/nfc" "$KDIR/drivers/bluetooth" \
           "$KDIR/sound" "$KDIR/net/bluetooth" "$KDIR/net/nfc"
    
    # Оставляем только нужные ФС (ext2/4)
    find "$KDIR/fs" -mindepth 1 -maxdepth 1 -not -name "ext*" -not -name "fat" -not -name "vfat" -not -name "nls" -exec rm -rf {} +
fi

# 3. Глубокая ручная очистка файловой системы
rm -rf mnt/usr/include \
       mnt/usr/share/info/* \
       mnt/usr/share/bash-completion \
       mnt/usr/share/zsh \
       mnt/usr/share/fish \
       mnt/usr/share/terminfo/* \
       mnt/usr/share/i18n \
       mnt/usr/share/zoneinfo/* \
       mnt/var/lib/apt/lists/* \
       mnt/var/cache/apt/archives/* \
       mnt/var/log/* \
       mnt/root/.cache \
       mnt/tmp/* \
       mnt/usr/share/icons \
       mnt/usr/share/pixmaps

# Оставляем только базовый термinfo (linux и xterm)
mkdir -p mnt/usr/share/terminfo/l mnt/usr/share/terminfo/x
# (команды копирования нужных terminfo если нужно, иначе SSH может ругаться на backspace)

# 4. Бинарная оптимизация (STRIP) - ОЧЕНЬ ВАЖНО
# Удаляет отладочные символы, уменьшает бинарники в разы
find mnt/lib/modules -name "*.ko" -exec strip --strip-debug {} + 2>/dev/null || true

# Финальный стрип всего живого (бинарники, библиотеки, модули ядра)
# Это безопасно для работы, но невозможно для отладки (debug)
find mnt/usr/bin mnt/usr/sbin mnt/usr/lib mnt/lib mnt/bin mnt/sbin \
     -type f -exec strip --strip-all {} + 2>/dev/null || true


# 5. Очистка базы данных пакетов (оставляем статус для работы apt, но удаляем инфо о файлах)
rm -rf mnt/var/lib/dpkg/info/*.md5sums
rm -rf mnt/var/lib/dpkg/info/*.list

# Установка ваших файлов (в самом конце, чтобы не затерло)
cp -a dist/* mnt/

# Размонтирование
umount mnt/dev/pts
umount mnt/dev
umount mnt/sys
umount mnt/proc
umount mnt

# Оптимизация размера образа
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

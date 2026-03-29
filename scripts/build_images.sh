#!/bin/sh -e

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

# Распаковка (исключаем лишнее сразу)
tar xpf rootfs.tgz -C mnt --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*'

# Установка ваших файлов
cp -a dist/* mnt

# Монтирование системных директорий для работы apt
for dir in proc sys dev dev/pts run; do
    mkdir -p "${CHROOT}/${dir}"
    mount --bind "/${dir}" "${CHROOT}/${dir}"
done

# Удаляем мусор
chroot mnt dpkg-query -W -f='${Installed-Size}\t${Package}\n' | sort -n | awk '{printf "%.2f MB\t%s\n", $1/1024, $2}'

chroot mnt apt-get update -y
chroot mnt apt-get purge -y \
    libconfig-dev libc6-dev linux-libc-dev gcc g++ make \
    perl perl-modules-5.40 libperl5.40 \
    libc-l10n debconf-i18n || true

chroot mnt apt-get autoremove -y --purge
chroot mnt apt-get clean

chroot mnt dpkg-query -W -f='${Installed-Size}\t${Package}\n' | sort -n | awk '{printf "%.2f MB\t%s\n", $1/1024, $2}'
# --- Глубокая ручная очистка (док, локали, кэши) ---
find mnt/usr/share/locale/ -maxdepth 1 -mindepth 1 ! -name 'en' ! -name 'en_US' ! -name 'locale.alias' -exec rm -rf {} +
rm -rf mnt/usr/include/* \
       mnt/usr/share/doc/* \
       mnt/usr/share/man/* \
       mnt/usr/share/info/* \
       mnt/usr/share/common-licenses/* \
       mnt/var/lib/apt/lists/* \
       mnt/var/cache/apt/archives/* \
       mnt/var/log/* \
       mnt/root/.cache \
       mnt/tmp/* \
       mnt/var/tmp/*

# Удаление статических библиотек и специфических путей
find mnt/usr/lib -name "*.a" -delete
find mnt/usr/lib -name "pkgconfig" -type d -exec rm -rf {} +

# Размонтирование в обратном порядке
for dir in proc sys dev/pts dev run; do umount "${CHROOT}/${dir}"; done
# --- Оптимизация и сжатие ---
shrink_raw() {
    FILE=$1
    e2fsck -fDy "$FILE"
    resize2fs -M "$FILE"
    BLOCK_COUNT=$(dumpe2fs -h "$FILE" | grep "Block count" | awk '{print $3}')
    BLOCK_SIZE=$(dumpe2fs -h "$FILE" | grep "Block size" | awk '{print $3}')
    truncate -s $((BLOCK_COUNT * BLOCK_SIZE)) "$FILE"
}

shrink_raw rootfs.raw
shrink_raw boot.raw

# Вывод размеров
echo "Final sizes after resize:"
ls -lh rootfs.raw boot.raw

# Создание разреженных образов (Android Sparse)
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

echo "Done! Images are in 'files/' directory."

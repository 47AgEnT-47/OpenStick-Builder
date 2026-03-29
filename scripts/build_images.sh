#!/bin/sh -e

# Точка монтирования для работы
MNT_DIR="$(pwd)/mnt"
export DEBIAN_FRONTEND=noninteractive

# Подготовка папок
rm -f rootfs.raw boot.raw
mkdir -p files "$MNT_DIR"

# --- Сборка BOOT ---
dd if=/dev/zero of=boot.raw bs=1M count=64 status=none
mkfs.ext2 -F boot.raw
mount boot.raw "$MNT_DIR"
tar xf rootfs.tgz -C "$MNT_DIR" ./boot --exclude='./boot/linux.efi' --strip-components=2
umount "$MNT_DIR"

# --- Сборка ROOTFS ---
dd if=/dev/zero of=rootfs.raw bs=1M count=1536 status=none
mkfs.ext4 -F rootfs.raw
mount rootfs.raw "$MNT_DIR"

# Распаковка
tar xpf rootfs.tgz -C "$MNT_DIR" --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*'
cp -a dist/* "$MNT_DIR"

# --- Настройка сети и системных директорий ---
# Копируем DNS с хоста, иначе apt не найдет репозитории
cp /etc/resolv.conf "$MNT_DIR/etc/resolv.conf"

for dir in proc sys dev dev/pts run; do
    mkdir -p "$MNT_DIR/$dir"
    mount --bind "/$dir" "$MNT_DIR/$dir"
done

# --- Работа внутри CHROOT ---
chroot "$MNT_DIR" apt-get update -y
chroot "$MNT_DIR" apt-get purge -y \
    libconfig-dev libc6-dev linux-libc-dev gcc g++ make \
    perl perl-modules-5.40 libperl5.40 \
    libc-l10n debconf-i18n || true

chroot "$MNT_DIR" apt-get autoremove -y --purge
chroot "$MNT_DIR" apt-get clean

# --- Очистка (док, локали, кэши) ---
find "$MNT_DIR/usr/share/locale/" -maxdepth 1 -mindepth 1 ! -name 'en' ! -name 'en_US' ! -name 'locale.alias' -exec rm -rf {} +
rm -rf "$MNT_DIR/usr/include/*" \
       "$MNT_DIR/usr/share/doc/*" \
       "$MNT_DIR/usr/share/man/*" \
       "$MNT_DIR/var/lib/apt/lists/*" \
       "$MNT_DIR/var/cache/apt/archives/*" \
       "$MNT_DIR/etc/resolv.conf" # Удаляем DNS хоста перед финализацией

# --- РАЗМОНТИРОВАНИЕ (Важен обратный порядок) ---
# Сначала виртуальные системы, потом сам образ
for dir in run dev/pts dev sys proc; do
    umount -l "$MNT_DIR/$dir" || true
done
umount -l "$MNT_DIR"

# --- Оптимизация (теперь образы свободны) ---
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

# Создание разреженных образов
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

echo "Done! Images are in 'files/' directory."

#!/bin/sh -e

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

# --- Настройка сети и системных директорий (FIX) ---
# Удаляем старый файл/ссылку и пишем DNS Google напрямую
rm -f "$MNT_DIR/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "$MNT_DIR/etc/resolv.conf"
echo "nameserver 1.1.1.1" >> "$MNT_DIR/etc/resolv.conf"

for dir in proc sys dev dev/pts run; do
    mkdir -p "$MNT_DIR/$dir"
    mount --bind "/$dir" "$MNT_DIR/$dir"
done

# --- Работа внутри CHROOT ---
# Твой вывод размеров ДО
echo "--- Packages size BEFORE cleanup ---"
chroot "$MNT_DIR" dpkg-query -W -f='${Installed-Size}\t${Package}\n' | sort -n | awk '{printf "%.2f MB\t%s\n", $1/1024, $2}'

chroot "$MNT_DIR" apt-get update -y
chroot "$MNT_DIR" apt-get purge -y \
    libconfig-dev libc6-dev linux-libc-dev \
    libperl5.40 libc-l10n debconf-i18n || true

chroot "$MNT_DIR" apt-get autoremove -y --purge
chroot "$MNT_DIR" apt-get clean

# Твой вывод размеров ПОСЛЕ
echo "--- Packages size AFTER cleanup ---"
chroot "$MNT_DIR" dpkg-query -W -f='${Installed-Size}\t${Package}\n' | sort -n | awk '{printf "%.2f MB\t%s\n", $1/1024, $2}'

# --- Очистка файлов ---
find mnt/usr/share/locale/ -maxdepth 1 -mindepth 1 ! -name 'en' ! -name 'en_US' ! -name 'locale.alias' -exec rm -rf {} +
rm -rf "$MNT_DIR/usr/include/"* \
       "$MNT_DIR/usr/share/doc/"* \
       "$MNT_DIR/usr/share/man/"* \
       "$MNT_DIR/usr/share/info/"* \
       "$MNT_DIR/usr/share/common-licenses/"* \
       "$MNT_DIR/var/lib/apt/lists/"* \
       "$MNT_DIR/var/cache/apt/archives/"* \
       "$MNT_DIR/var/log/"* \
       "$MNT_DIR/root/.cache" \
       "$MNT_DIR/tmp/"* \
       "$MNT_DIR/var/tmp/"*

# Удаление статических библиотек и специфических путей
find "$MNT_DIR/usr/lib" -name "*.a" -delete
find "$MNT_DIR/usr/lib" -name "pkgconfig" -type d -exec rm -rf {} +

dd if=/dev/zero of="$MNT_DIR/zero.fill" bs=1M status=progress || true
rm -f "$MNT_DIR/zero.fill"
sync

# --- РАЗМОНТИРОВАНИЕ ---
# Сначала вложенные, потом корень
for dir in run dev/pts dev sys proc; do
    umount -l "$MNT_DIR/$dir" || true
done
umount -l "$MNT_DIR"

# --- Оптимизация (FIX: выполняется на ОТМОНТИРОВАННОМ образе) ---
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

# Итоги
du -h rootfs.raw
ls -lh rootfs.raw boot.raw
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

echo "Done! Check 'files/' folder."

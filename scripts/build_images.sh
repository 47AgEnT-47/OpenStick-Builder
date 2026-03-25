#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}

# package rootfs
rm -f rootfs.raw boot.raw
mkdir -p files mnt

# create boot
dd if=/dev/zero of=boot.raw bs=1M count=64 status=none
mkfs.ext2 -F boot.raw
mount boot.raw mnt
tar xf rootfs.tgz -C mnt ./boot --exclude='./boot/linux.efi' --strip-components=2
umount mnt

# create root img
dd if=/dev/zero of=rootfs.raw bs=1M count=1536 status=none
mkfs.ext4 -F rootfs.raw
mount rootfs.raw mnt
tar xpf rootfs.tgz -C mnt --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*'

# install gt
cp -a dist/* mnt

# mount /dev/pts for apt
mkdir -p mnt/dev/pts
mount -o bind /dev/pts mnt/dev/pts

chroot mnt apt-get purge -y build-essential libconfig-dev libc6-dev linux-libc-dev 
chroot mnt apt-get autoremove --purge -y
chroot mnt apt-get clean
rm -rf mnt/usr/include mnt/usr/lib/aarch64-linux-gnu/pkgconfig mnt/usr/lib/*.a mnt/usr/share/doc mnt/usr/share/man mnt/var/lib/apt/lists/*

umount mnt/dev/pts
umount mnt

# resize to minimum with automatic yes
e2fsck -f -y rootfs.raw
resize2fs -M rootfs.raw
e2fsck -f -y boot.raw
resize2fs -M boot.raw

# show final sizes
echo "Final sizes after resize:"
ls -lh rootfs.raw boot.raw

# create sparse android images
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

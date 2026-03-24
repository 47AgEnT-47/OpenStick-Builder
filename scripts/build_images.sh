#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}

# package rootfs
rm -f rootfs.raw boot.raw
mkdir -p files mnt

# create boot
mkfs.ext2 boot.raw
mount boot.raw mnt
tar xf rootfs.tgz -C mnt ./boot --exclude='./boot/linux.efi' --strip-components=2
umount mnt

# create root img
mkfs.ext4 rootfs.raw
mount rootfs.raw mnt
tar xpf rootfs.tgz -C mnt --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*'

# install gt
cp -a dist/* mnt

chroot mnt apt purge -y build-essential libconfig-dev libc6-dev linux-libc-dev 
chroot mnt apt autoremove -y
chroot mnt apt clean
rm -rf mnt/usr/include mnt/usr/lib/aarch64-linux-gnu/pkgconfig mnt/usr/lib/*.a mnt/usr/share/doc mnt/usr/share/man mnt/var/lib/apt/lists/*

umount mnt

# resize to minimum
e2fsck -f rootfs.raw
resize2fs -M rootfs.raw
e2fsck -f boot.raw
resize2fs -M boot.raw

# create sparse android images
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

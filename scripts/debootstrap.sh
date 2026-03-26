#!/bin/sh -e

: "${CHROOT:=$(pwd)/rootfs}" "${RELEASE:=stable}" "${HOST_NAME:=openstick}"

rm -rf "$CHROOT"

echo "Using mmdebstrap..."
mmdebstrap --arch=arm64 --include=systemd,udev,dbus,apt,wget,ca-certificates \
    --keyring=/usr/share/keyrings/debian-archive-keyring.gpg "$RELEASE" "$CHROOT"

# Объединяем создание файлов через tee
printf "deb http://deb.debian.org/debian %s main contrib non-free-firmware\ndeb http://deb.debian.org/debian-security/ %s-security main contrib non-free-firmware\ndeb http://deb.debian.org/debian %s-updates main contrib non-free-firmware\n" "$RELEASE" "$RELEASE" "$RELEASE" > "$CHROOT/etc/apt/sources.list"

cat << EOF > "$CHROOT/etc/apt/apt.conf.d/99speedup"
APT::Acquire::Retries "3";
APT::Acquire::{http,ftp}::Timeout "10";
Acquire::Languages "none";
APT::Install-Re{commends,ggests} "false";
DPkg::Options::="--force-conf{def,old}";
EOF

for m in proc sys dev dev/pts run; do mount --bind "/$m" "$CHROOT/$m" 2>/dev/null || mount -t "${m%/}" "${m%/}" "$CHROOT/$m"; done

# Копирование конфигов (объединяем mkdir и cp)
mkdir -p "$CHROOT/etc/systemd/system" "$CHROOT/etc/NetworkManager/system-connections" "$CHROOT/etc/NetworkManager/conf.d"
cp -a configs/system/* "$CHROOT/etc/systemd/system/"
cp configs/nftables.conf "$CHROOT/etc/nftables.conf"
cp configs/*.nmconnection "$CHROOT/etc/NetworkManager/system-connections/"
chmod 0600 "$CHROOT/etc/NetworkManager/system-connections/"*
cp configs/99-custom.conf "$CHROOT/etc/NetworkManager/conf.d/"
cp configs/install_dnsproxy.sh scripts/setup.sh /usr/bin/qemu-aarch64-static "$CHROOT/"

chroot "$CHROOT" /usr/bin/qemu-aarch64-static /bin/sh -c "/setup.sh"

for a in proc sys dev/pts dev run; do umount "$CHROOT/$a"; done

rm -f "$CHROOT/install_dnsproxy.sh" "$CHROOT/setup.sh" "$CHROOT/qemu-aarch64-static"
: > "$CHROOT/root/.bash_history"

echo "$HOST_NAME" > "$CHROOT/etc/hostname"
sed -i "/localhost/ s/$/ $HOST_NAME/" "$CHROOT/etc/hosts"
printf "\n192.168.100.1\t%s\n" "$HOST_NAME" >> "$CHROOT/etc/hosts"

cp -a configs/dhcp.conf "$CHROOT/etc/dnsmasq.d/dhcp.conf"
cp -a configs/rc.local "$CHROOT/etc/rc.local" && chmod +x "$CHROOT/etc/rc.local"
cp -a configs/msm8916-usb-gadget.{sh,conf} "$CHROOT/usr/sbin/" 2>/dev/null || (cp configs/msm8916-usb-gadget.sh "$CHROOT/usr/sbin/" && cp configs/msm8916-usb-gadget.conf "$CHROOT/etc/")

mkdir -p "$CHROOT/etc/hostapd" "$CHROOT/boot/extlinux" "$CHROOT/lib/firmware/msm-firmware-loader"
cp configs/hostapd.conf "$CHROOT/etc/hostapd/"
cp configs/wifi-ap.sh scripts/msm-firmware-loader.sh "$CHROOT/usr/sbin/" && chmod +x "$CHROOT/usr/sbin/wifi-ap.sh"

wget -O - https://github.com/Mio-sha512/openstick-stuff/raw/refs/heads/main/builder-stuff/linux-postmarketos-qcom-msm8916-6.12.1-cpr.apk | tar xkzf - -C "$CHROOT" --exclude=.PKGINFO --exclude=.SIGN* 2>/dev/null

cp configs/extlinux.conf "$CHROOT/boot/extlinux/"
rm -rf "$CHROOT/boot/dtbs/qcom/*" && cp dtbs/* "$CHROOT/boot/dtbs/qcom/"

echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults\t0 2" > "$CHROOT/etc/fstab"
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .

#!/bin/sh -e

CHROOT=${CHROOT:-$(pwd)/rootfs}
RELEASE=${RELEASE:-stable}
HOST_NAME=${HOST_NAME:-openstick}

rm -rf "${CHROOT}"

echo "Using mmdebstrap for fast bootstrap..."
mmdebstrap --arch=arm64 \
    --include=systemd,udev,dbus,apt,ca-certificates \
    --keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
    "${RELEASE}" "${CHROOT}"

cat << EOF > "${CHROOT}/etc/apt/sources.list"
deb http://deb.debian.org/debian ${RELEASE} main contrib non-free-firmware
deb http://deb.debian.org/debian-security ${RELEASE}-security main contrib non-free-firmware
deb http://deb.debian.org/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

echo "nameserver 8.8.8.8" | sudo tee -a ${CHROOT}/etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a ${CHROOT}/etc/resolv.conf

cat << EOF > "${CHROOT}/etc/apt/apt.conf.d/99speedup"
APT::Acquire::Retries "3";
APT::Acquire::http::Timeout "10";
APT::Acquire::ftp::Timeout "10";
Acquire::Languages "none";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
DPkg::Options::="--force-confdef";
DPkg::Options::="--force-confold";
EOF

for dir in proc sys dev dev/pts run; do
    mkdir -p "${CHROOT}/${dir}"
    mount --bind "/${dir}" "${CHROOT}/${dir}"
done

cp configs/install_dnsproxy.sh scripts/setup.sh "${CHROOT}/"

chroot "${CHROOT}" /bin/sh -c "/setup.sh"

mkdir -p "${CHROOT}/etc/systemd/system" \
         "${CHROOT}/etc/NetworkManager/system-connections" \
         "${CHROOT}/etc/NetworkManager/conf.d" \
         "${CHROOT}/etc/hostapd" \
         "${CHROOT}/boot/extlinux" \
         "${CHROOT}/lib/firmware/msm-firmware-loader"

cp -a configs/system/* "${CHROOT}/etc/systemd/system/"
cp configs/*.nmconnection "${CHROOT}/etc/NetworkManager/system-connections/"
cp configs/99-custom.conf "${CHROOT}/etc/NetworkManager/conf.d/"
cp -a configs/rc.local "${CHROOT}/etc/rc.local" 
chmod +x "${CHROOT}/etc/rc.local"
cp -a configs/msm8916-usb-gadget.sh  scripts/msm-firmware-loader.sh "${CHROOT}/usr/sbin/"
cp configs/msm8916-usb-gadget.conf "${CHROOT}/etc/"
chmod 0600 "${CHROOT}/etc/NetworkManager/system-connections/"*

cat > "${CHROOT}/etc/udev/rules.d/99-override-nm-unmanaged.rules" << 'EOF'
ENV{INTERFACE}=="usb0", ENV{NM_UNMANAGED}="0"
EOF

for dir in proc sys dev/pts dev run; do umount "${CHROOT}/${dir}"; done

rm -f "${CHROOT}/install_dnsproxy.sh" "${CHROOT}/setup.sh"
: > "${CHROOT}/root/.bash_history"

echo "${HOST_NAME}" > "${CHROOT}/etc/hostname"
sed -i "/localhost/ s/$/ ${HOST_NAME}/" "${CHROOT}/etc/hosts"
printf "\n192.168.100.1\t%s\n" "${HOST_NAME}" >> "${CHROOT}/etc/hosts"

wget -O - https://github.com/Mio-sha512/openstick-stuff/raw/refs/heads/main/builder-stuff/linux-postmarketos-qcom-msm8916-6.12.1-cpr.apk \
    | tar xkzf - -C "${CHROOT}" --exclude=.PKGINFO --exclude=.SIGN* 2>/dev/null

cp configs/extlinux.conf "${CHROOT}/boot/extlinux/"
rm -rf "${CHROOT}/boot/dtbs/qcom/"*
cp dtbs/* "${CHROOT}/boot/dtbs/qcom/"

echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults\t0 2" > "${CHROOT}/etc/fstab"
tar cpzf rootfs.tgz -C rootfs .

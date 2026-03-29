#!/bin/bash
# MSM8916 USB Gadget - Compact & Robust
GADGET="/sys/kernel/config/usb_gadget/msm8916"
CFG="$GADGET/configs/c.1"
STR="$GADGET/strings/0x409"

# Загрузка конфига и дефолты
[ -f /etc/msm8916-usb-gadget.conf ] && . /etc/msm8916-usb-gadget.conf
: ${USB_VENDOR_ID:="0x1d6b"} ${USB_PRODUCT_ID:="0x0104"} ${UMS_IMAGE:="/root/usb_share.img"}

# Функция очистки (важно для перезапуска)
cleanup() {
    [ -d "$GADGET" ] || return 0
    echo "" > "$GADGET/UDC" 2>/dev/null
    find "$CFG" -maxdepth 1 -type l -delete
    [ -d "$GADGET/os_desc/c.1" ] && rm "$GADGET/os_desc/c.1"
    find "$GADGET/functions" -maxdepth 1 -mindepth 1 -type d -exec rmdir {} + 2>/dev/null
    find "$GADGET" -depth -type d -exec rmdir {} + 2>/dev/null
}

# Генерация MAC (совместимо с dash/sh)
gen_mac() {
    local h=$(echo "$(cat /etc/machine-id)$1" | md5sum | cut -c1-12)
    echo "02:${h:2:2}:${h:4:2}:${h:6:2}:${h:8:2}:${h:10:2}"
}

setup_net() {
    local type=$1 func="$GADGET/functions/$2"
    mkdir -p "$func"
    gen_mac "$type-host" > "$func/host_addr"
    gen_mac "$type-dev" > "$func/dev_addr"
    
    if [ "$type" = "rndis" ]; then
        echo "RNDIS" > "$func/os_desc/interface.rndis/compatible_id"
        echo "5162001" > "$func/os_desc/interface.rndis/sub_compatible_id"
        ln -sf "$CFG" "$GADGET/os_desc/c.1" # Сначала привязка конфига к OS Desc
    fi
    ln -sf "$func" "$CFG" # Потом привязка функции к конфигу
}

cleanup
modprobe libcomposite
mkdir -p "$STR" "$CFG/strings/0x409"

# Основные параметры
echo "$USB_VENDOR_ID" > "$GADGET/idVendor"
echo "$USB_PRODUCT_ID" > "$GADGET/idProduct"
echo "0xEF" > "$GADGET/bDeviceClass"
cat /etc/machine-id | cut -c1-16 > "$STR/serialnumber"
echo "MSM8916" > "$STR/manufacturer"

# Настройка функций
echo 1 > "$GADGET/os_desc/use"
echo "MSFT100" > "$GADGET/os_desc/qw_sign"

[ "$ENABLE_RNDIS" = "1" ] && setup_net "rndis" "rndis.usb0"
[ "$ENABLE_NCM"   = "1" ] && setup_net "ncm"   "ncm.usb0"
[ "$ENABLE_ACM"   = "1" ] && { mkdir -p "$GADGET/functions/acm.GS0"; ln -sf "$GADGET/functions/acm.GS0" "$CFG"; }

if [ "$ENABLE_UMS" = "1" ] && [ -f "$UMS_IMAGE" ]; then
    mkdir -p "$GADGET/functions/mass_storage.0"
    echo "$UMS_IMAGE" > "$GADGET/functions/mass_storage.0/lun.0/file"
    ln -sf "$GADGET/functions/mass_storage.0" "$CFG"
fi

# Активация
UDC=$(ls /sys/class/udc/ | head -n1)
echo "$UDC" > "$GADGET/UDC" || exit 1

# Поднятие сети (через wildcards, чтобы не ждать ifname)
sleep 1
ip link set usb0 up 2>/dev/null || ip link set eth0 up 2>/dev/null

#!/bin/bash
# MSM8916 USB Gadget - Compact & Robust
GADGET="/sys/kernel/config/usb_gadget/msm8916"
CFG="$GADGET/configs/c.1"
STR="$GADGET/strings/0x409"

# Загрузка конфига и дефолты
[ -f /etc/msm8916-usb-gadget.conf ] && . /etc/msm8916-usb-gadget.conf
: ${USB_VENDOR_ID:="0x1d6b"}
: ${USB_PRODUCT_ID:="0x0104"}
: ${USB_DEVICE_VERSION:="0x0100"}
: ${UMS_IMAGE:="/root/usb_share.img"}

# Функция очистки
cleanup() {
    [ -d "$GADGET" ] || return 0
    echo "" > "$GADGET/UDC" 2>/dev/null
    find "$CFG" -maxdepth 1 -type l -delete 2>/dev/null
    [ -d "$GADGET/os_desc/c.1" ] && rm -f "$GADGET/os_desc/c.1" 2>/dev/null
    find "$GADGET/functions" -maxdepth 1 -mindepth 1 -type d -exec rmdir {} + 2>/dev/null
    find "$GADGET/configs" -maxdepth 1 -mindepth 1 -type d -exec rmdir {} + 2>/dev/null
    rmdir "$GADGET/strings/0x409" 2>/dev/null
    rmdir "$GADGET" 2>/dev/null
}

# Генерация MAC
gen_mac() {
    local h=$(echo "$(cat /etc/machine-id 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")$1" | md5sum | cut -c1-12)
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
        ln -sf "$CFG" "$GADGET/os_desc/c.1"
    fi
    ln -sf "$func" "$CFG"
}

cleanup
modprobe libcomposite
mkdir -p "$STR" "$CFG/strings/0x409"

# Основные параметры
echo "$USB_VENDOR_ID" > "$GADGET/idVendor"
echo "$USB_PRODUCT_ID" > "$GADGET/idProduct"
echo "$USB_DEVICE_VERSION" > "$GADGET/bcdDevice"
echo "0xEF" > "$GADGET/bDeviceClass"
echo "0x02" > "$GADGET/bDeviceSubClass"
echo "0x01" > "$GADGET/bDeviceProtocol"

# Строки
serial=$(cat /etc/machine-id 2>/dev/null | cut -c1-16 || echo "0000000000000000")
echo "$serial" > "$STR/serialnumber"
echo "MSM8916" > "$STR/manufacturer"
echo "USB Gadget" > "$STR/product"

# Настройка функций
echo 1 > "$GADGET/os_desc/use"
echo "MSFT100" > "$GADGET/os_desc/qw_sign"

[ "$ENABLE_RNDIS" = "1" ] && setup_net "rndis" "rndis.usb0"
[ "$ENABLE_NCM"   = "1" ] && setup_net "ncm"   "ncm.usb0"
[ "$ENABLE_ECM"   = "1" ] && setup_net "ecm"   "ecm.usb0"
[ "$ENABLE_ACM"   = "1" ] && { mkdir -p "$GADGET/functions/acm.GS0"; ln -sf "$GADGET/functions/acm.GS0" "$CFG"; }

if [ "$ENABLE_UMS" = "1" ]; then
    if [ ! -f "$UMS_IMAGE" ]; then
        echo "Warning: UMS image $UMS_IMAGE not found" >&2
    else
        mkdir -p "$GADGET/functions/mass_storage.0"
        echo "${UMS_READONLY:-0}" > "$GADGET/functions/mass_storage.0/lun.0/ro"
        echo "$UMS_IMAGE" > "$GADGET/functions/mass_storage.0/lun.0/file"
        ln -sf "$GADGET/functions/mass_storage.0" "$CFG"
    fi
fi

# Конфигурация
echo "0xc0" > "$CFG/bmAttributes"
echo "MSM8916 Config" > "$CFG/strings/0x409/configuration"

# Активация
UDC=$(ls /sys/class/udc/ 2>/dev/null | head -n1)
if [ -z "$UDC" ]; then
    echo "ERROR: No UDC device found" >&2
    exit 1
fi
echo "$UDC" > "$GADGET/UDC" || exit 1

# Поднятие сети (читаем реальное имя интерфейса)
sleep 1
if [ "$ENABLE_RNDIS" = "1" ] && [ -f "$GADGET/functions/rndis.usb0/ifname" ]; then
    ifname=$(cat "$GADGET/functions/rndis.usb0/ifname")
    ip link set "$ifname" up 2>/dev/null
elif [ "$ENABLE_ECM" = "1" ] && [ -f "$GADGET/functions/ecm.usb0/ifname" ]; then
    ifname=$(cat "$GADGET/functions/ecm.usb0/ifname")
    ip link set "$ifname" up 2>/dev/null
elif [ "$ENABLE_NCM" = "1" ] && [ -f "$GADGET/functions/ncm.usb0/ifname" ]; then
    ifname=$(cat "$GADGET/functions/ncm.usb0/ifname")
    ip link set "$ifname" up 2>/dev/null
else
    ip link set usb0 up 2>/dev/null || ip link set eth0 up 2>/dev/null
fi

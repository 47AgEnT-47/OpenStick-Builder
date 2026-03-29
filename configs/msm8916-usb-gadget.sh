#!/bin/bash
# MSM8916 USB Gadget - Clean & Readable Version

CONFIG_FILE="/etc/msm8916-usb-gadget.conf"
GADGET_PATH="/sys/kernel/config/usb_gadget/msm8916"

if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Дефолтные настройки
: ${USB_VENDOR_ID:="0x1d6b"}
: ${USB_PRODUCT_ID:="0x0104"}
: ${USB_DEVICE_VERSION:="0x0100"}
: ${USB_MANUFACTURER:="MSM8916"}
: ${USB_PRODUCT:="USB Gadget"}

log() {
    logger -t msm8916-usb-gadget "$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

error() {
    log "ERROR: $*"
    exit 1
}

find_udc() {
    if [ -n "$UDC_DEVICE" ]; then
        echo "$UDC_DEVICE"
    elif [ -e "/sys/class/udc/ci_hdrc.0" ]; then
        echo "ci_hdrc.0"
    else
        ls /sys/class/udc/ | head -1
    fi
}

get_serial() {
    if [ -f /etc/machine-id ]; then
        sha256sum < /etc/machine-id | cut -c1-16
    else
        echo "$(date +%s)-$RANDOM"
    fi
}

gen_mac() {
    local h=$(echo "$(get_serial)$1" | md5sum)
    # Формируем MAC: устанавливаем бит Locally Administered (0x02)
    local b1=$(printf '%02x' $((0x${h:0:2} & 0xfe | 0x02)))
    echo "$b1:${h:2:2}:${h:4:2}:${h:6:2}:${h:8:2}:${h:10:2}"
}

setup_net() {
    local type=$1
    local func="functions/$type.usb0"
    log "Enabling $type"
    
    mkdir -p "$func"
    gen_mac "$type-host" > "$func/host_addr"
    gen_mac "$type-dev" > "$func/dev_addr"
    ln -sf "$func" configs/c.1/

    # Специфичные настройки для Windows RNDIS
    if [ "$type" = "rndis" ]; then
        echo 1 > os_desc/use
        echo MSFT100 > os_desc/qw_sign
        echo RNDIS > "$func/os_desc/interface.rndis/compatible_id"
        echo 5162001 > "$func/os_desc/interface.rndis/sub_compatible_id"
        ln -sf configs/c.1 os_desc
    fi
}

# --- ОСНОВНАЯ ЛОГИКА ---

# Режим OTG Host
if [ "$ENABLE_OTG_HOST" = "1" ]; then
    udc=$(find_udc)
    if [ -n "$udc" ]; then
        echo host > "/sys/class/udc/$udc/device/role"
        log "USB controller set to host mode"
        exit 0
    else
        error "No UDC found for OTG"
    fi
fi

modprobe libcomposite

if ! mountpoint -q /sys/kernel/config; then
    mount -t configfs none /sys/kernel/config
fi

# Подготовка Mass Storage
if [ "$ENABLE_UMS" = "1" ] && [ ! -f "$UMS_IMAGE" ]; then
    mkdir -p "$(dirname "$UMS_IMAGE")"
    truncate -s "${UMS_IMAGE_SIZE:-100M}" "$UMS_IMAGE"
fi

# Создание гаджета
mkdir -p "$GADGET_PATH"
cd "$GADGET_PATH" || error "Cannot access $GADGET_PATH"

echo "$USB_VENDOR_ID" > idVendor
echo "$USB_PRODUCT_ID" > idProduct
echo "$USB_DEVICE_VERSION" > bcdDevice
echo 0xEF > bDeviceClass
echo 0x02 > bDeviceSubClass
echo 0x01 > bDeviceProtocol

mkdir -p strings/0x409 configs/c.1/strings/0x409
get_serial > strings/0x409/serialnumber
echo "$USB_MANUFACTURER" > strings/0x409/manufacturer
echo "$USB_PRODUCT" > strings/0x409/product

CFG_STR=""
HAS_WAKE=0

# Инициализация функций
if [ "$ENABLE_RNDIS" = "1" ]; then
    setup_net "rndis"
    CFG_STR="${CFG_STR}+RNDIS"
    HAS_WAKE=1
fi

if [ "$ENABLE_NCM" = "1" ]; then
    setup_net "ncm"
    CFG_STR="${CFG_STR}+NCM"
    HAS_WAKE=1
fi

if [ "$ENABLE_ECM" = "1" ] && [ "$ENABLE_NCM" != "1" ]; then
    setup_net "ecm"
    CFG_STR="${CFG_STR}+ECM"
    HAS_WAKE=1
fi

if [ "$ENABLE_ACM" = "1" ]; then
    for i in $(seq 0 $((${ACM_COUNT:-1} - 1))); do
        mkdir -p "functions/acm.GS$i"
        ln -sf "functions/acm.GS$i" configs/c.1/
        CFG_STR="${CFG_STR}+ACM"
    done
fi

if [ "$ENABLE_UMS" = "1" ] && [ -f "$UMS_IMAGE" ]; then
    mkdir -p functions/mass_storage.0
    echo "${UMS_READONLY:-0}" > functions/mass_storage.0/lun.0/ro
    echo "$UMS_IMAGE" > functions/mass_storage.0/lun.0/file
    ln -sf functions/mass_storage.0 configs/c.1/
    CFG_STR="${CFG_STR}+UMS"
fi

# Питание и описание конфигурации
if [ "$HAS_WAKE" = "1" ]; then
    echo 0xe0 > configs/c.1/bmAttributes
else
    echo 0xc0 > configs/c.1/bmAttributes
fi

echo "${CFG_STR:1}" > configs/c.1/strings/0x409/configuration

# Активация
UDC_NAME=$(find_udc)
echo "$UDC_NAME" > UDC || error "Failed to enable UDC"

# Поднятие сетевого интерфейса
sleep 1
if [ "$ENABLE_RNDIS" = "1" ] && [ -f functions/rndis.usb0/ifname ]; then
    ip link set "$(cat functions/rndis.usb0/ifname)" up
fi

log "USB Gadget setup complete"

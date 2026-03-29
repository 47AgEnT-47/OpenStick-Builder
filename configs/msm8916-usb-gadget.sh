#!/bin/bash
CONFIG_FILE="/etc/msm8916-usb-gadget.conf"
GADGET_PATH="/sys/kernel/config/usb_gadget/msm8916"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Defaults
: ${USB_VENDOR_ID:="0x1d6b"} ${USB_PRODUCT_ID:="0x0104"} ${USB_DEVICE_VERSION:="0x0100"} ${USB_MANUFACTURER:="MSM8916"} ${USB_PRODUCT:="USB Gadget"}

log() { logger -t msm8916-usb-gadget "$*"; echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
error() { log "ERROR: $*"; exit 1; }

find_udc() {
    [ -n "$UDC_DEVICE" ] && echo "$UDC_DEVICE" && return
    [ -e "/sys/class/udc/ci_hdrc.0" ] && echo "ci_hdrc.0" || ls /sys/class/udc/ | head -1
}

get_serial() {
    [ -f /etc/machine-id ] && sha256sum < /etc/machine-id | cut -c1-16 || echo "$(date +%s)-$RANDOM"
}

gen_mac() {
    local h=$(echo "$(get_serial)$1" | md5sum)
    echo "$(printf '%02x' $((0x${h:0:2} & 0xfe | 0x02))):${h:2:2}:${h:4:2}:${h:6:2}:${h:8:2}:${h:10:2}"
}

setup_net() {
    local name=$1 func="functions/$2.usb0"
    log "Enabling $name"
    mkdir -p "$func"
    gen_mac "$2-host" > "$func/host_addr"
    gen_mac "$2-dev" > "$func/dev_addr"
    ln -sf "$func" configs/c.1/
    [ "$2" = "rndis" ] && {
        echo 1 > os_desc/use; echo MSFT100 > os_desc/qw_sign
        echo RNDIS > "$func/os_desc/interface.rndis/compatible_id"
        echo 5162001 > "$func/os_desc/interface.rndis/sub_compatible_id"
        ln -sf configs/c.1 os_desc
    }
}

teardown_gadget() {
    log "Tearing down gadget"
    [ ! -d "$GADGET_PATH" ] && return
    cd "$GADGET_PATH"
    echo "" > UDC 2>/dev/null
    rm -f configs/c.1/*.usb0 configs/c.1/*.GS* os_desc/c.1 2>/dev/null
    find configs/c.1/strings/0x409 strings/0x409 functions -mindepth 1 -type d -delete 2>/dev/null
    find . -mindepth 1 -maxdepth 1 -type d -delete 2>/dev/null
}

# MAIN LOGIC
if [ "$ENABLE_OTG_HOST" = "1" ]; then
    teardown_gadget
    udc=$(find_udc)
    echo host > "/sys/class/udc/$udc/device/role" && log "Host mode set" || error "OTG fail"
    exit 0
fi

modprobe libcomposite
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
[ "$ENABLE_UMS" = "1" ] && [ ! -f "$UMS_IMAGE" ] && {
    mkdir -p "$(dirname "$UMS_IMAGE")"
    truncate -s "${UMS_IMAGE_SIZE:-100M}" "$UMS_IMAGE" || dd if=/dev/zero of="$UMS_IMAGE" bs=1M count=${UMS_IMAGE_SIZE%M}
}

mkdir -p "$GADGET_PATH" && cd "$GADGET_PATH" || error "Path fail"
echo "$USB_VENDOR_ID" > idVendor; echo "$USB_PRODUCT_ID" > idProduct; echo "$USB_DEVICE_VERSION" > bcdDevice
echo 0xEF > bDeviceClass; echo 0x02 > bDeviceSubClass; echo 0x01 > bDeviceProtocol
mkdir -p strings/0x409 configs/c.1/strings/0x409
get_serial > strings/0x409/serialnumber; echo "$USB_MANUFACTURER" > strings/0x409/manufacturer; echo "$USB_PRODUCT" > strings/0x409/product

CFG_STR=""
[ "$ENABLE_RNDIS" = "1" ] && { setup_net "RNDIS" "rndis"; CFG_STR="+RNDIS"; WAKE=1; }
[ "$ENABLE_NCM" = "1" ] && { setup_net "NCM" "ncm"; CFG_STR="$CFG_STR+NCM"; WAKE=1; }
[ "$ENABLE_ECM" = "1" ] && [ "$ENABLE_NCM" != "1" ] && { setup_net "ECM" "ecm"; CFG_STR="$CFG_STR+ECM"; WAKE=1; }

if [ "$ENABLE_ACM" = "1" ]; then
    for i in $(seq 0 $((${ACM_COUNT:-1} - 1))); do
        mkdir -p "functions/acm.GS$i"; ln -sf "functions/acm.GS$i" configs/c.1/
        CFG_STR="$CFG_STR+ACM"
    done
fi

[ "$ENABLE_UMS" = "1" ] && [ -f "$UMS_IMAGE" ] && {
    mkdir -p functions/mass_storage.0
    echo "${UMS_READONLY:-0}" > functions/mass_storage.0/lun.0/ro
    echo "$UMS_IMAGE" > functions/mass_storage.0/lun.0/file
    ln -sf functions/mass_storage.0 configs/c.1/
    CFG_STR="$CFG_STR+UMS"
}

[ "$WAKE" = "1" ] && echo 0xe0 > configs/c.1/bmAttributes || echo 0xc0 > configs/c.1/bmAttributes
echo "${CFG_STR:1}" > configs/c.1/strings/0x409/configuration

UDC_DEV=$(find_udc)
echo "$UDC_DEV" > UDC || error "UDC fail"
sleep 1
[ "$ENABLE_RNDIS" = "1" ] && [ -f functions/rndis.usb0/ifname ] && ip link set "$(cat functions/rndis.usb0/ifname)" up

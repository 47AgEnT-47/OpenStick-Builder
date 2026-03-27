#!/bin/bash

INTERFACE="wlan0"

start_ap() {
    echo "Starting WiFi AP..."
    ip link set $INTERFACE up
    systemctl start hostapd
    echo "WiFi AP started"
}

stop_ap() {
    echo "Stopping WiFi AP..."
    systemctl stop hostapd
    echo "WiFi AP stopped"
}

status_ap() {
    systemctl status hostapd
}

case "$1" in
    start|stop|restart|status) "$1"_ap ;;
    *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac

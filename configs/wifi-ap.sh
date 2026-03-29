#!/bin/bash
nmcli connection delete hotspot 2>/dev/null
nmcli connection add type wifi ifname wlan0 con-name hotspot autoconnect yes ssid "4G-UFI-XX" mode ap
nmcli connection modify hotspot 802-11-wireless-security.key-mgmt wpa-psk
nmcli connection modify hotspot 802-11-wireless-security.psk "12345678"
nmcli connection modify hotspot ipv4.method shared
nmcli connection up hotspot

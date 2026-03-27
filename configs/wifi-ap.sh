#!/bin/bash
systemctl stop wpa_supplicant
systemctl mask wpa_supplicant
systemctl unmask hostapd
nmcli con down wlan0 2>/dev/null
nmcli dev set wlan0 managed no
systemctl start hostapd

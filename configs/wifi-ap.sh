#!/bin/bash
systemctl stop wpa_supplicant
nmcli con down wlan0 2>/dev/null
nmcli dev set wlan0 managed no
systemctl start hostapd

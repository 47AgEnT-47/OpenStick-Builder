#!/bin/bash
systemctl stop hostapd
systemctl mask hostapd
systemctl unmask wpa_supplicant
systemctl start wpa_supplicant
nmcli dev set wlan0 managed yes
nmcli con up wlan0

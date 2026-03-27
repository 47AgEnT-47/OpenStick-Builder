#!/bin/bash
systemctl stop hostapd
nmcli dev set wlan0 managed yes
nmcli con up wlan0

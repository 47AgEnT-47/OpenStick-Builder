#!/bin/bash
nmcli connection delete hotspot 2>/dev/null
nmcli device wifi connect "HONOR X8c" password "12345678" ifname wlan0

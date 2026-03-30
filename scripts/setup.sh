#!/bin/sh -e

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true

# Faster apt configuration
echo 'force-confdef' >> /etc/dpkg/dpkg.cfg
echo 'force-confold' >> /etc/dpkg/dpkg.cfg

# Настройка локалей и timezone
echo 'tzdata tzdata/Areas select Asia' | debconf-set-selections
echo 'tzdata tzdata/Zones/Asia select Novosibirsk' | debconf-set-selections
echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
rm -f "/etc/locale.gen"

# Установка пакетов
apt update -qqy
apt upgrade -qqy --with-new-pkgs
apt install -qqy --no-install-recommends \
    libconfig-dev \
    libc6-dev \
    linux-libc-dev \
    libconfig11 \
    locales \
    modemmanager \
    netcat-traditional \
    network-manager \
    openssh-server \
    qrtr-tools \
    rmtfs \
    sudo \
    systemd-timesyncd \
    tzdata \
    wpasupplicant \
    bash-completion \
    curl \
    ca-certificates \
    zram-tools \
    mobile-broadband-provider-info \
    iw \
    rfkill \

# Очистка
apt autoremove -qqy
apt clean
rm -rf /var/lib/apt/lists/*
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id
rm /etc/ssh/ssh_host_*
find /var/log -type f -delete

# Настройка пользователей
passwd -dl root

adduser --disabled-password --comment "" user
echo "user:1" | chpasswd
usermod -aG sudo user

# Алиасы
cat <<EOF >>/etc/bash.bashrc

alias ls='ls --color=auto -lh'
alias ll='ls --color=auto -lhA'
alias l='ls --color=auto -l'
alias cl='clear'
alias ip='ip --color'
alias free='free -h'
alias df='df -h'
alias du='du -hs'

EOF

# Настройка journald
cat <<EOF >> /etc/systemd/journald.conf
SystemMaxUse=100M
SystemKeepFree=1G
EOF

# Установка dnsproxy
bash /install_dnsproxy.sh systemd

# Включение сервисов
systemctl enable NetworkManager || true
systemctl enable systemd-resolved || true
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

systemctl enable ModemManager
systemctl enable systemd-timesyncd
systemctl enable wpa_supplicant

systemctl mask systemd-networkd
systemctl mask systemd-networkd-wait-online.service

# Отключаем выключение по кнопке питания
sed -i 's/^#HandlePowerKey=poweroff/HandlePowerKey=ignore/' /etc/systemd/logind.conf

# Настройка sysctl
cat <<EOF > /etc/sysctl.conf
net.ipv4.ip_forward=1
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF

# Настройка SSH
sed -i 's/^#ListenAddress 0.0.0.0/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config
systemctl enable ssh

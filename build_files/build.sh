#!/bin/bash
set -ouex pipefail

cat >/etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

curl -fsSL https://repository.mullvad.net/rpm/stable/mullvad.repo -o /etc/yum.repos.d/mullvad.repo

# Helium's official Fedora repo
dnf5 -y copr enable imput/helium

# /opt -> /var/opt on atomic images; make it exist for RPM scriptlets
mkdir -p /var/opt

dnf5 install -y kitty helium-bin 1password 1password-cli mullvad-vpn ripgrep

dnf5 -y copr disable imput/helium

# Move /opt payloads into the immutable image, link them back at boot
mkdir -p /usr/lib/opt
for d in /var/opt/*; do
  [ -e "$d" ] || continue
  name=$(basename "$d")
  mv "$d" "/usr/lib/opt/$name"
  echo "L+ \"/var/opt/$name\" - - - - /usr/lib/opt/$name" >>/usr/lib/tmpfiles.d/optfix.conf
done

# 1Password: pin the group GID so the browser helper keeps its setgid group
groupmod -g 1500 onepassword
echo "g onepassword 1500" >/usr/lib/sysusers.d/onepassword.conf
chgrp 1500 /usr/lib/opt/1Password/1Password-BrowserSupport
chmod 2755 /usr/lib/opt/1Password/1Password-BrowserSupport

groupmod -g 1600 onepassword-cli
echo "g onepassword-cli 1600" >/usr/lib/sysusers.d/onepassword-cli.conf
chgrp 1600 /usr/bin/op
chmod 2755 /usr/bin/op

# 1Password: trust Helium and let the Helium extension reach the desktop app
mkdir -p /etc/1password
echo "helium" >/etc/1password/custom_allowed_browsers
chmod 755 /etc/1password/custom_allowed_browsers

for hostdir in /etc/net.imput.helium/native-messaging-hosts /etc/helium/native-messaging-hosts; do
  mkdir -p "$hostdir"
  cat >"$hostdir/com.1password.1password.json" <<'EOF'
{
  "name": "com.1password.1password",
  "description": "1Password BrowserSupport",
  "path": "/opt/1Password/1Password-BrowserSupport",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
  ]
}
EOF
done

# GloriousEggroll's Widevine helper, placed the same way his own package does it
curl -fsSL https://github.com/GloriousEggroll/chromium-widevine-helper/archive/refs/heads/main.tar.gz | tar -xz -C /tmp
src=/tmp/chromium-widevine-helper-main

install -Dm755 "$src/helper/chromium-widevine" /usr/libexec/chromium-widevine/chromium-widevine
ln -sf /usr/libexec/chromium-widevine/chromium-widevine /usr/bin/chromium-widevine

mkdir -p /usr/share/chromium-widevine/extension
cp -a "$src/extension/." /usr/share/chromium-widevine/extension/

for hostdir in /etc/net.imput.helium/native-messaging-hosts /etc/helium/native-messaging-hosts; do
  install -Dm644 "$src/helper/chromium-widevine-native-host.json" "$hostdir/org.chromium.widevine.json"
done

rm -rf "$src"

systemctl enable mullvad-daemon

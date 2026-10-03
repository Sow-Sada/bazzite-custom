#!/bin/bash
set -ouex pipefail

cat >/etc/yum.repos.d/mozilla.repo <<'EOF'
[mozilla]
name=Mozilla Packages
baseurl=https://packages.mozilla.org/rpm/firefox
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.mozilla.org/rpm/firefox/signing-key.gpg
EOF

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

# /opt -> /var/opt on atomic images; make it exist for RPM scriptlets
mkdir -p /var/opt

dnf5 install -y kitty firefox-nightly 1password 1password-cli mullvad-vpn ripgrep
# Move /opt payloads into the immutable image, link them back at boot
mkdir -p /usr/lib/opt
for d in /var/opt/*; do
  [ -e "$d" ] || continue
  name=$(basename "$d")
  mv "$d" "/usr/lib/opt/$name"
  echo "L+ \"/var/opt/$name\" - - - - \"/usr/lib/opt/$name\"" >>/usr/lib/tmpfiles.d/optfix.conf
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

systemctl enable mullvad-daemon

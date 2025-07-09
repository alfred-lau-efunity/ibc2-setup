#!/bin/bash

set -e  # Exit on any error

sudo su
apt update
apt install inotify-tools ffmpeg

systemctl stop davConvert.service
systemctl disable davConvert.service

rm /etc/systemd/system/davConvert.service
systemctl daemon-reload && sudo systemctl reset-failed

rm /tmp/davConvert.lock
rm /usr/local/bin/davConvert.sh

curl -fsSL https://raw.githubusercontent.com/alfred-lau-efunity/ibc2-setup/refs/heads/main/dav-setup.sh?v=20250708 | bash
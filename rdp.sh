#!/bin/bash

set -e  # Exit on any error

sudo apt install xrdp -y
sudo apt install xfce4 xfce4-session -y
echo "xfce4-session" > /home/user/.xsession
sudo apt install ubuntu-desktop -y
 
sudo systemctl enable --now xrdp
 
sudo systemctl restart xrdp
sudo ufw allow 3389/tcp

echo "✅ RDP set up"
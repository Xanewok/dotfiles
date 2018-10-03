#!/bin/bash

# Reset to Xubuntu defaults:
#cp -r /etc/xdg/xdg-xubuntu/* .

sudo apt install arc-theme papirus-icon-theme
xfconf-query -c xfwm4 -p /general/theme -s "Arc-Dark"
xfconf-query -c xsettings -p /Net/ThemeName -s "Arc-Dark"
xfconf-query -c xsettings -p /Net/IconThemeName -s Papirus
# Background
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/image-style -n -t int -s 0

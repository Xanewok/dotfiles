#!/bin/bash

sudo apt-get install git gcc make libx11-dev libxtst-dev pkg-config

git clone https://github.com/hanschen/ksuperkey.git
cd ksuperkey
make
sudo make install

cp KSUPERKEY.desktop ~/.config/autostart/KSUPERKEY.desktop

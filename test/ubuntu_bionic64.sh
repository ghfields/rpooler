#!/bin/bash
set -eux

apt-get install -y zfsutils
apt-get install -y debootstrap gdisk zfs-initramfs

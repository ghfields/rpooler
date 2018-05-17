# Rpooler
## A ZFS rpool wrapper for the Ubuntu 18.04 Ubiquity Installer
This is a wrapper that automates the creation of a fully bootable zfs rpool with Ubuntu 18.04 installed.  It was crafted off the setep-by-step [HOWTO install Ubuntu 18.04 to a Whole Disk Native ZFS Root Filesystem using Ubiquity GUI installer](https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-Ubuntu-18.04-to-a-Whole-Disk-Native-ZFS-Root-Filesystem-using-Ubiquity-GUI-installer).  The goals are to further simplfy the installation process and encourage best practices through the guided process.

Instructions:
1) Boot Ubuntu 18.04 Desktop Live CD
2) Select "Try Ubuntu"
3) Open terminal (Ctrl+Alt+t)
4) wget https://raw.githubusercontent.com/ghfields/rpooler/master/rpooler.sh
5) chmod +x rpooler.sh
6) sudo su
7) ./rpooler.sh

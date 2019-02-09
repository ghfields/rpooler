# About

zfs-install automates the creation of a fully bootable zfs root pool.

Original forked from rpooler with all work "upstreamed", thanks Garrett !

## Roadmap
This project is in developement and unstable, please use rpooler in meantime.

Please see wiki for general state of the project

## zfs documentation

aaron-toponce [General zfs introduction and guidelines](https://pthree.org/2012/04/17/install-zfs-on-debian-gnulinux/)

## zfsonlinux community documentation for specific distributions.

ubuntu-ubiquity [HOWTO install Ubuntu 18.04 to a Whole Disk Native ZFS Root Filesystem using Ubiquity GUI installer](https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-Ubuntu-18.04-to-a-Whole-Disk-Native-ZFS-Root-Filesystem-using-Ubiquity-GUI-installer).

## Goals
- Simplfy the installation process to the point of automation.
- Upstream and intergrate as is "legally" possible. I wish this script wasn't required.
- Encourage best practices through the guides practices.

## Supported distributions
Currently only ubuntu using the ubiquity installer is the only option.

- ubuntu-ubiquity

TODO
- ubuntu-debootstrap
- arch
- gentoo
- debian
- rhel
- centos
- opensuse
- linuxfromscratch

## Instructions
1) Boot supported distribtion
2) run zfs-install.sh
3) follow normal install process
4) need to confirm zfs disk!

## Contributions
Any and all contibutions in any form are encouraged and most welcome.

There doesn't appear to be many people interested in this project, thats cool!
I would appreciate the time of any other zfs users. 

What method do you use to "bootstrap" zfs for your use case ?

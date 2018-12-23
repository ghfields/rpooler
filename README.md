# Rpooler
## A ZFS rpool wrapper for the Ubuntu 18.04 Ubiquity Installer
This is a wrapper that automates the creation of a fully bootable zfs root pool with Ubuntu 18.04 installed.  It was crafted off the step-by-step [HOWTO install Ubuntu 18.04 to a Whole Disk Native ZFS Root Filesystem using Ubiquity GUI installer](https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-Ubuntu-18.04-to-a-Whole-Disk-Native-ZFS-Root-Filesystem-using-Ubiquity-GUI-installer).  The goals are to further simplfy the installation process and encourage best practices through the guided process.

Instructions:
1) Boot Ubuntu 18.04 Desktop Live CD
2) Select "Try Ubuntu"
3) Open terminal (Ctrl+Alt+t)
4) `wget https://raw.github.com/ghfields/rpooler/master/rpooler.sh`
5) `sudo bash rpooler.sh`


## What to expect when running script
```
Installer script for ZFS whole disk installation using Ubuntu GUI (Ubiquity)
----------------------------------------------------------------------------
 What do you want to name your pool?  
rpool

These are the drives on your system:
 	 /dev/disk/by-id/ata-VBOX_CD-ROM_VB2-01700376
 	 /dev/disk/by-id/ata-VBOX_HARDDISK_VB9c4c6292-31c83b83
 What vdev layout do you want to use? (hint: tab completion works):  
/dev/disk/by-id/ata-VBOX_HARDDISK_VB9c4c6292-31c83b83

 Which zpool & zfs options do you wish to set at creation?  
-o feature@multi_vdev_crash_dump=disabled -o feature@large_dnode=disabled -o feature@sha512=disabled -o feature@skein=disabled -o feature@edonr=disabled -o ashift=12 -O atime=off -O compression=lz4 -O normalization=formD -O recordsize=1M -O xattr=sa

Zpool would create 'rpool' with the following layout:

	rpool
	  ata-VBOX_HARDDISK_VB9c4c6292-31c83b83

 Does this look correct (y/n): 
y

The Ubiquity made swapfile will not function and will be removed.
Based on your system's 3.85 GB of RAM, Ubuntu suggests a swap of 2 GB.
 What size, in GB, should the created swap zvol be? (0 for none):  
2
Zvol swap size: 2 GB
 Is this correct (y/n): 
y

Configuring the Ubiquity Installer
----------------------------------
 	 1) Choose any options you wish until you get to the 'Installation Type' screen.
 	 2) Select 'Erase disk and install Ubuntu' and click 'Continue'.
 	 3) Change the 'Select drive:' dropdown to '/dev/zd0 - 10.7 GB Unknown' and click 'Install Now'.
 	 4) A popup summarizes your choices and asks 'Write the changes to disks?'. Click 'Continue'.
 	 5) At this point continue through the installer normally.
 	 6) Finally, a message comes up 'Installation Complete'. Click the 'Continue Testing'.
 	 This install script will continue.

Press any key to launch Ubiquity. These instructions will remain visible in the terminal window.


======
Ubiquity Launches
======

(Rsync output truncated)

Setting up zfs-initramfs (0.7.5-1ubuntu16.2) ...
Processing triggers for libc-bin (2.27-3ubuntu1) ...
Processing triggers for initramfs-tools (0.130ubuntu3.1) ...
update-initramfs: Generating /boot/initrd.img-4.15.0-29-generic
cp: memory exhausted
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-4.15.0-29-generic
Found initrd image: /boot/initrd.img-4.15.0-29-generic
Found memtest86+ image: /ROOT/ubuntu-1@/boot/memtest86+.elf
Found memtest86+ image: /ROOT/ubuntu-1@/boot/memtest86+.bin
done
Warning: The kernel is still using the old partition table.
The new table will be used at the next reboot or after you
run partprobe(8) or kpartx(8)
The operation has completed successfully.
Installing for i386-pc platform.
Installation finished. No error reported.
 Would you like to create a snapshot before rebooting? :  
y

Script complete.  Please reboot your computer to boot into your installation.
If first boot hangs, reset computer and try boot again.

 Do you want to restart now?  
n
```

#!/bin/bash
echo ""
echo "Installer script for ZFS whole disk installation using Ubuntu GUI (Ubiquity)"
echo "----------------------------------------------------------------------------" 
if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
fi
read -p "What do you want to name your pool? " -i "rpool" -e POOL
## read -p "Where on the pool do you want your OS installed? " -i "ROOT/ubuntu-1" -e FILESYSTEM  (TODO: Need to parse and feed to 'zpool create')
echo ""
echo "These are the drives on your system:"
for i in $(ls /dev/disk/by-id/ -a |grep -v part |awk '{if(NR>2)print}');do echo -e ' \t' "/dev/disk/by-id/"$i;done
read -p "What vdev layout do you want to use? (hint: tab completion works): " -e LAYOUT
echo ""
read -p "Which zpool & zfs options do you wish to set at creation? " -i "-o ashift=12 -O atime=off -O compression=lz4 -O normalization=formD -O recordsize=1M -O xattr=sa" -e OPTIONS

while true; do
    read -p "Ubiquity made swapfile is removed.  Want to use a swap zvol (size: 4GB)?" yn
    case $yn in
        [Yy]* ) SWAPZVOL=4; break;;
        [Nn]* ) SWAPZVOL=0; break;;
        * ) echo "Please answer yes or no.";;
    esac
done


read -p "Provide an IP of a nameserver available on your network: " -i "8.8.8.8" -e NAMESERVER
DRIVES="$(echo $LAYOUT | sed 's/\S*\(mirror\|raidz\|log\|spare\|cache\)\S*//g')"

apt install -y zfsutils
zpool create -f $OPTIONS $POOL $LAYOUT
zfs create -V 10G $POOL/ubuntu-temp

echo ""
echo "Configuring the Ubiquity Installer"
echo "----------------------------------"
echo -e ' \t' "1) Choose any options you wish until you get to the 'Installation Type' screen."
echo -e ' \t' "2) Select 'Erase disk and install Ubuntu' and click 'Continue'."
echo -e ' \t' "3) Change the 'Select drive:' dropdown to '/dev/zd0 - 10.7 GB Unknown' and click 'Install Now'."
echo -e ' \t' "4) A popup summarizes your choices and asks 'Write the changes to disks?'. Click 'Continue'."
echo -e ' \t' "5) At this point continue through the installer normally."
echo -e ' \t' "6) Finally, a message comes up 'Installation Complete'. Click the 'Continue Testing'." 
echo -e ' \t' "This install script will continue."
echo ""
read -p "Press any key to launch Ubiquity. These instructions will remain visible in the terminal window."

ubiquity --no-bootloader

zfs create $POOL/ROOT
zfs create $POOL/ROOT/ubuntu-1

if [[ $SWAPZVOL -ne 0 ]]; then
fi


rsync -avPX /target/. /$POOL/ROOT/ubuntu-1/.

for d in proc sys dev; do mount --bind /$d /$POOL/ROOT/ubuntu-1/$d; done

#nano /etc/fstab         ## comment out the lines for the mountpoint "/" and "/swapfile" and exit
#sudo sed -i -e 's,^/ ,#/ ,' /etc/fstab  #Reddit take to comment out / line. Need to repeat for swapfile

echo "nameserver " $NAMESERVER | tee -a /$POOL/ROOT/ubuntu-1/etc/resolv.conf
sed -e '/\s\/\s/ s/^#*/#/' -i /$POOL/ROOT/ubuntu-1/etc/fstab  #My take at comment out / line.
sed -e '/\sswap\s/ s/^#*/#/' -i /$POOL/ROOT/ubuntu-1/etc/fstab #My take at comment out swap line.

if [[ $SWAPZVOL -ne 0 ]]; then
     zfs create create -V "$SWAPZVOL"G -b $(getconf PAGESIZE) -o compression=zle \
      -o logbias=throughput -o sync=always \
      -o primarycache=metadata -o secondarycache=none \
      -o com.sun:auto-snapshot=false $POOL/swap
     mkswap -f /dev/zvol/$POOL/swap
     echo RESUME=none > /$POOL/ROOT/ubuntu-1/etc/initramfs-tools/conf.d/resume
     echo /dev/zvol/rpool/swap none swap defaults 0 0 >> /$POOL/ROOT/ubuntu-1/etc/fstab
fi

chroot /$POOL/ROOT/ubuntu-1 apt update
chroot /$POOL/ROOT/ubuntu-1 apt install -y zfs-initramfs
chroot /$POOL/ROOT/ubuntu-1 update-grub
for i in $DRIVES; do chroot /$POOL/ROOT/ubuntu-1 sgdisk -a1 -n2:512:2047 -t2:EF02 $i;chroot /$POOL/ROOT/ubuntu-1 grub-install $i;done
rm /$POOL/ROOT/ubuntu-1/swapfile

umount -R /$POOL/ROOT/ubuntu-1
zfs set mountpoint=/ $POOL/ROOT/ubuntu-1
zfs snapshot $POOL/ROOT/ubuntu-1@pre-reboot
swapoff -a
umount /target
zfs destroy $POOL/ubuntu-temp
zpool export $POOL
echo ""
echo "Script complete.  Please reboot your computer to boot into your installation."
echo "If first boot hangs, reset computer and try boot again."
#shutdown -r 0
exit 0

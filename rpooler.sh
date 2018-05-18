#!/bin/bash
echo ""
echo "Installer script for ZFS whole disk installation using Ubuntu GUI (Ubiquity)"
echo "----------------------------------------------------------------------------" 
if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
fi
read -p "What do you want to name your pool? " -i "rpool" -e pool
echo ""
echo "These are the drives on your system:"
for i in $(ls /dev/disk/by-id/ -a |grep -v part |awk '{if(NR>2)print}');do echo -e ' \t' "/dev/disk/by-id/"$i;done
read -p "What vdev layout do you want to use? (hint: tab completion works): " -e layout
echo ""
read -p "Which zpool & zfs options do you wish to set at creation? " -i "-o ashift=12 -O atime=off -O compression=lz4 -O normalization=formD -O recordsize=1M -O xattr=sa" -e options

systemramk=$(free -m | awk '/^Mem:/{print $2}')
systemramg=$(echo "scale=2; $systemramk/1024" | bc)
suggestswap=$(printf %.$2f $(echo "scale=2; sqrt($systemramk/1024)" | bc))
echo ""
echo "The Ubiquity made swapfile will not function and will be removed."
echo "Based on your system's $systemramg GB of RAM, Ubuntu suggests a swap of $suggestswap GB."
read -p "What size, in GB, should the created swap zvol be? (0 for none): " -e -i $suggestswap swapzvol

drives="$(echo $layout | sed 's/\S*\(mirror\|raidz\|log\|spare\|cache\)\S*//g')"

apt install -y zfsutils
zpool create -f $options $pool $layout
zfs create -V 10G $pool/ubuntu-temp

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

zfs create $pool/ROOT
zfs create $pool/ROOT/ubuntu-1
rsync -avPX /target/. /$pool/ROOT/ubuntu-1/.

for d in proc sys dev; do mount --bind /$d /$pool/ROOT/ubuntu-1/$d; done

cp /etc/resolv.conf /$pool/ROOT/ubuntu-1/etc/resolv.conf
sed -e '/\s\/\s/ s/^#*/#/' -i /$pool/ROOT/ubuntu-1/etc/fstab  #My take at comment out / line.
sed -e '/\sswap\s/ s/^#*/#/' -i /$pool/ROOT/ubuntu-1/etc/fstab #My take at comment out swap line.

if [[ $swapzvol -ne 0 ]]; then
     zfs create -V "$swapzvol"G -b $(getconf PAGESIZE) -o compression=zle \
      -o logbias=throughput -o sync=always \
      -o primarycache=metadata -o secondarycache=none \
      -o com.sun:auto-snapshot=false $pool/swap
     mkswap -f /dev/zvol/$pool/swap
     echo RESUME=none > /$pool/ROOT/ubuntu-1/etc/initramfs-tools/conf.d/resume
     echo /dev/zvol/$pool/swap none swap defaults 0 0 >> /$pool/ROOT/ubuntu-1/etc/fstab
fi

chroot /$pool/ROOT/ubuntu-1 apt update
chroot /$pool/ROOT/ubuntu-1 apt install -y zfs-initramfs
chroot /$pool/ROOT/ubuntu-1 update-grub
for i in $drives; do chroot /$pool/ROOT/ubuntu-1 sgdisk -a1 -n2:512:2047 -t2:EF02 $i;chroot /$pool/ROOT/ubuntu-1 grub-install $i;done
rm /$pool/ROOT/ubuntu-1/swapfile

umount -R /$pool/ROOT/ubuntu-1
zfs set mountpoint=/ $pool/ROOT/ubuntu-1

while true; do
    read -p "Would you like to create a snapshot before rebooting?: " -i "y" yn
    case $yn in
        [Yy]* ) zfs snapshot $pool/ROOT/ubuntu-1@pre-reboot; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac

done
zfs snapshot $pool/ROOT/ubuntu-1@pre-reboot
swapoff -a
umount /target
zfs destroy $pool/ubuntu-temp
zpool export $pool
echo ""
echo "Script complete.  Please reboot your computer to boot into your installation."
echo "If first boot hangs, reset computer and try boot again."
echo ""

while true; do
    read -p "Do you want to restart now?" yn
    case $yn in
        [Yy]* ) shutdown -r 0; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac

done
exit 0

#!/bin/bash
green='\e[92m'
nocolor='\e[0m'
echo ""
echo "Installer script for ZFS whole disk installation using Ubuntu GUI (Ubiquity)"
echo "----------------------------------------------------------------------------" 

distver=$(lsb_release -cs)
if [ "$distver" != "bionic" ]; then
     echo "This script requires Ubuntu 18.04 to run."
     exit 1
fi

if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
fi

if !(apt update &> /dev/null && apt install -y zfsutils &> /dev/null); then
    echo "Error installing zfsutils from the internet.  Please check your connection."
    exit 1
fi

while [[ $exitpoolselect == "" ]]; do
     echo -e $green "What do you want to name your pool? " $nocolor
     read -i "rpool" -e pool
     echo ""
     echo "These are the drives on your system:"
     for i in $(ls /dev/disk/by-id/ -a |grep -v part |awk '{if(NR>2)print}');do echo -e ' \t' "/dev/disk/by-id/"$i;done
     echo -e $green "What vdev layout do you want to use? (hint: tab completion works): " $nocolor
     read -e layout
     echo ""
     echo -e $green "Which zpool & zfs options do you wish to set at creation? " $nocolor
     read -i "-o feature@multi_vdev_crash_dump=disabled -o feature@large_dnode=disabled -o feature@sha512=disabled -o feature@skein=disabled -o feature@edonr=disabled -o ashift=12 -O atime=off -O compression=lz4 -O normalization=formD -O recordsize=1M -O xattr=sa" -e options
     echo ""
     echo -n "Zpool "
     if (zpool create -nf $options $pool $layout); then 
          echo ""
          while true; do
               echo -e $green "Does this look correct (y/n):" $nocolor
               read -i "y" -e yn
               case $yn in
                    [Yy]* ) exitpoolselect="1"; break;;
                    [Nn]* ) break;;
                    * ) echo "Please answer yes or no.";;
               esac
          done
     else
          echo ""
          echo "Your selections formed an invalid "zpool create" commmand.  Please try again."
     fi
done


systemramk=$(free -m | awk '/^Mem:/{print $2}')
systemramg=$(echo "scale=2; $systemramk/1024" | bc)
suggestswap=$(printf %.$2f $(echo "scale=2; sqrt($systemramk/1024)" | bc))

while [[ $exitfilesystemselect == "" ]]; do
     echo ""
     echo "The Ubiquity made swapfile will not function and will be removed."
     echo "Based on your system's $systemramg GB of RAM, Ubuntu suggests a swap of $suggestswap GB."
     echo -e $green "What size, in GB, should the created swap zvol be? (0 for none): " $nocolor
     read -e -i $suggestswap swapzvol
     echo "Zvol swap size: $swapzvol GB"
     while true; do
          echo -e $green "Is this correct (y/n):" $nocolor
          read -i "y" -e yn
          case $yn in
             [Yy]* ) exitfilesystemselect="1"; break;;
             [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
     esac
    done
done

if !(zpool create -f $options $pool $layout); then
    echo "Error creating zpool.  Terminating Script."
    exit 1
fi

if !(zfs create -V 10G $pool/ubuntu-temp); then
     echo "Error creating ZVOL.  Terminating Script."
     exit 1
fi

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

if !(ubiquity --no-bootloader); then
     echo "Ubiquity Installer failed to complete.  Terminating Script."
     exit 1
fi

while [[ $exitrootselect == "" ]]; do
     echo -e $green "Where on your pool do you want your root dataset? " $nocolor
     echo -e "$pool\c"
     read -i "/ROOT/ubuntu-1" -e root
     echo ""
     while true; do
               echo -e $green "Create root dataset at $pool$root." $nocolor
               echo -e $green "Is this correct (y/n):" $nocolor
               read -i "y" -e yn
               case $yn in
                    [Yy]* ) exitrootselect="1"; break;;
                    [Nn]* ) break;;
                    * ) echo "Please answer yes or no.";;
               esac
          done
done

zfs create -p $pool$root

if !(rsync -avPX --exclude '/swapfile' /target/. /$pool$root/.); then
     echo "Rsync failed to complete. Terminating Script."
     exit 1
fi

for d in proc sys dev; do mount --bind /$d /$pool$root/$d; done

cp /etc/resolv.conf /$pool$root/etc/resolv.conf
sed -e '/\s\/\s/ s/^#*/#/' -i /$pool$root/etc/fstab  #My take at comment out / line.
sed -e '/\sswap\s/ s/^#*/#/' -i /$pool$root/etc/fstab #My take at comment out swap line.

if [[ $swapzvol -ne 0 ]]; then
     zfs create -V "$swapzvol"G -b $(getconf PAGESIZE) -o compression=zle \
      -o logbias=throughput -o sync=always \
      -o primarycache=metadata -o secondarycache=none \
      -o com.sun:auto-snapshot=false $pool/swap
     mkswap -f /dev/zvol/$pool/swap
     echo RESUME=none > /$pool$root/etc/initramfs-tools/conf.d/resume
     echo /dev/zvol/$pool/swap none swap defaults 0 0 >> /$pool$root/etc/fstab
fi

chroot /$pool$root apt update
chroot /$pool$root apt install -y zfs-initramfs
chroot /$pool$root update-grub
drives="$(echo $layout | sed 's/\S*\(mirror\|raidz\|log\|spare\|cache\)\S*//g')"
for i in $drives; do 
          chroot /$pool$root sgdisk -a1 -n2:512:2047 -t2:EF02 $i
          chroot /$pool$root grub-install $i
     done

umount -R /$pool$root
zfs set mountpoint=/ $pool$root

while true; do
    echo -e $green 'Would you like to create a snapshot before rebooting? : ' $nocolor
    read -i "y" -e yn
    case $yn in
        [Yy]* ) zfs snapshot $pool$root@install-pre-reboot; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac

done
swapoff -a
umount /target
zfs destroy $pool/ubuntu-temp
zpool export $pool
echo ""
echo "Script complete.  Please reboot your computer to boot into your installation."
echo "If first boot hangs, reset computer and try boot again."
echo ""

while true; do
    echo -e $green 'Do you want to restart now? ' $nocolor
    read -i "y" -e yn
    case $yn in
        [Yy]* ) shutdown -r 0; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac

done
exit 0

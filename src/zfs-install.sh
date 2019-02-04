#!/usr/bin/env bash

set -e

LOG='zfs-install.log'
LOG_CMD='zfs-install.cmd'
DRY_RUN=0
DEBUG=1

[[ $EUID -ne 0 ]] && exec sudo "$0" "$@"

get_host_os()
{   # discover host os
    if [ -f "/etc/lsb-release" ]; then
        distver=$(lsb_release -cs)
        case $distver in
            bionic) export HOST_OS=ubuntu;;
            *)  echo "Sorry host os not currently supported..."
                exit 1;;
        esac
    fi
    export HOST_OS=ubuntu
}

_exec()
{   # simple cmd wrapper to help with issue #25 - recipe mode
    # really not sure if this is a good idea, i use it but i get it might suck!
    # I understand it really changes your coding style if() do but you can only try:)
    # if the idea isnt terrible i'll add getopts properly rather than $1, $2 !
    # i have this in all my system scripts with options for time counters etc.
    _CMD="$1"
    _MSG_ERROR="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "$_CMD"
        return
    else
        if [ "$DEBUG" -eq 1 ]; then
            read -e -p "$ " -i "$_CMD"
        fi
        bash -c "$_CMD"
        if [ "$?" -eq 0 ];then
            echo "$_CMD" >> "$LOG_CMD"
            return 0
        else
            echo "$_MSG_ERROR"
            return 1
        fi
    fi
}

zfs_setup() 
{   # bootstrap zfs on host
    case $HOST_OS in
        ubuntu)
            _exec "apt update"
            _exec "apt install -y zfsutils"
        ;;
    esac
}

zfs_config() 
{   # generic zfs configuration

    read -p "zpool_name=" -i "rpool" -e pool
    if [ -f "/vagrant/Vagrantfile" ]; then
        _path=/dev/sdc
    elif [ -d "/dev/disk/by-id/" ]; then
            _path=/dev/disk/by-id/
    elif [ -d "/dev/disk/by-uuid/" ]; then
            _path=/dev/disk/by-uuid/
        fi
    echo "Select vdev_layout:"
    select _disk in $(ls "$_path"); do
        layout="$_path$_disk"
        break
    done
    read -p "vdev_layout=" -i "$layout" -e layout
    read -p "zpool_options=" -i "-o feature@multi_vdev_crash_dump=disabled \
        -o feature@large_dnode=disabled \
        -o feature@sha512=disabled \
        -o feature@skein=disabled -o feature@edonr=disabled -o ashift=12 -O atime=off -O compression=lz4 -O normalization=formD -O recordsize=1M -O xattr=sa" -e options
    
    # Swap file calculation
    systemramk=$(free -m | awk '/^Mem:/{print $2}')
    systemramg=$(echo "scale=2; $systemramk/1024" | bc)
    suggestswap=$(printf %.$2f $(echo "scale=2; sqrt($systemramk/1024)" | bc))

    read -e -p "zvol_swap_size=" -i $suggestswap swapzvol
    # root dataset
    read -p "root_dataset=" -i "/ROOT/ubuntu-1" -e root

    export root="$root"
    export pool="$pool"
    export options="$options"
    export layout="$layout"
}

zfs_create()
{   # create zpool
    _exec "zpool create -f $options $pool $layout" 'Error creating zpool'
    if [[ "$HOST_OS" == 'ubuntu' ]]; then
        _exec "zfs create -V 10G $pool/ubuntu-temp" 'Error creating ZVOL'
    fi

    # create zfs swap volume
    if [[ $swapzvol -ne 0 ]]; then
        _exec "zfs create -V ${swapzvol}G -b $(getconf PAGESIZE) -o compression=zle \
            -o logbias=throughput -o sync=always \
            -o primarycache=metadata -o secondarycache=none \
            -o com.sun:auto-snapshot=false $pool/swap"
        _exec "mkswap -f /dev/zvol/$pool/swap"
    fi
    _exec "zfs create -p $pool$root"
}

zfs_create_snapshot()
{
    while true; do
        read -p "Would you like to create a snapshot before rebooting ?" -i "y" -e yn
        case $yn in
            [Yy]* )
                _exec "zfs snapshot $pool$root@install-pre-reboot"
                break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

os_install()
{   # initial ubuntu-ubiquity installer.
    case "$1" in
        ubuntu-ubiquity)

            # Does ubiquity have anything like a preseed ?
            # I really like that ubiquity does EVERYTHING it does, which is alot.
            # if we could just preseed it the harddrive that would make skip the
            # user having to 
            
            # Ultimately incorporating the zfs_setup question into the installer would
            # be ideal, we should check with ubuntu if they have plans ! They seem to
            # have made a stand legally. I get the difference in partition to standard
            # mkfs but these patches should really be in ubiquity !

            # Just found ubiquity --automatic with preseed too, AWESOME.
            # There are many preseed options to consider seperate branch to test out.

            # For now following your work-flow at least maintains the codes design.
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

            _exec 'ubiquity --no-bootloader' 'Ubiquity Installer failed to complete.'

            # If my understanding is correct this essentially just slurps up the "default" ubiquity install
            # and puts it on the zvol ?

            # 1) Is their anyway to tell ubiquity to use /$pool$root
            # 2) If not couldn't we just bind /target with /$pool$root first and skip the rsync ??

            _exec "rsync -avPX --exclude '/swapfile' /target/. /$pool$root/." 'Rsync failed to complete'
        ;;
        gentoo)
            echo "TODO"
        ;;
    esac
}

cleanup()
{   # final system cleanups
    _exec "swapoff -a"
    _exec "umount /target"

    mount | grep -v zfs | tac | awk '/\/rpool/ {print $3}' | xargs -i{} umount -lf {}
    _exec "zfs destroy $pool/ubuntu-temp"
    _exec "zpool export $pool"
}

sys_config()
{   # Generic system configuration

    # bind local /proc with chroot
    for d in proc sys dev; do
        _exec "mount --bind /$d /$pool$root/$d"
    done

    # network config
    _exec "cp /etc/resolv.conf /$pool$root/etc/resolv.conf"
    _exec "sed -e '/\s\/\s/ s/^#*/#/' -i /$pool$root/etc/fstab"  #My take at comment out / line.
    _exec "sed -e '/\sswap\s/ s/^#*/#/' -i /$pool$root/etc/fstab" #My take at comment out swap line.

    # zfs-initramfs grub config
    _exec "chroot /$pool$root apt update"
    _exec "chroot /$pool$root apt install -y zfs-initramfs"
    _exec "chroot /$pool$root update-grub"

    drives="$(echo $layout | sed 's/\S*\(mirror\|raidz\|log\|spare\|cache\)\S*//g')"
    for i in $drives; do 
        _exec "chroot /$pool$root sgdisk -a1 -n2:512:2047 -t2:EF02 $i"
        _exec "chroot /$pool$root grub-install $i"
    done
    

    _exec "echo RESUME=none > /$pool$root/etc/initramfs-tools/conf.d/resume"
    _exec "echo /dev/zvol/$pool/swap none swap defaults 0 0 >> /$pool$root/etc/fstab"
    _exec "zfs set mountpoint=/ $pool$root"
}

_reboot()
{
    while true; do
        echo -e $green 'Do you want to restart now? ' $nocolor
        read -i "y" -e yn
        case $yn in
            [Yy]* ) _exec "shutdown -r 0"; break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
    echo ""
    echo "Script complete.  Please reboot your computer to boot into your installation."
    echo "If first boot hangs, reset computer and try boot again."
    exit 0
}

get_host_os
zfs_setup
zfs_config
zfs_create
os_install ubuntu-ubiquity
sys_config
zfs_create_snapshot
cleanup
_reboot

#!/bin/bash

set -e

# root privilages required
[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

_echo()
{   # additional formatting flags
    # _echo [opt] <text>...
    # opt:
    #   -c      text color
    #   --bold  bold
    if [ "$#" == '0' ]; then
        exit 1
    fi

    MSG_TEXT=""
    MSG_TEXT_STYLE='0'

    while (( "$#" )); do
        case "$1" in
            -c)     MSG_TEXT_COLOR=$2; shift;;
            --bold) MSG_TEXT_STYLE=1;;
            *)      MSG_TEXT+="$1 ";;
        esac
        shift
    done

    case $MSG_TEXT_COLOR in
        black)  MSG_TEXT_COLOR='30';;
        red)    MSG_TEXT_COLOR='31';;
        green)  MSG_TEXT_COLOR='32';;
        yellow) MSG_TEXT_COLOR='33';;
        blue)   MSG_TEXT_COLOR='34';;
        purple) MSG_TEXT_COLOR='35';;
        cyan)   MSG_TEXT_COLOR='36';;
        white)  MSG_TEXT_COLOR='37';;
    esac

    printf "\033[${MSG_TEXT_STYLE};${MSG_TEXT_COLOR}m${MSG_TEXT}\033[0m\n"
}

msg()
{   # standard message interface style copied from packer.
    # msg <opt> <text> <text>
    # opt:
    #   -e | --error    Error
    #   -c | --cmd      _exec stdout
    #   -d | --debug    Debug
    #   -i | --info     Notice
    #   -q | --question Question

    MSG_TEXT='--> '
    MSG_TEXT_STYLE=

    while (( "$#" )); do
        case "$1" in
            -i | --info)        MSG_TEXT_COLOR=green;;
            -q | --question)    MSG_TEXT_COLOR=green; MSG_TEXT_STYLE='--bold';;
            -e | --error)       MSG_TEXT_COLOR=red; MSG_TEXT_STYLE='--bold';;
            -c | --command)     MSG_TEXT_COLOR=blue;;
            -d | --debug)       MSG_TEXT_COLOR=yellow; MSG_TEXT_STYLE='--bold';;
            -*|--*=)            msg -e "msg() unsupported flag $1"; exit 1;;
            *)                  MSG_TEXT+="$1 ";;
        esac
        shift
    done

    if [ "$MSG_TEXT_COLOR" == "red" ]; then
        _echo -c $MSG_TEXT_COLOR $MSG_TEXT_STYLE $MSG_TEXT
        exit 1
    fi 
    _echo -c $MSG_TEXT_COLOR $MSG_TEXT_STYLE $MSG_TEXT


}

_select_multi()
{   # _select_multi <var_return> a b c ...
    options=("${@:2}")
     
    menu() {
        for i in ${!options[@]}; do
            printf "%3d [%s] %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
        done
        echo "$msg" 
    }

    while menu && read -rp "? " num && [[ "$num" ]]; do
        for i in `seq 1 $( expr ${#options[@]} + 2 )`; do tput cuu1; tput el; done 
        [[ "$num" != *[![:digit:]]* ]] &&
        (( num > 0 && num <= ${#options[@]} )) ||
        { msg="Invalid option: $num"; continue; }
        ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
        [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
    done
    
    _select=
    for i in ${!options[@]}; do
        [[ "${choices[i]}" ]] && _select+="${options[i]} "
    done
    export "$1"="$_select"
}

_exec()
{   # simple exec wrapper
    # - dry-run
    # - log output

    CMD="$@"
    msg -c "$CMD"
    if [ "$OPT_DEBUG" == '1' ]; then
        read -e -p "$ " -i "$_CMD"
        if [ "$_CMD" != "$CMD" ]; then
            msg -c "$_CMD"
            CMD=$_CMD
        fi
    fi
    if [ "$OPT_DRYRUN" != '1' ]; then
        printf "\e[37m"
        if [ "$OPT_LOG_FILE" != '' ]; then
            echo -e "$ $CMD" >> "$OPT_LOG_FILE"
            bash -c "$CMD" 2>&1 | tee -a "$OPT_LOG_FILE"
        else
            bash -c "$CMD"
        fi
        printf "\e[0m"
    fi
    if [ "$OPT_LOG_CMD" != '' ]; then
        echo "$CMD" >> "$OPT_LOG_CMD"
    fi
}

usage()
{   
    echo -e "\nzfs-install.sh <options>\n"
    echo -e "-d | --debug            Interactive command execution"
    echo -e "-l | --log <file>       Log stdout"
    echo -e "-c | --log-cmd <file>   Log cmd sequence."
    echo -e "--dry-run          Process script but no command execution.\n"
}

opt_cmdline()
{   # parse zfs-install.sh arguments
    while (( "$#" )); do
        case "$1" in
            -d | --debug)   OPT_DEBUG=1;;
            -l | --log)     
                OPT_LOG_FILE="$2"
                if [ -f "$OPT_LOG_FILE" ]; then
                    msg -q "log file exists"
                    read -e -p "Append, Delete ? [a/d] " -i 'a'
                    [[ "$REPLY" == 'd' ]] && echo '' > "$OPT_LOG_FILE"
                fi;;
            -c | --log-cmd) 
                OPT_LOG_CMD="$2"
                if [ -f "$OPT_LOG_CMD" ]; then
                    msg -q "command log file exists"
                    read -e -p "Delete ? [d] " -i "d"
                    if [ $REPLY == 'd' ]; then
                        rm "$OPT_LOG_CMD"
                    else
                        msg -e "please choose another filename."
                        exit 1
                    fi
                fi
                shift;;
            --dry-run)      OPT_DRYRUN=1;;
            --help)         usage;;
            -*|--*)         msg -e "unsupported flag $1"; exit 1;;
        esac
        shift
    done
}

detect_os()
{   # get host os
    if [ -f "/etc/lsb-release" ]; then
        OS_DISTRIBUTOR=$(lsb_release -si)
        OS_RELEASE=$(lsb_release -sr)
        OS_CODENAME=$(lsb_release -sc)
        OS_DESCRIPTION=$(lsb_release -sd)
    fi
    if [ "$OS_CODENAME" == '' ]; then
        msg -e "Unsupported host operating system."
        exit 1
    else
        msg -i "OS_DISTRIBUTOR=$OS_DISTRIBUTOR"
        msg -i "OS_CODENAME=$OS_CODENAME"
        msg -i "OS_RELEASE=$OS_RELEASE"
        msg -i "OS_DESCRIPTION=$OS_DESCRIPTION"
    fi
}


zfs_bootstrap()
{   # bootstrap zfs on host
    case "$OS_DISTRIBUTOR" in
        Ubuntu)
            _exec apt-get update 
            _exec apt-get install -y zfsutils
        ;;
    esac
}

zfs_config()
{   # config zfs
    msg -i "ZFS Config"
    
    msg -i "ZPOOL Config"
    # zpool exists
    zpool_list=$(zfs list | tail -n +2 )
    if [ "$zpool_list" != '' ]; then
        msg -i "zpool found."
        zpool_root=$(zfs list / | tail -n +2)
        zpool list
        
        if [ "$zpool_root" != '' ]; then
            msg -i "root zvol found."
            zvol_root=$(zfs list / | tail -n +2)
            zfs list /
        
            zvol_root_mounted=$(zfs list -o mounted / | tail -n +2 | awk '{gsub(/ /, "", $0); print}')
            if [ "$zvol_root_mounted" == 'yes' ]; then
                msg -i "mounted"
                msg -e "TODO live migration"
            else
                msg -i "not mounted."
            fi
        fi
    else
        # zpool root config
        read -e -p "ZPOOL_NAME=" -i "rpool" ZPOOL_NAME
    
        msg -i "Physical / Virtual Disks..."
        # disk.list header
        printf "%-40s\t%-40s\t%s\t\n" "Indentifier" "Path" "Type" "Format" "Size"

        disk_avail=$(find /dev/disk/by*id/* | grep -v 'part')
        for disk_path in $disk_avail; do
            disk_identifier=$(fdisk -l $disk_path 2> /dev/null | awk '/Disk identifier:/ {printf $3}')
            disk_type=$(fdisk -l $disk_path 2> /dev/null | awk '/Disklabel type:/ {printf $3}')
            disk_size=$(fdisk -l $disk_path 2> /dev/null  | head -n 1 | awk '{bytes=$5; gb=bytes/1024/1024/1024; printf "%.0fG", gb}')
            disk_type=disk
            if [ "$disk_identifier" != '' ]; then
                printf "%-40s\t%-40s\t%s\t%s\n" "$disk_identifier" "$disk_path" "$disk_type" "$disk_format" "$disk_size" >> disks.tmp
            fi
        done
        
        sort -n disks.tmp -u -k1 > disks.unique

        for disk in $(awk '{path=$2; print path}' disks.unique); do
            awk -v disk_path="$disk" '$0 ~ disk_path {path=$2;type=$3;size=$4; print path,type,size}' disks.unique
            fdisk -l $disk | awk '/part/ {path=$1;size=$5;type=partition;format=substr($0, index($0,$6)); print path,type,format,size}'
        done
        
        msg -e "TODO vdev layount"

        select _disk in $(ls "$_path"); do
            layout="$_path$_disk"
            break
        done

        # create zpool
        # TODO zpool.cfg
        read -p "VDEV_LAYOUT=" -i "$layout" -e VDEV_LAYOUT
        read -p "ZPOOL_OPTIONS=" -i "-o feature@multi_vdev_crash_dump=disabled \
            -o feature@large_dnode=disabled \
            -o feature@sha512=disabled \
            -o feature@skein=disabled \
            -o feature@edonr=disabled \
            -o ashift=12 \
            -O atime=off \
            -O compression=lz4 \
            -O normalization=formD \
            -O recordsize=1M \
            -O xattr=sa" -e ZPOOL_OPTIONS
        
        # Swap file calculation
        systemramk=$(free -m | awk '/^Mem:/{print $2}')
        systemramg=$(echo "scale=2; $systemramk/1024" | bc)
        suggestswap=$(printf %.$2f $(echo "scale=2; sqrt($systemramk/1024)" | bc))

        read -e -p "zvol_swap_size=" -i $suggestswap swapzvol
        
        # root dataset
        read -e -p "ROOT_DATASET=" -i "/ROOT/ubuntu-1" -e root

        # cleanup
        rm disks.{tmp,unique}
    fi
}

zfs_create()
{   # create zpool
    _exec "zpool create -f $options $pool $layout" 
    if [[ "$HOST_OS" == 'ubuntu' ]]; then
        _exec "zfs create -V 10G $pool/ubuntu-temp"
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

zfs_snapshot()
{   # basic snapshot of installation
    
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
        ubiquity)
            
            # TODO implement in preseed.cfg
            msg -i "Ubiquity Installer\n"
            msg -i "Please follow these steps"
            msg -i "1) Choose any options you wish until you get to the 'Installation Type' screen."
            msg -i "2) Select 'Erase disk and install Ubuntu' and click 'Continue'."
            msg -i "3) Change the 'Select drive:' dropdown to /dev/zd0 - 10.7 GB Unknown' and click 'Install Now'."
            msg -i "4) A popup summarizes your choices and asks 'Write the changes to disks?'. Click 'Continue'."
            msg -i "5) At this point continue through the installer normally."
            msg -i "6) Finally, a message comes up 'Installation Complete'. Click the 'Continue Testing'." 
            read -p "Press any key to launch Ubiquity. These instructions will remain visible in the terminal window."
            
            _exec ubiquity --no-bootloader
            _exec rsync -avPX --exclude '/swapfile' /target/. /${ZPOOL_NAME}${ZPOOL_ROOT}/.
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
    _exec "sed -e '/\s\/\s/ s/^#*/#/' -i /$pool$root/etc/fstab"
    _exec "sed -e '/\sswap\s/ s/^#*/#/' -i /$pool$root/etc/fstab"

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
    read -e -p "Do you want to restart now ?" -i 'n'
    if [ "$REPLY" == 'y' ]; then
        _exec "shutdown -r 0"
    fi
    _msg "If first boot hangs, reset computer and try boot again."
    exit 0
}


opt_cmdline "$@"

detect_os

zfs_bootstrap
zfs_config
#zfs_create
#os_install ubuntu-ubiquity
#sys_config
#zfs_create_snapshot
#cleanup
#_reboot


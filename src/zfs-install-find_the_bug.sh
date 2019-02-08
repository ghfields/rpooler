#!/bin/bash

# I made bunch of edits save and try and run script. AS IS RIGHT NOW.
# script fails.
# their is one " -> out of place.
# if anyone can show me the proper way to debug this i would really appreciate it.
# i just started deleting code from the bottom up, found the bug the shellcheck.

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

    MSG_TEXT='--> '
    MSG_TEXT_STYLE=

    while (( "$#" )); do
        case "$1" in
            -i)         MSG_TEXT_COLOR=green;;
            -q)         MSG_TEXT_COLOR=green; MSG_TEXT_STYLE='--bold';;
            -e)         MSG_TEXT_COLOR=red; MSG_TEXT_STYLE='--bold';;
            -c)         MSG_TEXT_COLOR=blue;;
            -d)         MSG_TEXT_COLOR=yellow; MSG_TEXT_STYLE='--bold';;
            -*|--*=)    msg -e "msg() unsupported flag $1"; exit 1;;
            *)          MSG_TEXT+="$1 ";;
        esac
        shift
    done

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
    if [ "$OPT_LOG_CMD" != '' ]; then
        echo "$CMD" >> "$OPT_LOG_CMD"
    fi
    if [ "$OPT_DRYRUN" != '1' ]; then
        if [ "$OPT_DEBUG" == '1' ]; then
            read -e -p "$ " -i "$CMD"
        fi
        if [ "$OPT_LOG_FILE" != '' ]; then
            bash -c "$CMD" | tee "$OPT_LOG_FILE"
        else
            bash -c "$CMD"
        fi
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
                    select i in Append Remove; do
                        case "$i" in
                            Remove) rm "$OPT_LOG_FILE"
                        esac
                        break
                    done
                fi
                shift;;
            -c | --log-cmd) 
                OPT_LOG_CMD="$2"
                if [ -f "$OPT_LOG_CMD" ]; then
                    msg -q "command log file exists"
                    read -e -p "delete ? " -i "n"
                    if [ $REPLY == 'y' ]; then
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
        Ubuntu) _exec apt update && apt install -y zfsutils
    esac
}

zfs_config()
{   # generic zfs configuration
    
    msg -i "ZFS configuration"
    read -e -p "ZPOOL_NAME=" -i "rpool" ZPOOL_NAME

    # vdev layout
#    disk_avail=$(find /dev/disk/by*id/* | grep -v 'part')
#    disk_select=
#    for disk in $disk_avail; do
#        disk_identifier=$(fdisk -l $disk | awk '/Disk identifier:/ {print $3}')
#        disk_type=$(fdisk -l $disk | awk '/Disklabel type:/ {print $3')
#        disk_size=$(fdisk -l $disk | head -n 1 | awk '{FS=" "; OFS="\t"}{bytes=$5; gb=bytes/1024/1024/1024; printf "%3.0f gb\n", gb}')
#        echo -e "$disk\t $disk_identifier $disk_type $disk_size"
#    done

    read -p "HALT"

    msg -i "VDEV layout"
    select _disk in $(ls "$_path"); do
        layout="$_path$_disk"
        break
    done

    # create zpool
    # TODO zpool.cfg
    read -p "VDEV_LAYOUT=" -i "$layout" -e layout
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
    read -p "root_dataset=" -i "/ROOT/ubuntu-1" -e root
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
            _exec rsync -avPX --exclude '/swapfile' /target/. /${ZPOOL_NAME}${ZPOOL_ROOT}/."
        ;;
        gentoo)
            echo "TODO"
        ;;
    esac
}


detect_os

zfs_bootstrap
zfs_config
#zfs_create
#os_install ubuntu-ubiquity
#sys_config
#zfs_create_snapshot
#cleanup
#_reboot





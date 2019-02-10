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

    _TEXT=''
    _STYLE=''

    while (( "$#" )); do
        case "$1" in
            -c | --color)   _COLOR="$2"; shift;;
            --bold)         _STYLE+='1';;
            --dim)          _STYLE+='2';;
            --underline)    _STYLE+='4';;
            --invert)       _STYLE+='7';;
            --hidden)       _STYLE+='8';;
            *)              _TEXT+="$1 ";;
        esac
        shift
    done

    case $_COLOR in
        default)        _COLOR='39';;
        black)          _COLOR='30';;
        red)            _COLOR='31';;
        green)          _COLOR='32';;
        yellow)         _COLOR='33';;
        blue)           _COLOR='34';;
        purple)         _COLOR='35';;
        cyan)           _COLOR='36';;
        gray)           _COLOR='37';;
        darkgray)       _COLOR='90';;
        lightred)       _COLOR='91';;
        lightgreen)     _COLOR='92';;
        lightyellow)    _COLOR='93';;
        lightblue)      _COLOR='94';;
        lightpurple)    _COLOR='95';;
        lightcyan)      _COLOR='95';;
        white)          _COLOR='97';;
    esac
    printf "\e[$_STYLE;${_COLOR}m${_TEXT}\e[0m\n"
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
            -i | --info)        _COLOR=yellow;;
            -q | --question)    _COLOR=green; MSG_TEXT_STYLE='--bold';;
            -e | --error)       _COLOR=red; MSG_TEXT_STYLE='--bold';;
            -c | --command)     _COLOR=lightblue; MSG_TEXT_STYLE='--bold';;
            -d | --debug)       _COLOR=purple; MSG_TEXT_STYLE='--bold';;
            -*|--*=)            msg -e "msg() unsupported flag $1"; exit 1;;
            *)                  MSG_TEXT+="$1 ";;
        esac
        shift
    done

    if [ "$_COLOR" == "red" ]; then
        _echo -c $_COLOR $MSG_TEXT_STYLE $MSG_TEXT
        exit 1
    fi 
    _echo -c $_COLOR $MSG_TEXT_STYLE $MSG_TEXT


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
{   # _exec <opt> "cmd | awk '{print $1}' > file"
    # opt: set via cli, --dry-run --debug -l <log> -c <cmd>
    CMD="$@"
    msg -c "$CMD"
    if [ "$OPT_DEBUG" == '1' ]; then
        read -e -p "$ " -i "$CMD" _CMD
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
    printf "
    zfs-install.sh <options>
    
    -d | --debug            Interactive command execution.
    -l | --log <file>       Log stdout.
    -c | --log-cmd <file>   Log cmd sequence.
    --dry-run               Process script but no command execution.
    --silent                Fully automatic. ! NO IMPLEMENTED YET.\n"
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
            --help)         usage; exit 1;;
            -*|--*)         msg -e "unsupported flag $1"; exit 1;;
        esac
        shift
    done
}

zfs-config()
{   # test for host zpool
    while (( "$#" )); do
        case "$1" in
            --root-ds)
                if [ "$2" == '' ]; then
                    ZPOOL_ROOT_DS="ROOT"
                else
                    ZPOOL_ROOT_DS="$2"
                fi
            ;;
            --root-fs)
                if [ "$2" == '' ]; then
                    ZPOOL_ROOT_FS="$OS_CODENAME"
                else
                    ZPOOL_ROOTFS_NAME="$2"
                fi
            ;;
            --pool-name)
                if [ "$2" == '' ]; then
                    ZPOOL_POOL_NAME='rpool'
                else
                    ZPOOL_POOL_NAME="$2"
                fi
            ;;
            --disks)
                if [ "$2" == '' ]; then
                    disk-config --select ZPOOL_DISKS
                else
                    ZPOOL_DISKS="$2"
                fi
            ;;
            --swap)   
                ZPOOL_ZVOL_SWAP="$2"
            ;;
            --swap-size)
                if [ "$2" == '' ]; then
                    systemramk=$(free -m | awk '/^Mem:/{print $2}')
                    systemramg=$(echo "scale=2; $systemramk/1024" | bc)
                    suggestswap=$(printf %.$2f $(echo "scale=2; sqrt($systemramk/1024)" | bc))
                    ZPOOL_ZVOL_SWAP_SIZE="$suggestswap"
                else
                    ZPOOL_ZVOL_SWAP_SIZE="$2"
                fi
            ;;
            list)   
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
                    msg -i "no zpool found."
                fi
            ;;
        esac
        shift
    done
}

disk_part_drive()
{   # hack to get to return the disk of partition.
    # _disk_part </dev/partition>
    # returns /dev/drive

    part=$1
    part=${part#/dev/}
    disk=$(readlink /sys/class/block/$part)
    disk=${disk%/*}
    disk=/dev/${disk##*/}
    echo $disk 
}

disk-config()
{   # Basic physical / virtual disks config.
    # TODO better layout of partitions
    # TODO basic used,avail stats per disk.

    while (( "$#" )); do
        case "$1" in
            --list)
                lsblk -flp -o name,uuid,label,type,fstype,size,mountpoint,model
            ;;
            --select)
                # return available list of drives.
                disk_root=$(disk_part_drive $(lsblk -lo name,uuid,mountpoint --noheadings | awk '$3 == "/" {print}'))
                for disk_name in $(lsblk -dpl -o name,fstype --noheadings | awk -v disk_root="${disk_root}" '!/iso9660/ && $0!~disk_root {print}'); do
                    disk_list+="$disk_name "
                done
                disk_list_count=$(echo "$disk_list" | awk '{print NF}')
                if [ "$disk_list_count" == '1' ]; then
                    export "$2"="$disk_list"
                else
                    _select_multi "$2" $disk_list 
                fi
            ;;
        esac
        shift
    done
}


zfs-create()
{   # create zpool and datasets
    msg -i "ZPOOL: create"
    # clean partition tables
    _exec "sgdisk --zap-all $ZPOOL_DISKS"

    # legacy bios boot
    #_exec "sgdisk -a1 -n2:34:2047  -t2:EF02 $ZPOOL_DISKS"

    # unencrypted volume
    #_exec "sgdisk -n1:0:0 -t1:BF01 $ZPOOL_DISKS"

    # create zpool
    _exec "zpool create \
        -o ashift=12 \
        -o altroot=/mnt \
        -O atime=off \
        -O relatime=on \
        -O compression=lz4 \
        -O mountpoint=/$ZPOOL_POOL_NAME \
        -m none $ZPOOL_POOL_NAME $ZPOOL_VDEV $ZPOOL_DISKS"
    
    # create filesystem dataset for the root filesystem
    _exec "zfs create \
        -o mountpoint=none \
        $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS"
    
    # create boot environment
    _exec "zfs create \
        -o mountpoint=/ \
        $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOTFS_NAME"
   
    _exec "zpool set bootfs=$ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOTFS_NAME $ZPOOL_POOL_NAME"

    if [ "$ZPOOL_ZVOL_SWAP" == 'on' ]; then
        _exec "zfs create \
            -V ${ZPOOL_ZVOL_SWAP_SIZE}G \
            -b $(getconf PAGESIZE) \
            -o compression=zle \
            -o logbias=throughput \
            -o sync=always \
            -o primarycache=metadata \
            -o secondarycache=none \
            -o com.sun:auto-snapshot=false \
            $ZPOOL_POOL_NAME/swap"
        _exec "sleep 1"
        _exec "mkswap -f /dev/zvol/$ZPOOL_POOL_NAME/swap"
    fi
    
    # create mount points
    _exec "zfs create \
        -o mountpoint=/home \
        $ZPOOL_POOL_NAME/home"
    _exec "zfs create \
        -o mountpoint=/usr \
        $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOTFS_NAME/usr"
    _exec "zfs create \
        -o mountpoint=/var \
        $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOTFS_NAME/var"
    _exec "zfs create \
        -o mountpoint=/var/tmp \
        -o setuid=off \
        $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOTFS_NAME/var/tmp"
    _exec "zfs create \
        -o mountpoint=/tmp \
        -o setuid=off \
        $ZPOOL_POOL_NAME/tmp"

    _exec "zfs set mountpoint=legacy $ZPOOL_POOL_NAME/tmp"
    
    _exec "zpool export $ZPOOL_POOL_NAME"

    # import and create cache file
    _exec "zpool import -R /mnt $ZPOOL_POOL_NAME"
    _exec "mkdir -p /mnt/etc/zfs"
    _exec "zpool set cachefile=/mnt/etc/zfs/zpool.cache $ZPOOL_POOL_NAME"
    
    # list zfs config
    _exec "zpool get all $ZPOOL_POOL_NAME"
    _exec "zfs list -t all -o name,type,mountpoint,compress,exec,setuid,atime,relatime"
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

os-install()
{   # _os <option> <stage>
    # 
    # stage:
    #   zfs-bootstrap
    #   install
    #   config
    case "$1" in
        detect)
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
        ;;
        run)
            case "$OS_CODENAME" in
                bionic)
                    while (( "$#" )); do
                        case "$1" in
                            zfs-bootstrap)
                                _exec "apt-get update"
                                _exec "apt-get upgrade -y"
                                _exec "apt-get install -y zfsutils"
                            ;;
                            install)
                                # install base system
                                _exec "apt install -y debootstrap"
                                _exec "debootstrap $OS_CODENAME /mnt"
                            ;;
                            config)
                                # config hostname
                                _exec 'printf "$OS_CODENAME" > /mnt/etc/hostname'
                                _exec 'printf "127.0.0.1  $OS_CODENAME" >> /mnt/etc/hosts'
                        
                                # network
                                _exec "cp /etc/resolv.conf /mnt/etc/resolv.conf"
                                
                                # apt
                                _exec "cp /etc/apt/sources.list /mnt/apt/sources.list"
                                # fstab
                                _exec 'printf "/dev/zvol/$ZPOOL_POOL_NAME/swap\tnone\t\tswap\tdefaults\t0 0\n" >> /mnt/etc/fstab'
                                _exec 'printf "$ZPOOL_POOL_NAME/tmp\t\t/tmp\t\tzfs\tdefaults\t0 0\n" >> /mnt/etc/fstab'

                                # bind local with chroot
                                for d in proc sys dev; do
                                    _exec "mount --rbind /$d /mnt/$d"
                                done

                                cat << 'EOF' | chroot /mnt /bin/bash
ln -s /proc/self/mounts /etc/mtab
update-locale LANG=en_AU.UTF-8
dpkg-reconfigure locales
dpkg-reconfigure -f noninteractive  tzdata
apt update
apt upgrage -y
apt install -y --no-install-recommends linux-image-generic zfs-initramfs dosfstools
update-grub
EOF
                            ;;

                        esac
                        shift
                    done
                ;;
            esac
        ;;
        template)
            while (( "$#" )); do
                case "$1" in
                    zfs-bootstrap)
                    ;;
                    install)
                    ;;
                    config)
                    ;;
                esac
            done
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

_reboot()
{
    read -e -p "Reboot ? [y/n]"  -i 'n'
    if [ "$REPLY" == 'y' ]; then
        _exec "shutdown -r 0"
    fi
    _msg -i "If system hangs, hard reset!"
    exit 0
}


opt_cmdline "$@"

os-install detect 
os-install run zfs-bootstrap
zfs-config --disks 
zfs-config --pool-name rpool --root-ds ROOT --root-fs bionic --swap on --swap-size 
zfs-create
os-install run install config
#zfs_create_snapshot
#cleanup
#_reboot


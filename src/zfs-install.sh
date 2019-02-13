#!/bin/bash

# Author:   Shaun Lloyd
# License:  MIT
# Version:  0.6
# About:    Basic script for the installation of zfs as a root filesytem.
# Features: With help from vagrant,virtualbox,packer and a few others
#           - install linux with zfs as root filesystem.
#           - test zpool layouts
#
# FIXME  grub-install fail.
# TODO  Better disk menus.
# TODO  stable vagrant builds.
# TODO  fix --dry-run, --silent, --debug. zfs commands need to us _exec.
# TODO  add _read()
#       - Include timeouts, defaults, thresholds, warnings.
# TODO  fix _echo()
#       - formatting
#       - add styles
#       - add background
# TODO  - add /bin, /pkg
#       - add pkg-dev to vagrant

set -e

# root privilages required
[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

msg()
{   # standard message interface style copied from packer.
    # msg <opt> <text> <text>
    # opt:
    #   -e | --error    Error
    #   -c | --cmd      _exec stdout
    #   -d | --debug    Debug
    #   -i | --info     Notice
    #   -q | --question Question

    _TEXT='==> '
    _STYLE=

    while (( "$#" )); do
        case "$1" in
            -i | --info)        _COLOR=yellow;;
            -q | --question)    _COLOR=green; 	_STYLE='--bold';;
            -e | --error)       _COLOR=red; 	_STYLE='--bold';;
            -c | --command)     _COLOR=blue; 	_STYLE='--bold';;
            -d | --debug)       _COLOR=purple; 	_STYLE='--bold';;
            -*|--*=)            msg -e "msg() unsupported flag $1";;
            *)                  _TEXT+="$1 ";;
        esac
        shift
    done

    case $_COLOR in
        default)    _COLOR='39';;
        black)      _COLOR='30';; white)      _COLOR='97';;
        red)        _COLOR='31';; lred)       _COLOR='91';;
        green)      _COLOR='32';; lgreen)     _COLOR='92';;
        yellow)     _COLOR='33';; lyellow)    _COLOR='93';;
        blue)       _COLOR='34';; lblue)      _COLOR='94';;
        purple)     _COLOR='35';; lpurple)    _COLOR='95';;
        cyan)       _COLOR='36';; lcyan)      _COLOR='95';;
        gray)       _COLOR='37';; dgray)      _COLOR='90';;
    esac
	case "$_STYLE" in
		--bold)         _STYLE='1;';;
	esac
    printf "\e[${_STYLE}${_COLOR}m${_TEXT}\e[0m\n"

}

_select_multi()
{   # _select_multi <var_return> a b c ...
    # TODO  add comments to list
    options=("${@:2}")
     
    menu() {
        for i in ${!options[@]}; do
            printf "%3d [%s] %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
        done
    }

    while menu && read -rp "? " num && [[ "$num" ]]; do
        for i in `seq 1 $( expr ${#options[@]} + 1 )`; do tput cuu1; tput el; done 
        [[ "$num" != *[![:digit:]]* ]] &&
        (( num > 0 && num <= ${#options[@]} )) || { continue; }
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
{   # _exec <opt> <cmd>
    # opt: set via cli, --dry-run --debug -l <log> -c <cmd>
    CMD="$@"
    msg -c "$CMD"
    if [ "$OPT_DEBUG" == True ]; then
        read -e -p "$ " -i "$CMD" _CMD
        if [ "$_CMD" != "$CMD" ]; then
            msg -c "$_CMD"
            CMD=$_CMD
        fi
    fi
    if [ "$OPT_DRYRUN" != True ]; then
        if [ "$OPT_LOG_FILE" != '' ]; then
            echo -e "$ $CMD" >> "$OPT_LOG_FILE"
            bash -c "$CMD" 2>&1 | tee -a "$OPT_LOG_FILE"
        else
            bash -c "$CMD"
        fi
    fi
    if [ "$OPT_LOG_CMD" != '' ]; then
        echo -e "$CMD" >> "$OPT_LOG_CMD"
    fi
}

opt_cmdline()
{   # parse zfs-install.sh arguments
    while (( "$#" )); do
        case "$1" in
            -d | --debug)   OPT_DEBUG=True;;
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
            --dry-run)      OPT_DRYRUN=True;;
            --help)
                echo -e "\nzfs-install.sh <options>\n"
                echo -e "\t-d | --debug            Interactive command execution."
                echo -e "\t-l | --log <file>       Log stdout."
                echo -e "\t-c | --log-cmd <file>   Log cmd sequence."
                echo -e "\t--dry-run               Process script but no command execution."
                echo -e "\t--silent                Fully automatic. ! NO IMPLEMENTED YET.\n"; 
                exit 1
            ;;
            --password=*)   OS_PASSWORD="${1#*=}";;
            --disks=*)      ZPOOL_DISKS="${1#*=}";;
            --layout=*)     ZPOOL_LAYOUT="${1#*=}";;
            --root-ds=*)    ZPOOL_ROOT_DS="${1#*=}";;
            --root-fs=*)    ZPOOL_ROOT_FS="${1#*=}";;
            --pool-name=*)  ZPOOL_POOL_NAME="${1#*=}";;
            --swap)         ZPOOL_SWAP=True;;
            --swap-size=*)
                if [ "${1#*=}" == '' ]; then
                    systemramk=$(free -m | awk '/^Mem:/{print $2}')
                    systemramg=$(echo "scale=2; $systemramk/1024" | bc)
                    suggestswap=$(printf %.$2f $(echo "scale=2; sqrt($systemramk/1024)" | bc))
                    ZPOOL_SWAP_SIZE="$suggestswap"
                else
                    ZPOOL_SWAP_SIZE="${1#*=}"
                fi
            ;;
            -*|--*)         msg -e "unsupported flag $1"; exit 1;;
        esac
        shift
    done
}

_zfs()
{   # basic zfs wrapper.

    # TODO better layout of partitions
    # TODO basic used,avail stats per disk.
    # TODO add support for VDEVS: file,mirror,raidz1/2/3,spare,cache,log

    case "$1" in
        create)
            # check options are set
            [[ "${ZPOOL_LAYOUT}" == '' ]] && [[ "${ZPOOL_DISKS}" == '' ]] && disk select ZPOOL_DISKS
            [[ "${ZPOOL_LAYOUT}" == '' ]] && _zfs layout ZPOOL_LAYOUT
            [[ "${ZPOOL_ROOT_DS}" == '' ]] && read -e -p "ZPOOL_ROOT_DS=" ZPOOL_ROOT_DS
            [[ "${ZPOOL_ROOT_FS}" == '' ]] && read -e -p "ZPOOL_ROOT_FS=" ZPOOL_ROOT_FS
            [[ "${ZPOOL_POOL_NAME}" == '' ]] && read -ep "ZPOOL_POOL_NAME=" ZPOOL_POOL_NAME


            msg -i "ZPOOL: create"
            msg -i "ZPOOL_LAYOUT=${ZPOOL_LAYOUT}"
            msg -i "ZPOOL_ROOT_DS=${ZPOOL_ROOT_DS}"
            msg -i "ZPOOL_ROOT_FS=${ZPOOL_ROOT_FS}"
            msg -i "ZPOOL_POOL_NAME=${ZPOOL_POOL_NAME}"
            msg -i "ZPOOL_SWAP=${ZPOOL_SWAP}"
            msg -i "ZPOOL_SWAP_SIZE=${ZPOOL_SWAP_SIZE}"

            # create zpool
            # FIXME	need to get the boot partition !
            _exec "zpool create \
                -o ashift=12 \
                -o altroot=/mnt \
                -O atime=off \
                -O relatime=on \
                -O compression=lz4 \
                -O mountpoint=/$ZPOOL_POOL_NAME \
                -m none $ZPOOL_POOL_NAME $ZPOOL_LAYOUT"
            
            # create filesystem dataset for the root filesystem
            _exec "zfs create \
                -o mountpoint=none \
                $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS"
            
            # create boot environment
            _exec "zfs create \
                -o mountpoint=/ \
                $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOT_FS"
           
            _exec "zpool set bootfs=$ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOT_FS $ZPOOL_POOL_NAME"

            if [ "$ZPOOL_ZVOL_SWAP" == True ]; then
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
            
            # create os datasets
            _exec "zfs create \
                -o mountpoint=/home \
                $ZPOOL_POOL_NAME/home"
            _exec "zfs create \
                -o mountpoint=/usr \
                $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOT_FS/usr"
            _exec "zfs create \
                -o mountpoint=/var \
                $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOT_FS/var"
            _exec "zfs create \
                -o mountpoint=/var/tmp \
                -o setuid=off \
                $ZPOOL_POOL_NAME/$ZPOOL_ROOT_DS/$ZPOOL_ROOT_FS/var/tmp"
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
        ;;
        layout)
            # basic layout setup
            [[ "${ZPOOL_DISKS}" == '' ]] && disk select
            msg -i "ZPOOL:  Layout Configuration"
            msg -i "TODO:   Currently ZPOOL_LAYOUT is passed to zfs create."
            msg -i "? mirror /dev/aaa /dev/bbb mirror /dev/ccc /dev/ddd"
            read -e -p "ZPOOL_LAYOUT=" -i "${ZPOOL_DISKS}"
        ;;
        snapshot)
            # basic snapshot support
            # TODO recover first snapshot
            # TODO setup auto snapshots on / /home etc

            while true; do
                read -p "Create snapshot ?" -i "y" -e yn
                case $yn in
                    [Yy]* )
                        _exec "zfs snapshot ${ZPOOL_POOL_NAME}${ZPOOL_ROOT_FS}@install-pre-reboot"
                        break;;
                    [Nn]* ) break;;
                    * ) echo "Please answer yes or no.";;
                esac
            done
        ;;
        find)
            # find existing zpools.
            ZPOOL_EXISTS=False
            ZPOOL_ROOT_DS_EXISTS=False
            ZPOOL_ROOT_FS_EXISTS=False
            ZPOOL_ROOT_DS_MOUNTED=False
            ZPOOL_ROOT_FS_MOUNTED=False

            zpool_list=$(zfs list | tail -n +2 )
            if [ "$zpool_list" != '' ]; then
                msg -i "ZPOOL: found."
                ZPOOL_EXISTS=True
                zpool list
                
                zpool_root=$(zfs list / | tail -n +2)
                if [ "$zpool_root" != '' ]; then
                    msg -i "ZPOOL: ROOT_FS found."
                    ZPOOL_ROOT_DS_EXISTS=True
                    zfs list /
                
                    zvol_root_mounted=$(zfs list -o mounted / | tail -n +2 | awk '{gsub(/ /, "", $0); print}')
                    if [ "$zvol_root_mounted" == 'yes' ]; then
                        ZPOOL_ROOT_DS_MOUNTED=True
                        msg -i "ZPOOL: ROOT_FS mounted."
                        msg -i "TODO live migration"
                        msg -i "TODO installation from ZFS active root"
                        msg -e "Active development, please see https://github.com/lloydie/zfs-install/issues/11"
                    else
                        msg -i "ZPOOL: ROOT_FS not mounted."
                    fi
                fi
            else
                msg -i "ZPOOL: not found."
            fi
        ;;
    esac
}

disk()
{   # Basic physical / virtual disks config.
    # TODO encryption
    # FIXME disk destroy with fdisk, alllow for non gpt partition drives.

	case "$1" in
		destroy)
			# destroy partition tables
			msg -i "DISK: destroy ${ZPOOL_DISKS}"
			_exec "sgdisk --zap-all ${ZPOOL_DISKS}"
		;;
		format)
			if [ -d /sys/firmware/efi ]; then
				# uefi 
				_exec "sgdisk -n3:1M:+512M -t3:EF00 ${ZPOOL_DISKS}"
			else
				# bios
				_exec "sgdisk -a1 -n2:34:2047 -t2:EF02 ${ZPOOL_DISKS}"
			fi

			# unencrypted volume
			_exec "sgdisk -n1:0:0 -t1:BF01 $ZPOOL_DISKS"
		;;
		list)
			msg -i "DISK: List block devices."
			lsblk -flp -o name,uuid,label,type,fstype,size,mountpoint,model
		;;
		select)
			# return available list of available drives.
			disk-part-drive()
			{   # hack to get drive a partition is on.
				part=${1}
				part=${part#/dev/}
				disk=$(readlink /sys/class/block/$part)
				disk=${disk%/*}
				disk=/dev/${disk##*/}
				echo $disk 
			}

			disk_root=$(disk-part-drive $(lsblk -lo name,uuid,mountpoint --noheadings | awk '$3 == "/" {print $1}'))
			for disk_name in $(lsblk -dpl -o name,fstype --noheadings | awk -v disk_root="${disk_root}" '!/iso9660/ && $0!~disk_root {print}'); do
				disk_list+="$disk_name "
			done

			disk_count=$(echo "$disk_list" | awk '{print NF}')
			if [ "$disk_count" == '1' ]; then
				msg -i "DISK: Single disk found, auto format."
				export "$2"="$disk_list"
			else
				msg -q "DISK: Please select disks for root pool ?"
				_select_multi "$2" $disk_list 
			fi
		;;
	esac
}

os-detect()
{	# simple os detection, linux obviously for starters.
	# TODO debian
	# TODO gentoo
	# TODO centos
	# TODO rhel
	# TODO coreos
	# TODO linuxfromscratch
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
	[[ -d /sys/firmware/efi ]] && OS_BOOT_MODE=UEFI || OS_BOOT_MODE=BIOS	
}

os-install()
{   # Individual distribution installation
    # os-install <option>
    # 
    # stage:
    #   zfs-bootstrap
    #   install
    #   config
	
	[[ "${OS_PASSWORD}" == '' ]] && read -e -p "OS_PASSWORD=" -i "" OS_PASSWORD
	[[ "${OS_HOSTNAME}" == '' ]] && read -e -p "OS_HOSTNAME=" -i "" OS_HOSTNAME

	case "$OS_CODENAME" in
		bionic)
			while (( "$#" )); do
				case "$1" in
					zfs-bootstrap)
						# bootstrap zfs kernal modules
						_exec "apt-get update"
						_exec "apt-get install -y zfsutils"
					;;
					base)
						# install base system
						_exec "chmod 1777 /mnt/var/tmp"
						_exec "apt-get install -y debootstrap"
						_exec "debootstrap $OS_CODENAME /mnt"
						_exec "zfs set devices=off $ZPOOL_POOL_NAME"
					;;
					config)
						# config hostname
						_exec 'printf "$OS_HOSTNAME" > /mnt/etc/hostname'
						_exec 'printf "127.0.0.1  $OS_HOSTNAME" >> /mnt/etc/hosts'
				
						# network
						_exec "cp /etc/resolv.conf /mnt/etc/resolv.conf"
						
						# FIXME better repo selection is required.
						_exec "mkdir -p /mnt/etc/apt"
						_exec "cp /etc/apt/sources.list /mnt/etc/apt/source.list"
						
						# fstab
						_exec 'printf "/dev/zvol/$ZPOOL_POOL_NAME/swap\tnone\t\tswap\tdefaults\t0 0\n" >> /mnt/etc/fstab'
						_exec 'printf "$ZPOOL_POOL_NAME/tmp\t\t/tmp\t\tzfs\tdefaults\t0 0\n" >> /mnt/etc/fstab'
					;;
					bind-host)
						for d in proc sys dev; do
							_exec "mount --rbind /${d} /mnt/${d}"
						done
					;;
					unbind-host)
						mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {} 
					;;
					chroot-login)
						_exec chroot /mnt /bin/bash --login
					;;
					chroot-install)
						_chroot_install() 
						{   # Actual os install. 
							
							_exec "ln -s /proc/self/mounts /etc/mtab"
							_exec "apt-get update"
							_exec "apt-get upgrade -y"

							# locale
							_exec "locale-gen --purge"
							_exec "echo -e 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale"
							_exec "dpkg-reconfigure -f noninteractive locales"
							
							# timezone
							_exec "echo 'Australia/Melbourne' > /etc/timezone"
							_exec "dpkg-reconfigure  -f noninteractive tzdata"
							
							# install zfs in chroot
							_exec "apt-get install -y --no-install-recommends linux-image-generic zfs-initramfs"
							if [ -d /sys/firmware/efi ]; then
								msg -i "GRUB:   UEFI install."
								_exec "apt-get install -y dosfstools"
								_exec "mkdir /boot/efi"
								_exec "echo PARTUUID=$(blkid -s PARTUUID -o value ${ZPOOL_DISKS}) /boot/efi vfat noatime,nofail,x-systemd.device-timeout=1 0 1 >> /etc/fstab"
								_exec "mount /boot/efi"
								_exec "apt-get install --yes grub-efi-amd64"
								_exec "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck --no-floppy"
							else
								msg -i "GRUB:   BIOS install."
								_exec "apt-get install -y grub-pc"
								_exec "grub-install ${ZPOOL_DISKS}"
							fi

							# user accounts
							_exec "addgroup --system lpadmin"
							_exec "echo -e '${OS_PASSWORD}\n${OS_PASSWORD}' | passwd"

							# test grub
							_test_grub_root=$(grub-probe /)
							if [ "$grub_test_root" == 'zfs' ]; then
								msg -i "TEST_GRUB_ROOT:     PASS"
							else
								msg -i "TEST_GRUB_ROOT:     FAIL"
							fi
							_exec "update-initramfs -u -k all"
							_exec "update-grub"
							_test_grub_module=$(find /boot/grub/*/zfs.mod 2>1)
							if [ "$_test_grub_module" != '' ]; then
								msg -i "TEST_GRUB_MODULE:   FAIL"
							else
								msg -i "TEST_GRUB_MODULE:   PASS"
							fi
							msg -i "chroot install finished."
							exit
						}
						export -f _chroot_install _exec _echo msg
						_exec chroot /mnt /bin/bash -c "ZPOOL_DISKS=${ZPOOL_DISKS}; OS_PASSWORD=${OS_PASSWORD}; _chroot_install"
					;;
					cleanup)
						msg -i "cleanup"
						_exec "zfs umount -a"
						_exec "swapoff -a"
						_exec "zpool export $ZPOOL_POOL_NAME"
					;;
				esac
				shift
			done
		;;
	esac
}

_reboot()
{
    read -e -p "Reboot ? [y/n]"  -i 'n'
    [[ "$REPLY" == 'y' ]] && _exec "shutdown -r 0"
    _msg -i "If system hangs, hard reset!"
    exit 0
}


opt_cmdline "$@"

os-detect 
os-install zfs-bootstrap

disk list
disk select ZPOOL_DISKS

_zfs find "${ZPOOL_DISKS}"
disk destroy "${ZPOOL_DISKS}"
disk format "${ZPOOL_DISKS}"

read -e -p "ZPOOL_LAYOUT=" -i "${ZPOOL_DISKS}" ZPOOL_LAYOUT


_zfs create 

_os install base config bind-host chroot-mnt chroot-install unbind-host cleanup
#zfs_create_snapshot
_reboot

#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8
setup_path=/www

# 改自 bash <(wget --no-check-certificate -qO- 'http://download.bt.cn/tools/auto_disk.sh') 

# 检测内置硬盘数量（改进的检测逻辑）
get_internal_disks() {
    # 获取所有块设备，排除分区、loop设备、ram设备等
    local all_disks=$(lsblk -nd -o NAME,TYPE | grep disk | awk '{print $1}')
    local internal_disks=""
    
    for disk in $all_disks; do
        # 检查是否为内置硬盘
        # 1. NVMe 设备 (nvme*)
        # 2. SATA/SCSI 设备 (sd*, hd*)
        # 3. VirtIO 设备 (vd*) - 虚拟机环境
        # 4. Xen 设备 (xvd*) - Xen虚拟化
        if [[ $disk =~ ^(nvme[0-9]+n[0-9]+|sd[a-z]+|hd[a-z]+|vd[a-z]+|xvd[a-z]+)$ ]]; then
            # 排除USB、光驱等外置设备
            local is_removable=$(cat /sys/block/$disk/removable 2>/dev/null || echo 0)
            local device_type=$(udevadm info --query=property --name=/dev/$disk 2>/dev/null | grep "ID_BUS=" | cut -d= -f2)
            
            # 排除可移动设备和USB设备
            if [ "$is_removable" = "0" ] && [ "$device_type" != "usb" ]; then
                # 排除光驱
                local is_cdrom=$(udevadm info --query=property --name=/dev/$disk 2>/dev/null | grep "ID_CDROM=1")
                if [ -z "$is_cdrom" ]; then
                    internal_disks="$internal_disks $disk"
                fi
            fi
        fi
    done
    
    echo $internal_disks | xargs
}

# 获取系统盘（正在使用的根分区所在的磁盘）
get_system_disk() {
    local root_device=$(df / | tail -1 | awk '{print $1}')
    # 提取磁盘名称，去掉分区号
    if [[ $root_device =~ nvme ]]; then
        echo $root_device | sed 's/p[0-9]*$//'
    else
        echo $root_device | sed 's/[0-9]*$//'
    fi | sed 's|/dev/||'
}

# 获取数据盘（排除系统盘后的内置硬盘）
get_data_disks() {
    local all_internal_disks=$(get_internal_disks)
    local system_disk=$(get_system_disk)
    local data_disks=""
    
    for disk in $all_internal_disks; do
        if [ "$disk" != "$system_disk" ]; then
            data_disks="$data_disks $disk"
        fi
    done
    
    echo $data_disks | xargs
}

# 检测数据盘数量
sysDisk=$(get_data_disks)

if [ -z "$sysDisk" ]; then
    echo -e "ERROR! No additional internal hard drives found, exit"
    echo -e "未发现额外的内置硬盘，无法挂载"
    echo -e "当前内置硬盘列表:"
    get_internal_disks | tr ' ' '\n' | while read disk; do
        if [ -n "$disk" ]; then
            echo "  /dev/$disk ($(lsblk -nd -o SIZE /dev/$disk 2>/dev/null || echo 'unknown size'))"
        fi
    done
    echo -e "系统盘: /dev/$(get_system_disk)"
    echo -e "Bye-bye"
    exit 1
fi

echo -e "发现以下可用的数据盘:"
for disk in $sysDisk; do
    size=$(lsblk -nd -o SIZE /dev/$disk 2>/dev/null || echo 'unknown')
    echo "  /dev/$disk ($size)"
done

#检测/www目录是否已挂载磁盘
mountDisk=`df -h | awk '{print $6}' |grep www`
if [ "${mountDisk}" != "" ]; then
	echo -e "www directory has been mounted,exit"
	echo -e "www目录已被挂载,不执行任何操作"
	echo -e "Bye-bye"
	exit;
fi

#检测是否有windows分区
winDisk=`fdisk -l |grep "NTFS\|FAT32"`
if [ "${winDisk}" != "" ];then
	echo 'Warning: The Windows partition was detected. For your data security, Mount manually.';
	echo "危险 数据盘为windwos分区，为了你的数据安全，请手动挂载，本脚本不执行任何操作。"
	exit;
fi

echo "
+----------------------------------------------------------------------
| Bt-WebPanel Automatic disk partitioning tool (Enhanced Version)
+----------------------------------------------------------------------
| Copyright © 2015-2017 BT-SOFT(http://www.bt.cn) All rights reserved.
+----------------------------------------------------------------------
| Auto mount partition disk to $setup_path
| 支持硬盘类型: NVMe, SATA, IDE, VirtIO, Xen
| 可移动硬盘: $ALLOW_REMOVABLE | USB硬盘: $ALLOW_USB
+----------------------------------------------------------------------
"

#数据盘自动分区（修改后的函数）
fdiskP(){
	for disk in $sysDisk; do
		echo "正在处理磁盘: /dev/$disk"
		
		#判断指定目录是否被挂载
		isR=`df -P|grep $setup_path`
		if [ "$isR" != "" ];then
			echo "Error: The $setup_path directory has been mounted."
			return;
		fi
		
		# 检查第一个分区是否已挂载
		partition1="${disk}1"
		if [[ $disk =~ nvme ]]; then
			partition1="${disk}p1"
		fi
		
		isM=`df -P|grep "/dev/${partition1}"`
		if [ "$isM" != "" ];then
			echo "/dev/${partition1} has been mounted."
			continue;
		fi
			
		#判断是否存在未分区磁盘
		isP=`fdisk -l /dev/$disk 2>/dev/null |grep -v 'bytes'|grep "${disk}[p]*[1-9]"`
		if [ "$isP" = "" ];then
			echo "开始对 /dev/$disk 进行分区..."
			#开始分区
			fdisk -S 56 /dev/$disk << EOF
n
p
1


wq
EOF
			sleep 5
			#检查是否分区成功
			checkP=`fdisk -l /dev/$disk 2>/dev/null |grep "/dev/${partition1}"`
			if [ "$checkP" != "" ];then
				echo "分区创建成功，开始格式化..."
				#格式化分区
				mkfs.ext4 /dev/${partition1}
				mkdir -p $setup_path
				#挂载分区
				sed -i "/\/dev\/${partition1//\//\\\/}/d" /etc/fstab
				echo "/dev/${partition1}    $setup_path    ext4    defaults    0 0" >> /etc/fstab
				mount -a
				df -h
				echo "磁盘 /dev/$disk 挂载完成!"
				return
			else
				echo "分区创建失败: /dev/$disk"
			fi
		else
			echo "磁盘 /dev/$disk 已存在分区"
			#判断是否存在Windows磁盘分区
			isN=`fdisk -l /dev/$disk 2>/dev/null |grep -v 'bytes'|grep -v "NTFS"|grep -v "FAT32"`
			if [ "$isN" = "" ];then
				echo 'Warning: The Windows partition was detected. For your data security, Mount manually.';
				continue;
			fi
			
			#挂载已有分区
			checkR=`df -P|grep "/dev/$disk"`
			if [ "$checkR" = "" ];then
				echo "挂载现有分区 /dev/${partition1}..."
				mkdir -p $setup_path
				sed -i "/\/dev\/${partition1//\//\\\/}/d" /etc/fstab
				echo "/dev/${partition1}    $setup_path    ext4    defaults    0 0" >> /etc/fstab
				mount -a
				df -h
			fi
			
			#清理不可写分区
			echo 'True' > $setup_path/checkD.pl
			if [ ! -f $setup_path/checkD.pl ];then
				echo "分区不可写，重新挂载..."
				sed -i "/\/dev\/${partition1//\//\\\/}/d" /etc/fstab
				mount -a
				df -h
			else
				rm -f $setup_path/checkD.pl
				echo "磁盘 /dev/$disk 挂载完成!"
				return
			fi
		fi
	done
}

stop_service(){
	/etc/init.d/bt stop

	if [ -f "/etc/init.d/nginx" ]; then
		/etc/init.d/nginx stop > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/httpd" ]; then
		/etc/init.d/httpd stop > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/mysqld" ]; then
		/etc/init.d/mysqld stop > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/pure-ftpd" ]; then
		/etc/init.d/pure-ftpd stop > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/tomcat" ]; then
		/etc/init.d/tomcat stop > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/redis" ]; then
		/etc/init.d/redis stop > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/memcached" ]; then
		/etc/init.d/memcached stop > /dev/null 2>&1
	fi

	if [ -f "/www/server/panel/data/502Task.pl" ]; then
		rm -f /www/server/panel/data/502Task.pl
		for php_ver in 52 53 54 55 56 70 71 72 73 74 80 81; do
			if [ -f "/etc/init.d/php-fpm-${php_ver}" ]; then
				/etc/init.d/php-fpm-${php_ver} stop > /dev/null 2>&1
			fi
		done
	fi
}

start_service(){
	/etc/init.d/bt start

	if [ -f "/etc/init.d/nginx" ]; then
		/etc/init.d/nginx start > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/httpd" ]; then
		/etc/init.d/httpd start > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/mysqld" ]; then
		/etc/init.d/mysqld start > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/pure-ftpd" ]; then
		/etc/init.d/pure-ftpd start > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/tomcat" ]; then
		/etc/init.d/tomcat start > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/redis" ]; then
		/etc/init.d/redis start > /dev/null 2>&1
	fi

	if [ -f "/etc/init.d/memcached" ]; then
		/etc/init.d/memcached start > /dev/null 2>&1
	fi

	for php_ver in 52 53 54 55 56 70 71 72 73 74 80 81; do
		if [ -f "/etc/init.d/php-fpm-${php_ver}" ]; then
			/etc/init.d/php-fpm-${php_ver} start > /dev/null 2>&1
		fi
	done

	echo "True" > /www/server/panel/data/502Task.pl
}

while [ "$go" != 'y' ] && [ "$go" != 'n' ]
do
	read -p "确认要将数据盘挂载到 $setup_path 目录吗? (y/n): " go;
done

if [ "$go" = 'n' ];then
	echo -e "操作已取消"
	exit;
fi

if [ -f "/etc/init.d/bt" ] && [ -f "/www/server/panel/data/port.pl" ]; then
	# 获取第一个数据盘用于计算空间
	first_disk=$(echo $sysDisk | awk '{print $1}')
	diskFree=`cat /proc/partitions |grep ${first_disk}|awk '{print $3}'`
	wwwUse=`du -sh -k /www 2>/dev/null |awk '{print $1}' || echo 0`

	if [ "${diskFree}" -lt "${wwwUse}" ]; then
		echo -e "Sorry,your data disk is too small,can't copy to the www."
		echo -e "对不起，你的数据盘太小,无法迁移www目录数据到此数据盘"
		exit;
	else
		echo -e ""
		echo -e "stop bt-service"
		echo -e "停止宝塔服务"
		echo -e ""
		sleep 3
		stop_service
		echo -e ""
		mv /www /bt-backup
		echo -e "disk partition..."
		echo -e "磁盘分区..."
		sleep 2
		echo -e ""
		fdiskP
		echo -e ""
		echo -e "move disk..."
		echo -e "迁移数据中..."
		\cp -r -p -a /bt-backup/* /www
		echo -e ""
		echo -e "Done"
		echo -e "迁移完成"
		echo -e ""
		echo -e "start bt-service"
		echo -e "启动宝塔服务"
		echo -e ""
		start_service
	fi
else
	fdiskP
	echo -e ""
	echo -e "Done"
	echo -e "挂载成功"
fi

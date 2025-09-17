#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8
setup_path=/www

# 参数解析
ALLOW_REMOVABLE=false
ALLOW_USB=false
AUTO_MODE=false
CHECK_DISK=""

# 如果没有参数，推迟显示使用说明到函数定义之后
SHOW_USAGE_ONLY=false
if [ $# -eq 0 ]; then
    SHOW_USAGE_ONLY=true
fi

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--auto)
            AUTO_MODE=true
            shift
            ;;
        -r|--removable)
            ALLOW_REMOVABLE=true
            shift
            ;;
        -u|--usb)
            ALLOW_USB=true
            shift
            ;;
        -p|--path)
            setup_path="$2"
            if [[ -z "$setup_path" ]]; then
                echo "错误: -p|--path 需要指定路径参数"
                exit 1
            fi
            shift 2
            ;;
        -d|--disk)
            CHECK_DISK="$2"
            if [[ -z "$CHECK_DISK" ]]; then
                echo "错误: -d|--disk 需要指定硬盘名称 (如: sda, nvme0n1)"
                exit 1
            fi
            # 去掉可能的 /dev/ 前缀
            CHECK_DISK=${CHECK_DISK#/dev/}
            shift 2
            ;;
        -s|--select)
            SELECT_DISK="$2"
            if [[ -z "$SELECT_DISK" ]]; then
                echo "错误: -s|--select 需要指定硬盘名称 (如: sda, nvme0n1)"
                exit 1
            fi
            # 去掉可能的 /dev/ 前缀
            SELECT_DISK=${SELECT_DISK#/dev/}
            shift 2
            ;;
        -h|--help)
            SHOW_USAGE_ONLY=true
            break
            ;;
        *)
            echo "错误: 未知参数 '$1'"
            echo "使用 '$0 -h' 查看使用说明"
            exit 1
            ;;
    esac
done

# 检测内置硬盘数量（改进的检测逻辑）
get_internal_disks() {
    # 获取所有块设备，排除分区、loop设备、ram设备等
    local all_disks=$(lsblk -nd -o NAME,TYPE | grep disk | awk '{print $1}')
    local internal_disks=""
    
    for disk in $all_disks; do
        # 检查是否为硬盘设备
        # 1. NVMe 设备 (nvme*)
        # 2. SATA/SCSI 设备 (sd*, hd*)
        # 3. VirtIO 设备 (vd*) - 虚拟机环境
        # 4. Xen 设备 (xvd*) - Xen虚拟化
        if [[ $disk =~ ^(nvme[0-9]+n[0-9]+|sd[a-z]+|hd[a-z]+|vd[a-z]+|xvd[a-z]+)$ ]]; then
            # 获取设备信息
            local is_removable=$(cat /sys/block/$disk/removable 2>/dev/null || echo 0)
            local device_type=$(udevadm info --query=property --name=/dev/$disk 2>/dev/null | grep "ID_BUS=" | cut -d= -f2)
            local is_usb_device=false
            
            # 检查是否为USB设备
            if [ "$device_type" = "usb" ]; then
                is_usb_device=true
            fi
            
            # 排除光驱
            local is_cdrom=$(udevadm info --query=property --name=/dev/$disk 2>/dev/null | grep "ID_CDROM=1")
            if [ -n "$is_cdrom" ]; then
                continue
            fi
            
            # 根据参数决定是否包含该设备
            local should_include=true
            
            # 检查可移动设备
            if [ "$is_removable" = "1" ] && [ "$ALLOW_REMOVABLE" = false ]; then
                should_include=false
            fi
            
            # 检查USB设备
            if [ "$is_usb_device" = true ] && [ "$ALLOW_USB" = false ]; then
                should_include=false
            fi
            
            if [ "$should_include" = true ]; then
                internal_disks="$internal_disks $disk"
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

# 获取数据盘（排除系统盘后的硬盘）
get_data_disks() {
    local all_disks=$(get_internal_disks)
    local system_disk=$(get_system_disk)
    local data_disks=""
    
    for disk in $all_disks; do
        if [ "$disk" != "$system_disk" ]; then
            data_disks="$data_disks $disk"
        fi
    done
    
    echo $data_disks | xargs
}

# 获取分区的UUID
get_partition_uuid() {
    local partition=$1
    blkid /dev/$partition 2>/dev/null | grep -o 'UUID="[^"]*"' | cut -d'"' -f2 | head -1
}

# 交互式选择硬盘
select_disk_interactive() {
    local available_disks=$(get_data_disks)
    local disk_array=($available_disks)
    local disk_count=${#disk_array[@]}

    if [ $disk_count -eq 0 ]; then
        echo "错误: 没有可用的数据盘"
        return 1
    elif [ $disk_count -eq 1 ]; then
        echo "只发现一块数据盘: ${disk_array[0]}"
        echo "${disk_array[0]}"
        return 0
    fi

    echo "发现多块数据盘，请选择要挂载的硬盘:"
    echo ""

    local i=1
    for disk in $available_disks; do
        echo "  [$i] /dev/$disk"
        show_disk_info "$disk"
        echo ""
        ((i++))
    done

    while true; do
        read -p "请输入选择 (1-$disk_count): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$disk_count" ]; then
            local selected_index=$((choice - 1))
            echo "${disk_array[$selected_index]}"
            return 0
        else
            echo "错误: 请输入有效的数字 (1-$disk_count)"
        fi
    done
}

# 检查smartctl工具是否安装
check_smartctl() {
    if ! command -v smartctl &> /dev/null; then
        echo "  [警告] smartctl 工具未安装，无法显示SMART信息"
        echo "  安装方法: apt-get install smartmontools 或 yum install smartmontools"
        return 1
    fi
    return 0
}

# 获取硬盘SMART信息摘要
get_smart_summary() {
    local disk=$1
    if ! check_smartctl >/dev/null 2>&1; then
        echo "    SMART: 未安装smartmontools"
        return
    fi
    
    # 检查SMART是否支持和启用
    local smart_available=$(smartctl -i /dev/$disk 2>/dev/null | grep -i "SMART support is:" | grep "Available")
    local smart_enabled=$(smartctl -i /dev/$disk 2>/dev/null | grep -i "SMART support is:" | grep "Enabled")
    
    if [ -z "$smart_available" ]; then
        echo "    SMART: 不支持"
        return
    fi
    
    if [ -z "$smart_enabled" ]; then
        echo "    SMART: 支持但未启用"
        return
    fi
    
    # 获取关键SMART信息
    local smart_health=$(smartctl -H /dev/$disk 2>/dev/null | grep -i "overall-health" | awk -F': ' '{print $2}')
    local power_on_hours=$(smartctl -A /dev/$disk 2>/dev/null | grep -i "Power_On_Hours" | awk '{print $10}')
    local power_cycle_count=$(smartctl -A /dev/$disk 2>/dev/null | grep -i "Power_Cycle_Count" | awk '{print $10}')
    local temperature=$(smartctl -A /dev/$disk 2>/dev/null | grep -i "Temperature_Celsius" | awk '{print $10}' | head -1)
    local reallocated_sectors=$(smartctl -A /dev/$disk 2>/dev/null | grep -i "Reallocated_Sector" | awk '{print $10}')
    
    # 对于NVMe硬盘，使用不同的命令
    if [[ $disk =~ nvme ]]; then
        smart_health=$(smartctl -H /dev/$disk 2>/dev/null | grep -i "critical warning" | awk -F': ' '{print $2}')
        if [ "$smart_health" = "0x00" ]; then
            smart_health="PASSED"
        else
            smart_health="WARNING"
        fi
        power_on_hours=$(smartctl -A /dev/$disk 2>/dev/null | grep -i "Power On Hours" | awk -F': ' '{print $2}' | awk '{print $1}')
        temperature=$(smartctl -A /dev/$disk 2>/dev/null | grep -i "Temperature:" | awk -F': ' '{print $2}' | awk '{print $1}')
    fi
    
    echo "    SMART: 健康=${smart_health:-N/A}"
    if [ -n "$power_on_hours" ] && [ "$power_on_hours" != "N/A" ]; then
        # 将小时转换为更友好的格式
        local days=$((power_on_hours / 24))
        echo "           通电时间=${power_on_hours}小时 (约${days}天)"
    fi
    if [ -n "$temperature" ] && [ "$temperature" != "N/A" ]; then
        echo "           温度=${temperature}°C"
    fi
    if [ -n "$power_cycle_count" ] && [ "$power_cycle_count" != "N/A" ]; then
        echo "           开机次数=${power_cycle_count}次"
    fi
    if [ -n "$reallocated_sectors" ] && [ "$reallocated_sectors" != "N/A" ] && [ "$reallocated_sectors" != "0" ]; then
        echo "           重新分配扇区=${reallocated_sectors} [需关注]"
    fi
}

# 显示详细SMART信息
show_detailed_smart() {
    local disk=$1
    
    echo "
+----------------------------------------------------------------------
| 硬盘 /dev/$disk 详细SMART信息
+----------------------------------------------------------------------"
    
    if ! check_smartctl; then
        echo "请先安装 smartmontools:"
        echo "  Ubuntu/Debian: apt-get install smartmontools"
        echo "  CentOS/RHEL:   yum install smartmontools"
        return 1
    fi
    
    # 检查硬盘是否存在
    if [ ! -b "/dev/$disk" ]; then
        echo "错误: 硬盘 /dev/$disk 不存在"
        return 1
    fi
    
    # 显示基本信息
    echo "硬盘基本信息:"
    smartctl -i /dev/$disk 2>/dev/null | grep -E "(Model|Serial|Firmware|User Capacity|Sector Size)" | sed 's/^/  /'
    
    echo ""
    echo "SMART健康状态:"
    smartctl -H /dev/$disk 2>/dev/null | sed 's/^/  /'
    
    echo ""
    echo "关键SMART属性:"
    if [[ $disk =~ nvme ]]; then
        # NVMe设备
        smartctl -A /dev/$disk 2>/dev/null | grep -E "(Critical Warning|Temperature|Available Spare|Percentage Used|Data Units|Power On|Power Cycle|Unsafe Shutdown)" | sed 's/^/  /'
    else
        # 传统SATA/SAS设备
        smartctl -A /dev/$disk 2>/dev/null | grep -E "(Reallocated_Sector|Spin_Up_Time|Start_Stop_Count|Reallocated_Event|Current_Pending|Offline_Uncorrectable|UDMA_CRC_Error|Power_On_Hours|Power_Cycle_Count|Temperature|SATA_Downshift)" | sed 's/^/  /'
    fi
    
    echo ""
    echo "错误日志 (最近10条):"
    local error_count=$(smartctl -l error /dev/$disk 2>/dev/null | grep -c "Error [0-9]" || echo 0)
    if [ "$error_count" -gt 0 ]; then
        smartctl -l error /dev/$disk 2>/dev/null | head -20 | sed 's/^/  /'
        echo "  总错误数: $error_count"
    else
        echo "  无错误记录"
    fi
    
    echo ""
    echo "自检测试状态:"
    smartctl -l selftest /dev/$disk 2>/dev/null | head -10 | sed 's/^/  /'
    
    echo "+----------------------------------------------------------------------"
}

# 显示设备详细信息
show_disk_info() {
    local disk=$1
    local size=$(lsblk -nd -o SIZE /dev/$disk 2>/dev/null || echo 'unknown')
    local model=$(lsblk -nd -o MODEL /dev/$disk 2>/dev/null || echo 'unknown')
    local is_removable=$(cat /sys/block/$disk/removable 2>/dev/null || echo 0)
    local device_type=$(udevadm info --query=property --name=/dev/$disk 2>/dev/null | grep "ID_BUS=" | cut -d= -f2)
    
    local info_tags=""
    if [ "$is_removable" = "1" ]; then
        info_tags="${info_tags}[可移动]"
    fi
    if [ "$device_type" = "usb" ]; then
        info_tags="${info_tags}[USB]"
    fi
    if [ -z "$info_tags" ]; then
        info_tags="[内置]"
    fi
    
    echo "  /dev/$disk ($size) $info_tags - $model"

    # 显示UUID信息
    local partition1="${disk}1"
    if [[ $disk =~ nvme ]]; then
        partition1="${disk}p1"
    fi

    if [ -b "/dev/${partition1}" ]; then
        # 有分区的情况
        local partition_uuid=$(get_partition_uuid "${partition1}")
        if [ -n "$partition_uuid" ]; then
            echo "    分区UUID: $partition_uuid"
        else
            echo "    分区UUID: 未检测到"
        fi
    else
        # 检查整个硬盘是否有文件系统UUID（无分区表）
        local disk_uuid=$(blkid /dev/$disk 2>/dev/null | grep -o 'UUID="[^"]*"' | cut -d'"' -f2 | head -1)
        if [ -n "$disk_uuid" ]; then
            echo "    硬盘UUID: $disk_uuid (无分区表)"
        else
            echo "    分区状态: 未分区"
        fi
    fi

    # 如果没有指定具体硬盘检查，显示SMART摘要信息
    if [ -z "$CHECK_DISK" ] || [ "$CHECK_DISK" = "$disk" ]; then
        get_smart_summary "$disk"
    fi
}

# 显示磁盘挂载状态
show_disk_status() {
    echo "
+----------------------------------------------------------------------
| 当前磁盘状态
+----------------------------------------------------------------------"
    
    # 显示已挂载的磁盘
    echo "已挂载的磁盘:"
    local mounted_found=false
    while IFS= read -r line; do
        if [[ $line =~ ^/dev/ ]]; then
            local device=$(echo "$line" | awk '{print $1}')
            local mount_point=$(echo "$line" | awk '{print $6}')
            local size=$(echo "$line" | awk '{print $2}')
            local used=$(echo "$line" | awk '{print $3}')
            local available=$(echo "$line" | awk '{print $4}')
            local use_percent=$(echo "$line" | awk '{print $5}')
            
            # 过滤掉一些系统分区
            if [[ ! "$mount_point" =~ ^/(dev|proc|sys|run) ]]; then
                echo "  $device -> $mount_point ($size, 已用:$used, 可用:$available, 使用率:$use_percent)"
                mounted_found=true
            fi
        fi
    done < <(df -h | grep -v "tmpfs" | grep -v "Filesystem")
    
    if [ "$mounted_found" = false ]; then
        echo "  无已挂载的数据盘"
    fi
    
    echo ""
    
    # 显示待挂载的硬盘
    echo "待挂载的硬盘:"
    local all_disks=$(get_internal_disks)
    local system_disk=$(get_system_disk)
    local available_found=false
    
    if [ -n "$all_disks" ]; then
        for disk in $all_disks; do
            if [ "$disk" != "$system_disk" ]; then
                # 检查是否已挂载
                local is_mounted=$(df -h | grep "/dev/$disk" | wc -l)
                if [ "$is_mounted" -eq 0 ]; then
                    show_disk_info "$disk"
                    available_found=true
                fi
            fi
        done
    fi
    
    if [ "$available_found" = false ]; then
        echo "  无待挂载的硬盘"
        echo "  (当前配置: 可移动硬盘=$ALLOW_REMOVABLE, USB硬盘=$ALLOW_USB)"
    fi
    
    echo ""
    echo "系统盘: /dev/$system_disk [已排除,不会操作]"
    echo ""
}

# 显示使用说明
show_usage() {
    # 先显示磁盘状态
    show_disk_status
    
    echo "
+----------------------------------------------------------------------
| Bt-WebPanel 自动磁盘分区挂载工具 (增强版 MOD by tanpengsccd)
+----------------------------------------------------------------------
| (改自宝塔自动挂载脚本 http://download.bt.cn/tools/auto_disk.sh)
+----------------------------------------------------------------------
| 支持硬盘类型: NVMe, SATA, IDE, VirtIO, Xen, 可移动硬盘, USB硬盘
+----------------------------------------------------------------------

用法: $0 [选项]

选项:
  -a, --auto             自动挂载内置硬盘 (默认行为，必须指定)
  -r, --removable        允许识别可移动硬盘 (配合-a使用)
  -u, --usb              允许识别USB硬盘 (配合-a使用)
  -p, --path PATH        指定挂载路径 (默认:/www)
  -d, --disk DISK        查看指定硬盘的详细SMART信息 (如: sda, nvme0n1)
  -s, --select DISK      直接指定要挂载的硬盘 (如: sda, nvme0n1)
  -h, --help             显示此使用说明

组合使用示例:
  $0                     # 显示磁盘状态和SMART摘要
  $0 -a                  # 自动挂载内置硬盘
  $0 -a -r               # 自动挂载内置和可移动硬盘
  $0 -a -u               # 自动挂载内置和USB硬盘
  $0 -a -r -u            # 自动挂载所有类型硬盘
  $0 -a -p /data         # 自动挂载到/data目录
  $0 -a -s sda           # 直接挂载指定硬盘sda
  $0 -d sda              # 查看sda硬盘的详细SMART信息
  $0 -d nvme0n1          # 查看nvme0n1硬盘的详细SMART信息

注意事项:
  • 必须使用 -a 参数才会执行自动挂载操作
  • 脚本会自动排除系统盘，仅处理数据盘
  • 默认只处理内置硬盘，外置设备需额外参数启用
  • 挂载前会停止相关服务，完成后自动重启

+----------------------------------------------------------------------
"
}

# 检查是否只显示使用说明或检查指定硬盘
if [ "$SHOW_USAGE_ONLY" = true ] && [ -n "$CHECK_DISK" ]; then
    # 显示指定硬盘的详细SMART信息
    show_detailed_smart "$CHECK_DISK"
    exit 0
elif [ "$SHOW_USAGE_ONLY" = true ]; then
    # 显示使用说明（包含SMART摘要）
    show_usage
    exit 0
elif [ -n "$CHECK_DISK" ]; then
    # 仅检查指定硬盘
    show_detailed_smart "$CHECK_DISK"
    exit 0
fi

# 检查是否指定了自动模式
if [ "$AUTO_MODE" = false ]; then
    echo "错误: 必须使用 -a 或 --auto 参数才能执行自动挂载操作"
    echo "使用 '$0 -h' 查看使用说明"
    exit 1
fi

# 处理硬盘选择
if [ -n "$SELECT_DISK" ]; then
    # 验证指定的硬盘是否存在于可用数据盘中
    available_disks=$(get_data_disks)
    if [[ " $available_disks " =~ " $SELECT_DISK " ]]; then
        sysDisk="$SELECT_DISK"
        echo "已指定使用硬盘: /dev/$SELECT_DISK"
    else
        echo "错误: 指定的硬盘 /dev/$SELECT_DISK 不在可用数据盘列表中"
        echo "可用数据盘: $available_disks"
        exit 1
    fi
else
    # 检测数据盘数量
    all_data_disks=$(get_data_disks)

    if [ -z "$all_data_disks" ]; then
        echo "错误: 未发现可用的数据盘"
        echo "当前硬盘检测配置:"
        echo "  自动模式: $AUTO_MODE"
        echo "  允许可移动硬盘: $ALLOW_REMOVABLE"
        echo "  允许USB硬盘: $ALLOW_USB"
        echo "  挂载路径: $setup_path"
        exit 1
    else
        # 如果有多块硬盘，进行交互式选择
        selected_disk=$(select_disk_interactive)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        sysDisk="$selected_disk"
    fi
fi

echo -e "将要挂载的数据盘:"
show_disk_info "$sysDisk"
echo -e ""

#检测/www目录是否已挂载磁盘
mountDisk=`df -h | awk '{print $6}' |grep "^${setup_path}$"`
if [ "${mountDisk}" != "" ]; then
	echo -e "$setup_path directory has been mounted,exit"
	echo -e "$setup_path 目录已被挂载,不执行任何操作"
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
| Bt-WebPanel 自动磁盘分区挂载工具 (增强版) 
+----------------------------------------------------------------------
| Copyright © 2015-2017 BT-SOFT(http://www.bt.cn) All rights reserved.
+----------------------------------------------------------------------
| 挂载目标路径: $setup_path
| 支持硬盘类型: NVMe, SATA, IDE, VirtIO, Xen
| 可移动硬盘: $ALLOW_REMOVABLE | USB硬盘: $ALLOW_USB
+----------------------------------------------------------------------
"

#数据盘自动分区（修改为使用UUID挂载）
fdiskP(){
	disk=$sysDisk
	echo "正在处理磁盘: /dev/$disk"

	#判断指定目录是否被挂载
	isR=`df -P|grep $setup_path`
	if [ "$isR" != "" ];then
		echo "Error: The $setup_path directory has been mounted."
		return;
	fi

	# 检查分区或整个硬盘是否已挂载
	partition1="${disk}1"
	if [[ $disk =~ nvme ]]; then
		partition1="${disk}p1"
	fi

	# 检查分区挂载
	isM=`df -P|grep "/dev/${partition1}"`
	if [ "$isM" != "" ];then
		echo "/dev/${partition1} has been mounted."
		return;
	fi

	# 检查整个硬盘挂载（无分区表情况）
	isM_disk=`df -P|grep "/dev/${disk}"`
	if [ "$isM_disk" != "" ];then
		echo "/dev/${disk} has been mounted."
		return;
	fi
			
	#判断磁盘状态：分区、无分区表文件系统、或完全未格式化
	isP=`fdisk -l /dev/$disk 2>/dev/null |grep -v 'bytes'|grep "${disk}[p]*[1-9]"`
	disk_uuid=$(blkid /dev/$disk 2>/dev/null | grep -o 'UUID="[^"]*"' | cut -d'"' -f2 | head -1)

	if [ "$isP" = "" ] && [ -z "$disk_uuid" ];then
		# 完全未格式化的硬盘，需要分区
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
			# 获取分区UUID
			sleep 2  # 等待文件系统创建完成
			partition_uuid=$(get_partition_uuid "${partition1}")
			if [ -z "$partition_uuid" ]; then
				echo "错误: 无法获取分区UUID"
				return 1
			fi
			echo "分区UUID: $partition_uuid"
			mkdir -p $setup_path
			#使用UUID挂载分区
			sed -i "/UUID=$partition_uuid/d" /etc/fstab
			echo "UUID=$partition_uuid    $setup_path    ext4    defaults    0 0" >> /etc/fstab
			mount -a
			df -h
			echo "磁盘 /dev/$disk 使用UUID挂载完成!"
			return
		else
			echo "分区创建失败: /dev/$disk"
		fi
	elif [ "$isP" = "" ] && [ -n "$disk_uuid" ];then
		# 无分区表但有文件系统的硬盘，直接挂载
		echo "检测到无分区表的文件系统: /dev/$disk (UUID: $disk_uuid)"
		mkdir -p $setup_path
		# 清理旧的挂载条目
		sed -i "/\/dev\/${disk}/d" /etc/fstab
		sed -i "/UUID=$disk_uuid/d" /etc/fstab
		echo "UUID=$disk_uuid    $setup_path    ext4    defaults    0 0" >> /etc/fstab
		mount -a
		df -h

		# 测试写入权限
		echo 'True' > $setup_path/checkD.pl
		if [ ! -f $setup_path/checkD.pl ];then
			echo "分区不可写，重新挂载..."
			umount $setup_path 2>/dev/null
			mount -a
			df -h
		else
			rm -f $setup_path/checkD.pl
			echo "硬盘 /dev/$disk 使用UUID挂载完成!"
			return
		fi
	else
		echo "磁盘 /dev/$disk 已存在分区"
		#判断是否存在Windows磁盘分区
		isN=`fdisk -l /dev/$disk 2>/dev/null |grep -v 'bytes'|grep -v "NTFS"|grep -v "FAT32"`
		if [ "$isN" = "" ];then
			echo 'Warning: The Windows partition was detected. For your data security, Mount manually.';
			return;
		fi

		#挂载已有分区
		checkR=`df -P|grep "/dev/$disk"`
		if [ "$checkR" = "" ];then
			echo "挂载现有分区 /dev/${partition1}..."
			# 获取现有分区的UUID
			partition_uuid=$(get_partition_uuid "${partition1}")
			if [ -z "$partition_uuid" ]; then
				echo "错误: 无法获取分区UUID，将使用设备名挂载"
				mkdir -p $setup_path
				sed -i "/\/dev\/${partition1//\//\\\/}/d" /etc/fstab
				echo "/dev/${partition1}    $setup_path    ext4    defaults    0 0" >> /etc/fstab
			else
				echo "分区UUID: $partition_uuid"
				mkdir -p $setup_path
				# 清理旧的挂载条目
				sed -i "/\/dev\/${partition1//\//\\\/}/d" /etc/fstab
				sed -i "/UUID=$partition_uuid/d" /etc/fstab
				echo "UUID=$partition_uuid    $setup_path    ext4    defaults    0 0" >> /etc/fstab
			fi
			mount -a
			df -h
		fi

		#清理不可写分区
		echo 'True' > $setup_path/checkD.pl
		if [ ! -f $setup_path/checkD.pl ];then
			echo "分区不可写，重新挂载..."
			# 重新挂载
			umount $setup_path 2>/dev/null
			mount -a
			df -h
		else
			rm -f $setup_path/checkD.pl
			echo "磁盘 /dev/$disk 使用UUID挂载完成!"
			return
		fi
	fi
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
	read -p "确认要将硬盘 /dev/$sysDisk 挂载到 $setup_path 目录吗? (y/n): " go;
done

if [ "$go" = 'n' ];then
	echo -e "操作已取消"
	exit;
fi

if [ -f "/etc/init.d/bt" ] && [ -f "/www/server/panel/data/port.pl" ]; then
	# 获取选定数据盘用于计算空间
	diskFree=`cat /proc/partitions |grep ${sysDisk}|awk '{print $3}'`
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

#!/bin/bash

# 检查是否有超级用户权限
if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要超级用户权限，请使用 sudo 或以 root 用户运行"
    exit 1
fi

# 解析命令行参数
permanent=false
interface=""
dns_servers=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -p | --permanent) permanent=true ;;
    -i | --interface)
        shift
        interface="$1"
        ;;
    *) dns_servers+=("$1") ;;
    esac
    shift
done

if [ "${#dns_servers[@]}" -eq 0 ]; then
    echo "请至少提供一个 DNS 地址。"
    exit 1
fi

# 尝试自动检测网络接口名称，如果未指定
if [ -z "$interface" ]; then
    interface=$(ip route | grep default | sed -e "s/^.*dev.//" -e "s/.proto.*//")
    if [ -z "$interface" ]; then
        echo "未能检测到默认网络接口，请使用 -i 选项手动指定。"
        exit 1
    fi
fi

set_permanent_dns() {
    # 设置永久 DNS
    if systemctl is-active --quiet systemd-resolved; then
        sed -i '/^DNS=/d' /etc/systemd/resolved.conf
        echo "DNS=${dns_servers[*]}" >>/etc/systemd/resolved.conf
        systemctl restart systemd-resolved
        echo "systemd-resolved 的 DNS 配置已更新。"
    else
        # 更新 /etc/network/interfaces 文件以设置永久 DNS
        echo "iface $interface inet static" >>/etc/network/interfaces
        echo "    dns-nameservers ${dns_servers[*]}" >>/etc/network/interfaces
        ifdown $interface && ifup $interface
        echo "网络接口文件 /etc/network/interfaces 已更新。"
    fi
    echo "永久 DNS 已设置为："
    systemd-resolve --status | grep 'DNS Servers' -A 2 || cat /etc/resolv.conf
}

# 根据参数决定设置永久还是临时 DNS
if $permanent; then
    set_permanent_dns
else
    set_temporary_dns
fi

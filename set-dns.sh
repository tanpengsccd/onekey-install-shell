#!/bin/bash

# 显示帮助信息
usage() {
    echo "使用方式: $0 [-p] [-i interface] dns1 [dns2 ...]"
    echo "  -p, --permanent   设置永久 DNS"
    echo "  -i, --interface   指定网络接口"
}

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
    -h | --help)
        usage
        exit 0
        ;;
    *)
        # 支持 IPv4 和 IPv6 地址的正则表达式
        if [[ "$1" =~ ^(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)|([0-9a-fA-F:]+))$ ]]; then
            dns_servers+=("$1")
        else
            echo "无效的 DNS 地址: $1"
            usage
            exit 1
        fi
        ;;
    esac
    shift
done

if [ "${#dns_servers[@]}" -eq 0 ]; then
    echo "请至少提供一个 DNS 地址。"
    usage
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

set_temporary_dns() {
    echo -n >/etc/resolv.conf
    for dns in "${dns_servers[@]}"; do
        echo "nameserver $dns" >>/etc/resolv.conf
    done
    echo "临时 DNS 已设置为："
    cat /etc/resolv.conf
}

set_permanent_dns() {
    if systemctl is-active --quiet systemd-resolved; then
        # 清理现有 DNS 设置
        sed -i '/^DNS=/d' /etc/systemd/resolved.conf
        # 添加新 DNS 设置
        echo "DNS=${dns_servers[*]}" >>/etc/systemd/resolved.conf
        systemctl restart systemd-resolved
        echo "systemd-resolved 的 DNS 配置已更新。"
    else
        echo "systemd-resolved 服务未启用，请启用后再设置永久 DNS:"
        echo "  sudo systemctl enable systemd-resolved"
        echo "  sudo systemctl start systemd-resolved"
    fi
}

# 根据参数决定设置永久还是临时 DNS
if $permanent; then
    set_permanent_dns
else
    set_temporary_dns
fi
echo "如出现不可解决异常请 访问 https://github.com/tanpengsccd/onekey-install-shell 提交issue"

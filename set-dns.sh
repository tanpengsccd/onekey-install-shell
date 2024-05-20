#!/bin/bash
# 使用说明：
# 只支持 Ubuntu 和 Debian 系统
# 将上述代码保存到 set-dns.sh 文件中。
# 给脚本文件添加执行权限：chmod +x set-dns.sh
# 运行脚本：
# 临时设置 DNS：sudo ./set-dns.sh 1.1.1.1 8.8.8.8
# 永久设置 DNS：sudo ./set-dns.sh -p 1.1.1.1 8.8.8.8

# 检查是否有超级用户权限
if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要超级用户权限，请使用 sudo 或以 root 用户运行"
    exit 1
fi

# 解析命令行参数
permanent=false
dns_servers=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -p | --permanent) permanent=true ;;
    *) dns_servers+=("$1") ;;
    esac
    shift
done

if [ "${#dns_servers[@]}" -eq 0 ]; then
    echo "请至少提供一个 DNS 地址。"
    exit 1
fi

set_temporary_dns() {
    # 设置临时 DNS
    echo -n >/etc/resolv.conf
    for dns in "${dns_servers[@]}"; do
        echo "nameserver $dns" >>/etc/resolv.conf
    done
    echo "临时 DNS 已设置为："
    cat /etc/resolv.conf
}

set_permanent_dns() {
    # 设置永久 DNS
    if systemctl is-active --quiet systemd-resolved; then
        sed -i '/^DNS=/d' /etc/systemd/resolved.conf
        echo "DNS=${dns_servers[*]}" >>/etc/systemd/resolved.conf
        systemctl restart systemd-resolved
        echo "systemd-resolved 的 DNS 配置已更新。"
    else
        echo -n >/etc/resolv.conf
        for dns in "${dns_servers[@]}"; do
            echo "nameserver $dns" >>/etc/resolv.conf
        done
        echo "直接更新了 /etc/resolv.conf 文件。"
    fi
    echo "永久 DNS 已设置为："
    systemd-resolve --status | grep 'DNS Servers' -A 2
}

# 根据参数决定设置永久还是临时 DNS
if $permanent; then
    set_permanent_dns
else
    set_temporary_dns
fi

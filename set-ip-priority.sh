#!/bin/bash

# 脚本名字：set-ip-priority.sh
# 使用方法：
#   -4 设置 IPv4 优先
#   -6 设置 IPv6 优先
#   -reset 重置到默认设置

# 确保脚本以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

GAI_CONF="/etc/gai.conf"

# 检查 gai.conf 文件是否存在，不存在则创建
if [ ! -f "$GAI_CONF" ]; then
  echo "文件 $GAI_CONF 不存在，正在创建..."
  touch "$GAI_CONF"
fi

set_ipv4_priority() {
  sed -i '/^precedence ::ffff:0:0\/96/d' $GAI_CONF
  echo "precedence ::ffff:0:0/96  100" >> $GAI_CONF
  echo "已设置 IPv4 优先。"
}

set_ipv6_priority() {
  sed -i '/^precedence ::ffff:0:0\/96/d' $GAI_CONF
  echo "已设置 IPv6 优先（默认设置）。"
}

reset_to_default() {
  sed -i '/^precedence ::ffff:0:0\/96/d' $GAI_CONF
  echo "已重置到默认设置。"
}

# 解析命令行参数
while getopts ":46reset" opt; do
  case $opt in
    4)
      set_ipv4_priority
      exit 0
      ;;
    6)
      set_ipv6_priority
      exit 0
      ;;
    r)
      reset_to_default
      exit 0
      ;;
    \?)
      echo "无效选项: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "选项 -$OPTARG 需要一个参数。" >&2
      exit 1
      ;;
  esac
done

# 如果没有任何参数被提供
echo "用法：bash $0 -4 | -6 | -reset"
echo "  -4 设置 IPv4 优先"
echo "  -6 设置 IPv6 优先"
echo "  -reset 重置到默认设置"

#不需要重启系统。修改 /etc/gai.conf 文件后，改动会立即生效，因为这个文件是由系统库在进行名称解析时读取的。所以一旦你修改了该文件，所有新启动的应用程序都将使用新的地址选择规则。
#然而，对于已经运行中的应用程序或服务，它们可能还在使用旧的地址解析策略，因此你可能需要重启这些特定的应用程序，而不是整个系统，以确保它们使用最新的配置。

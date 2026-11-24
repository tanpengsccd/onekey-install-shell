#!/usr/bin/env bash
# ==============================================================================
# Eternal Terminal (ET) 一键安装脚本
# 适用系统: Debian 11 (bullseye) / 12 (bookworm) / 13 (trixie) 及 Ubuntu 各版本
# 功能说明:
#   - Debian 12/13 (amd64/arm64): 优先通过官方 APT 源安装
#   - Ubuntu (22.04/24.04/26.04 等): 优先通过官方 PPA (ppa:jgmath2000/et) 安装
#   - Debian 11 / Ubuntu 20.04 / 其他未提供预编译包的架构或版本: 自动回退至源码编译安装
#   - 自动配置 /etc/et.cfg、启用 et.service 并按需放行防火墙端口 (默认 TCP 2022)
# ==============================================================================

set -euo pipefail

# 默认参数
ET_PORT="2022"
ET_BIND_IP=""
CLIENT_ONLY="false"
FORCE_SOURCE="false"
SKIP_FIREWALL="false"
ACTION="install"
ET_REPO_URL="https://mistertea.github.io/debian-et/debian-source"
ET_GPG_URL="https://github.com/MisterTea/debian-et/raw/master/et.gpg"
ET_GITHUB_REPO="https://github.com/MisterTea/EternalTerminal.git"
ET_BUILD_ROOT=""

cleanup() {
    if [[ -n "${ET_BUILD_ROOT:-}" && -d "${ET_BUILD_ROOT}" ]]; then
        rm -rf "${ET_BUILD_ROOT}"
    fi
}
trap cleanup EXIT

# 终端颜色
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

usage() {
    cat <<'EOF'
Eternal Terminal (ET) 一键安装脚本
适配: Debian 11 / 12 / 13 与 Ubuntu

用法:
  sudo bash install-et.sh [选项]

选项:
  -p, --port <端口>       设置 etserver 监听的 TCP 端口 (默认: 2022)
  -b, --bind-ip <IP>      设置 etserver 绑定的 IP 地址 (默认: 全部网卡)
      --client-only       仅安装客户端，不启用 etserver 服务端且不修改防火墙
      --from-source       跳过 APT/PPA，强制从 GitHub 源码编译安装
      --no-firewall       跳过自动配置 ufw / firewalld 防火墙规则
      --uninstall         卸载 Eternal Terminal 并清理相关仓库配置
  -h, --help              显示此帮助信息

示例:
  sudo bash install-et.sh
  sudo bash install-et.sh --port 2022
  sudo bash install-et.sh --client-only
  sudo bash install-et.sh --from-source
  sudo bash install-et.sh --uninstall
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--port)
                [[ $# -ge 2 ]] || die "选项 $1 需要一个端口号参数"
                ET_PORT="$2"
                [[ "$ET_PORT" =~ ^[0-9]+$ ]] && (( ET_PORT >= 1 && ET_PORT <= 65535 )) \
                    || die "无效的端口号: $ET_PORT (范围 1-65535)"
                shift 2
                ;;
            -b|--bind-ip)
                [[ $# -ge 2 ]] || die "选项 $1 需要一个 IP 参数"
                ET_BIND_IP="$2"
                shift 2
                ;;
            --client-only)
                CLIENT_ONLY="true"
                shift
                ;;
            --from-source)
                FORCE_SOURCE="true"
                shift
                ;;
            --no-firewall)
                SKIP_FIREWALL="true"
                shift
                ;;
            --uninstall)
                ACTION="uninstall"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "未知参数: $1 (使用 --help 查看帮助)"
                ;;
        esac
    done
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "请使用 root 权限运行此脚本 (例如: sudo bash $0)"
    fi
}

detect_os() {
    [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release，无法识别操作系统"
    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
    OS_CODENAME="${VERSION_CODENAME:-}"
    OS_PRETTY="${PRETTY_NAME:-$OS_ID $OS_VERSION_ID}"

    # 兼容极少数没有 VERSION_CODENAME 的系统
    if [[ -z "$OS_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
        OS_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
    fi

    ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"

    info "检测到系统: ${OS_PRETTY} (ID=${OS_ID}, VERSION=${OS_VERSION_ID}, CODENAME=${OS_CODENAME:-none}, ARCH=${ARCH})"

    case "$OS_ID" in
        debian)
            if [[ "$OS_VERSION_ID" =~ ^(11|12|13|14)$ ]]; then
                :
            else
                warn "当前 Debian 版本 (${OS_VERSION_ID}) 不在主要测试范围 (11/12/13) 内，将尝试自动适配"
            fi
            ;;
        ubuntu)
            :
            ;;
        *)
            if [[ "$OS_ID_LIKE" == *ubuntu* || "$OS_ID_LIKE" == *debian* ]]; then
                warn "检测到 Debian/Ubuntu 衍生系统 (${OS_ID})，将尝试兼容安装"
            else
                die "不支持的操作系统: ${OS_PRETTY} (仅支持 Debian 和 Ubuntu)"
            fi
            ;;
    esac
}

ensure_base_tools() {
    export DEBIAN_FRONTEND=noninteractive
    info "更新软件索引并安装基础依赖..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg
}

check_debian_repo_available() {
    local codename="$1"
    local arch="$2"
    local release_info

    [[ -n "$codename" ]] || return 1

    release_info="$(curl -fsSL --connect-timeout 10 --max-time 20 "${ET_REPO_URL}/dists/${codename}/Release" 2>/dev/null)" || return 1
    grep -qE "^Architectures:.*\b${arch}\b" <<< "$release_info" || return 1
    return 0
}

check_ubuntu_ppa_available() {
    local codename="$1"
    local arch="$2"
    local pkg_list

    [[ -n "$codename" ]] || return 1

    pkg_list="$(curl -fsSL --connect-timeout 10 --max-time 20 \
        "https://ppa.launchpadcontent.net/jgmath2000/et/ubuntu/dists/${codename}/main/binary-${arch}/Packages.gz" 2>/dev/null \
        | gzip -dc 2>/dev/null)" || return 1

    grep -q '^Package: et$' <<< "$pkg_list"
}

install_debian_apt() {
    info "通过 Eternal Terminal 官方 Debian APT 源安装 (${OS_CODENAME}/${ARCH})..."

    install -d -m 0755 /etc/apt/keyrings

    local tmp_key
    tmp_key="$(mktemp)"
    if ! curl -fsSL --connect-timeout 15 --max-time 60 "$ET_GPG_URL" -o "$tmp_key"; then
        rm -f "$tmp_key"
        die "下载 GPG 密钥失败: $ET_GPG_URL"
    fi

    # 兼容二进制 OpenPGP 密钥与 ASCII Armored 密钥
    if grep -aq "BEGIN PGP PUBLIC KEY BLOCK" "$tmp_key"; then
        gpg --dearmor --yes -o /etc/apt/keyrings/et.gpg "$tmp_key"
    else
        cp "$tmp_key" /etc/apt/keyrings/et.gpg
    fi
    rm -f "$tmp_key"
    chmod 0644 /etc/apt/keyrings/et.gpg

    cat >/etc/apt/sources.list.d/et.list <<EOF
deb [signed-by=/etc/apt/keyrings/et.gpg] ${ET_REPO_URL}/ ${OS_CODENAME} main
EOF

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y et
    success "已通过官方 APT 源安装 Eternal Terminal"
}

install_ubuntu_ppa() {
    info "通过官方 Ubuntu PPA (ppa:jgmath2000/et) 安装 (${OS_CODENAME}/${ARCH})..."

    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq software-properties-common
    add-apt-repository -y ppa:jgmath2000/et
    apt-get update -qq
    apt-get install -y et
    success "已通过 Ubuntu PPA 安装 Eternal Terminal"
}

install_from_source() {
    info "准备从 GitHub 源码编译安装 Eternal Terminal (适用于 Debian 11 / 旧版 Ubuntu / 特殊架构)..."

    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y \
        build-essential cmake ninja-build git pkg-config \
        autoconf automake libtool zip unzip \
        libsodium-dev libprotobuf-dev protobuf-compiler \
        libutempter-dev libcurl4-openssl-dev libssl-dev \
        zlib1g-dev libunwind-dev

    ET_BUILD_ROOT="$(mktemp -d /tmp/et-build.XXXXXX)"

    # 查询最新稳定 release tag，失败则使用默认分支
    local release_json="" latest_tag=""
    release_json="$(curl -fsSL --connect-timeout 10 --max-time 20 \
        https://api.github.com/repos/MisterTea/EternalTerminal/releases/latest 2>/dev/null || true)"
    latest_tag="$(printf '%s\n' "$release_json" | awk -F'"' '/"tag_name"/ {print $4; exit}' || true)"

    if [[ -n "$latest_tag" ]]; then
        info "克隆 EternalTerminal 稳定版本: ${latest_tag}"
        git clone --depth 1 --branch "$latest_tag" --recurse-submodules --shallow-submodules \
            "$ET_GITHUB_REPO" "${ET_BUILD_ROOT}/EternalTerminal"
    else
        warn "未能获取最新 release 标签，将克隆默认分支"
        git clone --depth 1 --recurse-submodules --shallow-submodules \
            "$ET_GITHUB_REPO" "${ET_BUILD_ROOT}/EternalTerminal"
    fi

    mkdir -p "${ET_BUILD_ROOT}/EternalTerminal/build"
    pushd "${ET_BUILD_ROOT}/EternalTerminal/build" >/dev/null

    info "正在配置 CMake (禁用 vcpkg 与 telemetry，使用系统库)..."
    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DDISABLE_VCPKG=ON \
        -DBUILD_TESTING=OFF \
        -DDISABLE_TELEMETRY=ON \
        ..

    local jobs
    jobs="$(nproc 2>/dev/null || echo 2)"
    info "正在编译 Eternal Terminal (并行任务数: ${jobs})..."
    cmake --build . -j"${jobs}"

    info "正在安装编译产物至 /usr ..."
    cmake --install .

    popd >/dev/null

    # 安装默认配置文件与 systemd 服务单元 (源码 make install 不会自动放置)
    if [[ ! -f /etc/et.cfg ]]; then
        if [[ -f "${ET_BUILD_ROOT}/EternalTerminal/etc/et.cfg" ]]; then
            install -m 0644 "${ET_BUILD_ROOT}/EternalTerminal/etc/et.cfg" /etc/et.cfg
        else
            cat >/etc/et.cfg <<'EOF'
; et.cfg : Config file for Eternal Terminal

[Networking]
port = 2022

[Debug]
verbose = 0
silent = 0
logsize = 20971520
telemetry = false
logdirectory = /tmp
EOF
        fi
    fi

    if [[ ! -f /etc/systemd/system/et.service && ! -f /lib/systemd/system/et.service && ! -f /usr/lib/systemd/system/et.service ]]; then
        if [[ -f "${ET_BUILD_ROOT}/EternalTerminal/systemctl/et.service" ]]; then
            install -m 0644 "${ET_BUILD_ROOT}/EternalTerminal/systemctl/et.service" /etc/systemd/system/et.service
        else
            cat >/etc/systemd/system/et.service <<'EOF'
[Unit]
Description=Eternal Terminal
After=syslog.target network.target

[Service]
Type=simple
Restart=on-failure
ExecStart=/usr/bin/etserver --cfgfile=/etc/et.cfg --logtostdout

[Install]
WantedBy=multi-user.target
EOF
        fi
    fi

    rm -rf "${ET_BUILD_ROOT}"
    ET_BUILD_ROOT=""

    success "已完成 Eternal Terminal 源码编译安装"
}

configure_et_server() {
    info "配置 /etc/et.cfg (端口: ${ET_PORT})..."

    if [[ ! -f /etc/et.cfg ]]; then
        cat >/etc/et.cfg <<EOF
; et.cfg : Config file for Eternal Terminal

[Networking]
port = ${ET_PORT}

[Debug]
verbose = 0
silent = 0
logsize = 20971520
telemetry = false
logdirectory = /tmp
EOF
    else
        if grep -qE '^[#;[:space:]]*port[[:space:]]*=' /etc/et.cfg; then
            sed -i -E "s/^[#;[:space:]]*port[[:space:]]*=.*/port = ${ET_PORT}/" /etc/et.cfg
        else
            sed -i "/^\[Networking\]/a port = ${ET_PORT}" /etc/et.cfg
        fi
    fi

    if [[ -n "$ET_BIND_IP" ]]; then
        if grep -qE '^[#;[:space:]]*bind_ip[[:space:]]*=' /etc/et.cfg; then
            sed -i -E "s/^[#;[:space:]]*bind_ip[[:space:]]*=.*/bind_ip = ${ET_BIND_IP}/" /etc/et.cfg
        else
            sed -i "/^\[Networking\]/a bind_ip = ${ET_BIND_IP}" /etc/et.cfg
        fi
    fi
}

enable_et_service() {
    if [[ ! -d /run/systemd/system ]]; then
        warn "当前环境未以 systemd 作为 PID 1 运行，跳过 systemctl 启动服务"
        warn "可手动启动服务端: etserver --cfgfile=/etc/et.cfg --daemon"
        return 0
    fi

    info "启用并重启 et.service..."
    systemctl daemon-reload
    systemctl enable et >/dev/null 2>&1 || true
    systemctl restart et

    if systemctl is-active --quiet et; then
        success "et.service 已启动并设置为开机自启"
    else
        error "et.service 启动失败，请查看日志: journalctl -u et -n 50 --no-pager"
        return 1
    fi
}

configure_firewall() {
    [[ "$SKIP_FIREWALL" == "true" ]] && { info "已按参数跳过防火墙配置"; return 0; }

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
        info "检测到 UFW 防火墙已启用，放行 TCP ${ET_PORT}..."
        ufw allow "${ET_PORT}/tcp" comment "Eternal Terminal" >/dev/null
        success "UFW 已放行 TCP ${ET_PORT}"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        info "检测到 firewalld 已启用，放行 TCP ${ET_PORT}..."
        firewall-cmd --permanent --add-port="${ET_PORT}/tcp" >/dev/null
        firewall-cmd --reload >/dev/null
        success "firewalld 已放行 TCP ${ET_PORT}"
    else
        warn "未检测到启用的 UFW/firewalld；如使用云服务器或自定义 iptables/nftables，请确保安全组放行 TCP 端口 ${ET_PORT}"
    fi
}

detect_ssh_port() {
    local port=""
    if command -v ss >/dev/null 2>&1; then
        port="$(ss -tlnp 2>/dev/null | awk '/"sshd"/ {split($4, a, ":"); print a[length(a)]; exit}')"
    fi
    if [[ -z "$port" && -r /etc/ssh/sshd_config ]]; then
        port="$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2; exit}' /etc/ssh/sshd_config)"
    fi
    echo "${port:-22}"
}

print_summary() {
    local et_ver ssh_port
    et_ver="$(et --version 2>&1 | head -n 1 || echo "已安装")"
    ssh_port="$(detect_ssh_port)"

    echo ""
    echo "============================================================"
    success "Eternal Terminal (ET) 安装完成！"
    echo "------------------------------------------------------------"
    echo "  版本信息 : ${et_ver}"
    echo "  安装路径 : $(command -v et || echo 'N/A')"
    if [[ "$CLIENT_ONLY" == "false" ]]; then
        echo "  配置文件 : /etc/et.cfg"
        echo "  监听端口 : TCP ${ET_PORT}"
        if [[ -d /run/systemd/system ]]; then
            echo "  服务状态 : $(systemctl is-active et 2>/dev/null || echo 'unknown')"
        fi
    else
        echo "  安装模式 : 仅客户端 (--client-only)"
    fi
    echo "------------------------------------------------------------"
    echo "  客户端连接提示 (客户端本地同样需要安装 et):"
    if [[ "$ssh_port" == "22" && "$ET_PORT" == "2022" ]]; then
        echo "    et <用户名>@<服务器IP>"
    elif [[ "$ssh_port" == "22" ]]; then
        echo "    et <用户名>@<服务器IP>:${ET_PORT}"
    else
        echo "    检测到当前 SSH 端口为 ${ssh_port} (非默认 22)，连接示例:"
        echo "    et --ssh-option=\"Port=${ssh_port}\" <用户名>@<服务器IP>:${ET_PORT}"
        echo "    或在客户端 ~/.ssh/config 中为该主机配置 Port ${ssh_port} 后直接执行:"
        echo "    et <Host别名>:${ET_PORT}"
    fi
    echo "============================================================"
}

uninstall_et() {
    info "开始卸载 Eternal Terminal..."

    if [[ -d /run/systemd/system ]]; then
        systemctl stop et 2>/dev/null || true
        systemctl disable et 2>/dev/null || true
    fi

    if dpkg -s et >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get remove --purge -y et
        apt-get autoremove -y
    else
        # 清理源码安装的二进制文件
        rm -f /usr/bin/et /usr/bin/etserver /usr/bin/etterminal /usr/bin/htm /usr/bin/htmd \
              /usr/local/bin/et /usr/local/bin/etserver /usr/local/bin/etterminal /usr/local/bin/htm /usr/local/bin/htmd \
              /etc/systemd/system/et.service
    fi

    # 清理 APT 仓库及 PPA
    rm -f /etc/apt/sources.list.d/et.list /etc/apt/keyrings/et.gpg
    if command -v add-apt-repository >/dev/null 2>&1 && ls /etc/apt/sources.list.d/*jgmath2000* >/dev/null 2>&1; then
        add-apt-repository -y --remove ppa:jgmath2000/et || true
    fi

    if [[ -d /run/systemd/system ]]; then
        systemctl daemon-reload
    fi

    success "Eternal Terminal 已卸载完成 (如需清理配置可手动删除 /etc/et.cfg)"
}

main() {
    parse_args "$@"
    require_root

    if [[ "$ACTION" == "uninstall" ]]; then
        uninstall_et
        exit 0
    fi

    detect_os
    ensure_base_tools

    if [[ "$FORCE_SOURCE" == "true" ]]; then
        install_from_source
    elif [[ "$OS_ID" == "debian" ]] || [[ "$OS_ID_LIKE" == *debian* && "$OS_ID" != "ubuntu" && "$OS_ID_LIKE" != *ubuntu* ]]; then
        if check_debian_repo_available "$OS_CODENAME" "$ARCH"; then
            install_debian_apt
        else
            warn "官方 Debian APT 源暂未提供 ${OS_CODENAME:-$OS_VERSION_ID}/${ARCH} 预编译包 (例如 Debian 11 bullseye 已停止预编译分发)"
            warn "自动切换为源码编译安装..."
            install_from_source
        fi
    elif [[ "$OS_ID" == "ubuntu" || "$OS_ID_LIKE" == *ubuntu* ]]; then
        if check_ubuntu_ppa_available "$OS_CODENAME" "$ARCH"; then
            install_ubuntu_ppa
        else
            warn "官方 Ubuntu PPA (ppa:jgmath2000/et) 暂未提供 ${OS_CODENAME:-$OS_VERSION_ID}/${ARCH} 预编译包"
            warn "自动切换为源码编译安装..."
            install_from_source
        fi
    else
        install_from_source
    fi

    if [[ "$CLIENT_ONLY" == "false" ]]; then
        configure_et_server
        enable_et_service
        configure_firewall
    else
        if [[ -d /run/systemd/system ]]; then
            systemctl stop et 2>/dev/null || true
            systemctl disable et 2>/dev/null || true
        fi
    fi

    print_summary
}

main "$@"

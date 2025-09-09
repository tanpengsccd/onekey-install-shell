#!/usr/bin/env bash
#=============================================================
# 在https://github.com/P3TERX/SSH_Key_Installer基础上 做了功能增强 https://github.com/tanpengsccd/onekey-install-shell/ssh.sh
# Description: Install SSH keys via GitHub, URL or local files
# Version: 1.0.2
# Author: P3TERX  mod by tanpengsccd
# Blog: https://p3terx.com
#=============================================================

VERSION=1.0.1
RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${LIGHT_GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
[ $EUID != 0 ] && SUDO=sudo

USAGE() {
    echo "
SSH Key Installer $VERSION

Usage:
  bash <(curl -fsSL iilog.com/ssh_pub_key_installer.sh) [options...] <arg>

Options:
  -o	Overwrite mode, this option is valid at the top
  -g	Get the public key from GitHub, the arguments is the GitHub ID
  -u	Get the public key from the URL, the arguments is the URL
  -f	Get the public key from the local file, the arguments is the local file path
  -p	Change SSH port, the arguments is port number
  -d	'y' will disable remote password login, 'n' will enable remote password login
"
}

if [ $# -eq 0 ]; then
    USAGE
    exit 1
fi

get_github_key() {
    if [ "${KEY_ID}" == '' ]; then
        read -e -p "Please enter the GitHub account:" KEY_ID
        [ "${KEY_ID}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} The GitHub account is: ${KEY_ID}"
    echo -e "${INFO} Get key from GitHub..."
    PUB_KEY=$(curl -fsSL https://github.com/${KEY_ID}.keys)
    if [ "${PUB_KEY}" == 'Not Found' ]; then
        echo -e "${ERROR} GitHub account not found."
        exit 1
    elif [ "${PUB_KEY}" == '' ]; then
        echo -e "${ERROR} This account ssh key does not exist."
        exit 1
    fi
}

get_url_key() {
    if [ "${KEY_URL}" == '' ]; then
        read -e -p "Please enter the URL:" KEY_URL
        [ "${KEY_URL}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} Get key from URL..."
    PUB_KEY=$(curl -fsSL ${KEY_URL})
}

get_loacl_key() {
    if [ "${KEY_PATH}" == '' ]; then
        read -e -p "Please enter the path:" KEY_PATH
        [ "${KEY_PATH}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} Get key from ${KEY_PATH}..."
    PUB_KEY=$(cat ${KEY_PATH})
}

install_key() {
    [ "${PUB_KEY}" == '' ] && echo "${ERROR} ssh key does not exist." && exit 1
    if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
        echo -e "${INFO} '${HOME}/.ssh/authorized_keys' is missing..."
        echo -e "${INFO} Creating ${HOME}/.ssh/authorized_keys..."
        mkdir -p ${HOME}/.ssh/
        touch ${HOME}/.ssh/authorized_keys
        if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
            echo -e "${ERROR} Failed to create SSH key file."
        else
            echo -e "${INFO} Key file created, proceeding..."
        fi
    fi
    if [ "${OVERWRITE}" == 1 ]; then
        echo -e "${INFO} Overwriting SSH key..."
        echo -e "${PUB_KEY}\n" >${HOME}/.ssh/authorized_keys
    else
        echo -e "${INFO} Adding SSH key..."
        echo -e "\n${PUB_KEY}\n" >>${HOME}/.ssh/authorized_keys
    fi
    chmod 700 ${HOME}/.ssh/
    chmod 600 ${HOME}/.ssh/authorized_keys
    [[ $(grep "${PUB_KEY}" "${HOME}/.ssh/authorized_keys") ]] &&
        echo -e "${INFO} SSH Key installed successfully!" || {
        echo -e "${ERROR} SSH key installation failed!"
        exit 1
    }
}

# 检查并处理全局PermitRootLogin设置
handle_global_permit_root_login() {
    local config_file
    if [ $(uname -o) == Android ]; then
        config_file="$PREFIX/etc/ssh/sshd_config"
    else
        config_file="/etc/ssh/sshd_config"
    fi
    
    # 检查是否存在全局的PermitRootLogin设置
    if grep -q "^[[:space:]]*PermitRootLogin" "$config_file"; then
        echo -e "${INFO} Found existing global PermitRootLogin setting, commenting it out..."
        if [ $(uname -o) == Android ]; then
            sed -i 's/^[[:space:]]*PermitRootLogin/#&/' "$config_file"
        else
            $SUDO sed -i 's/^[[:space:]]*PermitRootLogin/#&/' "$config_file"
        fi
    fi
}

change_port() {
    echo -e "${INFO} Changing SSH port to ${SSH_PORT} ..."
    if [ $(uname -o) == Android ]; then
        # 检查是否已经有Port配置
        if grep -q "^[[:space:]]*Port" "$PREFIX/etc/ssh/sshd_config"; then
            sed -i "s@^[[:space:]]*Port.*@Port ${SSH_PORT}@" $PREFIX/etc/ssh/sshd_config
        else
            echo "Port ${SSH_PORT}" >>$PREFIX/etc/ssh/sshd_config
        fi
        [[ $(grep "^Port ${SSH_PORT}" "$PREFIX/etc/ssh/sshd_config") ]] && {
            echo -e "${INFO} SSH port changed successfully!"
            RESTART_SSHD=2
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} SSH port change failed!"
            exit 1
        }
    else
        # 检查是否已经有Port配置
        if grep -q "^[[:space:]]*Port" "/etc/ssh/sshd_config"; then
            $SUDO sed -i "s@^[[:space:]]*Port.*@Port ${SSH_PORT}@" /etc/ssh/sshd_config
        else
            echo "Port ${SSH_PORT}" | $SUDO tee -a /etc/ssh/sshd_config >/dev/null
        fi
        [[ $(grep "^Port ${SSH_PORT}" "/etc/ssh/sshd_config") ]] && {
            echo -e "${INFO} SSH port changed successfully!"
            RESTART_SSHD=1
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} SSH port change failed!"
            exit 1
        }
    fi
}

permit_local_root_login() {
    echo -e "${INFO} 配置允许 127.0.0.1 本地登录 root 用户"
    
    local config_file
    if [ $(uname -o) == Android ]; then
        config_file="$PREFIX/etc/ssh/sshd_config"
    else
        config_file="/etc/ssh/sshd_config"
    fi
    
    # 删除现有的Match Address 127.0.0.1配置块
    if grep -q "Match Address 127.0.0.1" "$config_file"; then
        echo -e "${INFO} 删除现有的 Match Address 127.0.0.1 配置..."
        if [ $(uname -o) == Android ]; then
            # 删除从Match Address 127.0.0.1开始到下一个非缩进行或文件末尾的所有内容
            sed -i '/^Match Address 127\.0\.0\.1/,/^[^[:space:]]/{/^Match Address 127\.0\.0\.1/d; /^[[:space:]]/d; /^[^[:space:]]/!d;}' "$config_file"
        else
            $SUDO sed -i '/^Match Address 127\.0\.0\.1/,/^[^[:space:]]/{/^Match Address 127\.0\.0\.1/d; /^[[:space:]]/d; /^[^[:space:]]/!d;}' "$config_file"
        fi
    fi
    
    # 添加新的配置
    local match_config="Match Address 127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication yes"
    
    if [ $(uname -o) == Android ]; then
        echo -e "$match_config" >>"$config_file"
        RESTART_SSHD=2
    else
        echo -e "$match_config" | $SUDO tee -a "$config_file" >/dev/null
        RESTART_SSHD=1
    fi
    
    echo -e "${INFO} 本地root登录配置完成"
}

permit_remote_root_password_login() {
    echo -e "${INFO} 配置远程root登录: ${DISABALE_PASSWORD}"
    
    local config_file
    if [ $(uname -o) == Android ]; then
        config_file="$PREFIX/etc/ssh/sshd_config"
    else
        config_file="/etc/ssh/sshd_config"
    fi
    
    # 先处理全局PermitRootLogin设置
    handle_global_permit_root_login
    
    # 删除现有的Match Address *,!127.0.0.1配置块
    if grep -q "Match Address \*,!127\.0\.0\.1\|Match Address \\\*,!127\.0\.0\.1" "$config_file"; then
        echo -e "${INFO} 删除现有的远程访问配置..."
        if [ $(uname -o) == Android ]; then
            sed -i '/^Match Address [*\\]*,!127\.0\.0\.1/,/^[^[:space:]]/{/^Match Address [*\\]*,!127\.0\.0\.1/d; /^[[:space:]]/d; /^[^[:space:]]/!d;}' "$config_file"
        else
            $SUDO sed -i '/^Match Address [*\\]*,!127\.0\.0\.1/,/^[^[:space:]]/{/^Match Address [*\\]*,!127\.0\.0\.1/d; /^[[:space:]]/d; /^[^[:space:]]/!d;}' "$config_file"
        fi
    fi
    
    # 根据参数决定配置
    local match_config
    if [[ ${DISABALE_PASSWORD} =~ ^[nN] ]]; then
        echo -e "${INFO} 允许远程密码登录root用户"
        match_config="Match Address *,!127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication yes\n    PubkeyAuthentication yes"
    else
        echo -e "${INFO} 不允许远程密码登录root用户,但允许ssh-key登陆"
        match_config="Match Address *,!127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication no\n    PubkeyAuthentication yes"
    fi
    
    # 添加新配置
    if [ $(uname -o) == Android ]; then
        echo -e "$match_config" >>"$config_file"
        RESTART_SSHD=2
    else
        echo -e "$match_config" | $SUDO tee -a "$config_file" >/dev/null
        RESTART_SSHD=1
    fi
    
    echo -e "${INFO} 远程root登录配置完成"
}

# 验证SSH配置文件语法
validate_ssh_config() {
    echo -e "${INFO} 验证SSH配置文件语法..."
    if [ $(uname -o) == Android ]; then
        # Termux环境可能不支持sshd -t
        echo -e "${INFO} Termux环境跳过语法检查"
        return 0
    else
        if $SUDO sshd -t 2>/dev/null; then
            echo -e "${INFO} SSH配置语法正确"
            return 0
        else
            echo -e "${ERROR} SSH配置语法错误，请检查配置文件"
            echo -e "${INFO} 运行 'sudo sshd -t' 查看详细错误信息"
            return 1
        fi
    fi
}

while getopts "og:u:f:p:d:" OPT; do
    case $OPT in
    o)
        OVERWRITE=1
        ;;
    g)
        KEY_ID=$OPTARG
        get_github_key
        install_key
        ;;
    u)
        KEY_URL=$OPTARG
        get_url_key
        install_key
        ;;
    f)
        KEY_PATH=$OPTARG
        get_loacl_key
        install_key
        ;;
    p)
        SSH_PORT=$OPTARG
        change_port
        ;;
    d)
        DISABALE_PASSWORD=${OPTARG:-y} # 如果未提供参数，则默认为'y'
        permit_remote_root_password_login
        permit_local_root_login
        ;;
    ?)
        USAGE
        exit 1
        ;;
    :)
        USAGE
        exit 1
        ;;
    *)
        USAGE
        exit 1
        ;;
    esac
done

# 如果修改了SSH配置，验证语法
if [ "$RESTART_SSHD" = 1 ] || [ "$RESTART_SSHD" = 2 ]; then
    if validate_ssh_config; then
        if [ "$RESTART_SSHD" = 1 ]; then
            echo -e "${INFO} 重启SSH服务..."
            if $SUDO systemctl restart sshd; then
                echo -e "${INFO} SSH服务重启成功"
            else
                echo -e "${ERROR} SSH服务重启失败"
                exit 1
            fi
        elif [ "$RESTART_SSHD" = 2 ]; then
            echo -e "${INFO} 请重启sshd服务或Termux应用以使配置生效"
        fi
    else
        echo -e "${ERROR} 由于配置语法错误，未重启SSH服务"
        exit 1
    fi
fi

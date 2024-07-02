#!/usr/bin/env bash
#=============================================================
# 在https://github.com/P3TERX/SSH_Key_Installer基础上 做了功能增强 https://github.com/tanpengsccd/onekey-install-shell/ssh.sh
# Description: Install SSH keys via GitHub, URL or local files
# Version: 1.0.0
# Author: P3TERX  mod by tanpengsccd
# Blog: https://p3terx.com
#=============================================================

VERSION=1.0
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
  -d	'y' will disable remote password login",'n' will enable remote password login
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
    echo -e "${INFO} Get key from $(${KEY_PATH})..."
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

change_port() {
    echo -e "${INFO} Changing SSH port to ${SSH_PORT} ..."
    if [ $(uname -o) == Android ]; then
        [[ -z $(grep "Port " "$PREFIX/etc/ssh/sshd_config") ]] &&
            echo -e "${INFO} Port ${SSH_PORT}" >>$PREFIX/etc/ssh/sshd_config ||
            sed -i "s@.*\(Port \).*@\1${SSH_PORT}@" $PREFIX/etc/ssh/sshd_config
        [[ $(grep "Port " "$PREFIX/etc/ssh/sshd_config") ]] && {
            echo -e "${INFO} SSH port changed successfully!"
            RESTART_SSHD=2
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} SSH port change failed!"
            exit 1
        }
    else
        $SUDO sed -i "s@.*\(Port \).*@\1${SSH_PORT}@" /etc/ssh/sshd_config && {
            echo -e "${INFO} SSH port changed successfully!"
            RESTART_SSHD=1
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} SSH port change failed!"
            exit 1
        }
    fi
}

# disable_password() {

#     if [ $(uname -o) == Android ]; then
#         sed -i "s@.*\(PasswordAuthentication \).*@\1no@" $PREFIX/etc/ssh/sshd_config && {
#             RESTART_SSHD=2
#             echo -e "${INFO} Disabled password login in SSH."
#         } || {
#             RESTART_SSHD=0
#             echo -e "${ERROR} Disable password login failed!"
#             exit 1
#         }
#     else
#         $SUDO sed -i "s@.*\(PasswordAuthentication \).*@\1no@" /etc/ssh/sshd_config && {
#             RESTART_SSHD=1
#             echo -e "${INFO} Disabled password login in SSH."
#         } || {
#             RESTART_SSHD=0
#             echo -e "${ERROR} Disable password login failed!"
#             exit 1
#         }
#     fi
# }

permit_local_root_login() {
    echo -e "允许 127.0.0.1 本地登录 root 用户"
    # 允许 127.0.0.1 本地登录 root 用户, 需要检查有无"Match Address 127.0.0.1",有则先删除对应缩进里的所有配置,再添加
    # Match Address 127.0.0.1
    #     PermitRootLogin yes
    #     PasswordAuthentication yes
    if [ $(uname -o) == Android ]; then
        if grep -q "Match Address 127.0.0.1" $PREFIX/etc/ssh/sshd_config; then
            sed -i '/Match Address 127.0.0.1/,/^$/d' $PREFIX/etc/ssh/sshd_config
        fi
        echo -e "\Match Address 127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication yes\n" >>$PREFIX/etc/ssh/sshd_config
        RESTART_SSHD=2
    else
        if grep -q "Match Address 127.0.0.1" /etc/ssh/sshd_config; then
            $SUDO sed -i '/Match Address 127.0.0.1/,/^$/d' /etc/ssh/sshd_config
        fi
        $SUDO echo -e "Match Address 127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication yes\n" >>/etc/ssh/sshd_config
        RESTART_SSHD=1
    fi

}

permit_remote_root_password_login() {
    # $DISABALE_PASSWORD 是 "n"/"N" 开头字符 就是 开启 root 密码登陆 (反反得正)
    echo -e "permit_remote_root_password_login ${DISABALE_PASSWORD} "
    if [[ ${DISABALE_PASSWORD} =~ ^[nN] ]]; then
        echo -e "允许远程密码登录root用户"
        if [ $(uname -o) == Android ]; then
            if grep -q "Match Address \*,!127.0.0.1" $PREFIX/etc/ssh/sshd_config; then
                sed -i '/Match Address \*,!127.0.0.1/,/^$/d' $PREFIX/etc/ssh/sshd_config
            fi
            echo -e "Match Address *,!127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication yes\n    PubkeyAuthentication yes\n" >>$PREFIX/etc/ssh/sshd_config
            RESTART_SSHD=2
        else
            if grep -q "Match Address \*,!127.0.0.1" /etc/ssh/sshd_config; then
                $SUDO sed -i '/Match Address \*,!127.0.0.1/,/^$/d' /etc/ssh/sshd_config
            fi
            $SUDO echo -e "Match Address *,!127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication yes\n    PubkeyAuthentication yes\n" >>/etc/ssh/sshd_config
            RESTART_SSHD=1
        fi
    else
        echo -e "不允许远程密码登录root用户,但允许ssh-key 登陆"
        if [ $(uname -o) == Android ]; then
            if grep -q "Match Address \*,!127.0.0.1" $PREFIX/etc/ssh/sshd_config; then
                sed -i '/Match Address \*,!127.0.0.1/,/^$/d' $PREFIX/etc/ssh/sshd_config
            fi
            echo -e "Match Address *,!127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication no\n    PubkeyAuthentication yes\n" >>$PREFIX/etc/ssh/sshd_config
            RESTART_SSHD=2
        else
            if grep -q "Match Address \*,!127.0.0.1" /etc/ssh/sshd_config; then
                $SUDO sed -i '/Match Address \*,!127.0.0.1/,/^$/d' /etc/ssh/sshd_config
            fi
            $SUDO echo -e "Match Address *,!127.0.0.1\n    PermitRootLogin yes\n    PasswordAuthentication no\n    PubkeyAuthentication yes\n" >>/etc/ssh/sshd_config
            RESTART_SSHD=1
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
        # disable_password
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

if [ "$RESTART_SSHD" = 1 ]; then
    echo -e "${INFO} Restarting sshd..."
    $SUDO systemctl restart sshd && echo -e "${INFO} Done."
elif [ "$RESTART_SSHD" = 2 ]; then
    echo -e "${INFO} Restart sshd or Termux App to take effect."
fi

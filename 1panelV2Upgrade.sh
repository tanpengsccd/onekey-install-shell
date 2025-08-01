#!/bin/bash

# 1Panel迁移工具自动化脚本
# 版本: 1.0
# 功能: 自动化1Panel的安装、升级和回滚操作

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
GITEE_RELEASES_URL="https://gitee.com/fit2cloud-feizhiyun/1panel-migrator/releases/"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="1panel-migrator"
TMP_DIR="/tmp"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检测系统架构
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm"
            ;;
        ppc64le)
            echo "ppc64le"
            ;;
        s390x)
            echo "s390x"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# 显示帮助信息
show_help() {
    echo "1Panel迁移工具自动化脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  install               安装1panel-migrator工具"
    echo "  upgrade-master        升级为主节点（包含服务和网站升级）"
    echo "  upgrade-slave         升级为从节点（包含服务升级）"
    echo "  upgrade-slave-web     从节点网站升级（在主节点添加从节点后执行）"
    echo "  rollback              完整回滚（包含服务和网站回滚）"
    echo "  rollback-service      仅回滚服务"
    echo "  rollback-website      仅回滚网站"
    echo "  status                检查工具状态"
    echo "  help                  显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 install            # 安装迁移工具"
    echo "  $0 upgrade-master     # 升级为主节点"
    echo "  $0 upgrade-slave      # 升级为从节点"
    echo "  $0 rollback           # 完整回滚"
}

# 检查工具是否已安装
check_installed() {
    if command -v $BINARY_NAME &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 安装1panel-migrator
install_migrator() {
    log_info "开始安装1panel-migrator工具..."
    
    local arch=$(detect_architecture)
    local binary_name="${BINARY_NAME}-linux-${arch}"
    
    log_info "检测到系统架构: $arch"
    log_info "二进制文件名: $binary_name"
    
    # 检查临时目录中是否存在文件
    if [[ ! -f "$TMP_DIR/$binary_name" ]]; then
        log_error "未找到安装包: $TMP_DIR/$binary_name"
        log_info "请从以下地址下载对应架构的安装包并放置到 $TMP_DIR 目录："
        log_info "$GITEE_RELEASES_URL"
        exit 1
    fi
    
    # 进入临时目录
    cd $TMP_DIR
    
    # 添加执行权限
    log_info "添加执行权限..."
    chmod +x $binary_name
    
    # 移动到系统PATH并重命名
    log_info "安装到系统目录..."
    mv $binary_name $INSTALL_DIR/$BINARY_NAME
    
    # 验证安装
    if check_installed; then
        log_success "1panel-migrator安装成功！"
        log_info "版本信息："
        $BINARY_NAME --version 2>/dev/null || echo "工具已安装到 $INSTALL_DIR/$BINARY_NAME"
    else
        log_error "安装失败"
        exit 1
    fi
}

# 升级为主节点
upgrade_master() {
    log_info "开始升级为主节点..."
    
    if ! check_installed; then
        log_error "1panel-migrator未安装，请先运行: $0 install"
        exit 1
    fi
    
    # 升级服务
    log_info "步骤1: 升级服务..."
    $BINARY_NAME upgrade core
    
    log_success "服务升级完成"
    log_warning "请确保V2服务启动成功后再继续..."
    
    # 询问是否继续网站升级
    read -p "V2服务是否已启动成功？继续网站升级吗？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "步骤2: 升级网站..."
        $BINARY_NAME upgrade website
        log_success "主节点升级完成！"
    else
        log_warning "网站升级已跳过，请在V2服务启动后手动执行: $BINARY_NAME upgrade website"
    fi
}

# 升级为从节点
upgrade_slave() {
    log_info "开始升级为从节点..."
    
    if ! check_installed; then
        log_error "1panel-migrator未安装，请先运行: $0 install"
        exit 1
    fi
    
    # 升级服务
    log_info "升级从节点服务..."
    $BINARY_NAME upgrade agent
    
    log_success "从节点服务升级完成！"
    log_warning "请在主节点的【节点管理】页面添加此从节点"
    log_warning "添加完成后，请运行: $0 upgrade-slave-web 完成网站升级"
}

# 从节点网站升级
upgrade_slave_website() {
    log_info "开始从节点网站升级..."
    
    if ! check_installed; then
        log_error "1panel-migrator未安装，请先运行: $0 install"
        exit 1
    fi
    
    log_warning "请确保已在主节点添加此从节点"
    read -p "是否已在主节点添加此从节点？(y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "执行网站升级..."
        $BINARY_NAME upgrade website
        log_success "从节点网站升级完成！"
    else
        log_warning "请先在主节点添加此从节点，然后再执行网站升级"
        exit 1
    fi
}

# 完整回滚
rollback_full() {
    log_info "开始完整回滚..."
    
    if ! check_installed; then
        log_error "1panel-migrator未安装"
        exit 1
    fi
    
    log_warning "此操作将回滚到1Panel V1版本，是否继续？"
    read -p "确认回滚？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "回滚操作已取消"
        exit 0
    fi
    
    # 回滚服务
    log_info "步骤1: 回滚服务..."
    $BINARY_NAME rollback service
    
    log_success "服务回滚完成"
    log_warning "请确保V1服务启动成功后再继续..."
    
    # 询问是否继续网站回滚
    read -p "V1服务是否已启动成功？继续网站回滚吗？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "步骤2: 回滚网站..."
        $BINARY_NAME rollback website
        log_success "完整回滚完成！"
    else
        log_warning "网站回滚已跳过，请在V1服务启动后手动执行: $BINARY_NAME rollback website"
    fi
}

# 仅回滚服务
rollback_service() {
    log_info "开始回滚服务..."
    
    if ! check_installed; then
        log_error "1panel-migrator未安装"
        exit 1
    fi
    
    $BINARY_NAME rollback service
    log_success "服务回滚完成！"
}

# 仅回滚网站
rollback_website() {
    log_info "开始回滚网站..."
    
    if ! check_installed; then
        log_error "1panel-migrator未安装"
        exit 1
    fi
    
    log_warning "请确保V1服务已启动成功"
    read -p "V1服务是否已启动成功？(y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $BINARY_NAME rollback website
        log_success "网站回滚完成！"
    else
        log_warning "请在V1服务启动后再执行网站回滚"
        exit 1
    fi
}

# 检查状态
check_status() {
    log_info "检查1panel-migrator状态..."
    
    if check_installed; then
        log_success "1panel-migrator 已安装"
        log_info "安装路径: $INSTALL_DIR/$BINARY_NAME"
        
        # 尝试显示版本信息
        if $BINARY_NAME --version &> /dev/null; then
            log_info "版本信息: $($BINARY_NAME --version)"
        else
            log_info "工具可用，但无法获取版本信息"
        fi
    else
        log_warning "1panel-migrator 未安装"
        log_info "请运行: $0 install 进行安装"
    fi
}

# 主函数
main() {
    # 检查root权限
    check_root
    
    case "${1:-help}" in
        "install")
            install_migrator
            ;;
        "upgrade-master")
            upgrade_master
            ;;
        "upgrade-slave")
            upgrade_slave
            ;;
        "upgrade-slave-web")
            upgrade_slave_website
            ;;
        "rollback")
            rollback_full
            ;;
        "rollback-service")
            rollback_service
            ;;
        "rollback-website")
            rollback_website
            ;;
        "status")
            check_status
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# 执行主函数
main "$@"

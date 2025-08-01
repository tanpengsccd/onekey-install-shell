#!/bin/bash

# 1Panel迁移工具自动化脚本
# 版本: 2.1
# 功能: 自动化1Panel的安装、升级和回滚操作，支持自动获取最新版本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 配置变量
GITEE_API_URL="https://gitee.com/api/v5/repos/fit2cloud-feizhiyun/1panel-migrator/releases/latest"
GITHUB_API_URL="https://api.github.com/repos/fit2cloud-feizhiyun/1panel-migrator/releases/latest"
GITEE_BASE_URL="https://gitee.com/fit2cloud-feizhiyun/1panel-migrator/releases/download"
GITHUB_BASE_URL="https://github.com/fit2cloud-feizhiyun/1panel-migrator/releases/download"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="1panel-migrator"
TMP_DIR="/tmp"
CACHE_FILE="/tmp/.1panel_migrator_version_cache"
CACHE_DURATION=3600  # 缓存1小时

# 全局变量
LATEST_VERSION=""
USE_SPECIFIC_VERSION=""

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

log_download() {
    echo -e "${CYAN}[DOWNLOAD]${NC} $1"
}

log_version() {
    echo -e "${PURPLE}[VERSION]${NC} $1"
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

# 检查网络连接和工具
check_network_tools() {
    local missing_tools=()
    
    # 检查下载工具
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        missing_tools+=("wget或curl")
    fi
    
    # 检查JSON解析工具
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "缺少必要工具: ${missing_tools[*]}"
        log_info "请安装缺少的工具："
        
        if [[ " ${missing_tools[*]} " =~ " wget或curl " ]]; then
            log_info "  Ubuntu/Debian: apt-get update && apt-get install -y wget curl"
            log_info "  CentOS/RHEL: yum install -y wget curl"
        fi
        
        if [[ " ${missing_tools[*]} " =~ " jq " ]]; then
            log_info "  Ubuntu/Debian: apt-get install -y jq"
            log_info "  CentOS/RHEL: yum install -y jq"
        fi
        
        exit 1
    fi
}

# HTTP请求函数
http_get() {
    local url=$1
    local output_file=$2
    
    if command -v curl &> /dev/null; then
        if [[ -n "$output_file" ]]; then
            curl -s -L -o "$output_file" "$url" 2>/dev/null
        else
            curl -s -L "$url" 2>/dev/null
        fi
    elif command -v wget &> /dev/null; then
        if [[ -n "$output_file" ]]; then
            wget -q -O "$output_file" "$url" 2>/dev/null
        else
            wget -q -O - "$url" 2>/dev/null
        fi
    else
        return 1
    fi
}

# 检查版本缓存
check_version_cache() {
    if [[ -f "$CACHE_FILE" ]]; then
        local cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        local current_time=$(date +%s)
        local age=$((current_time - cache_time))
        
        if [[ $age -lt $CACHE_DURATION ]]; then
            LATEST_VERSION=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
            if [[ -n "$LATEST_VERSION" ]]; then
                log_info "使用缓存版本信息: $LATEST_VERSION (缓存剩余: $(((CACHE_DURATION - age) / 60))分钟)"
                return 0
            fi
        fi
    fi
    return 1
}

# 保存版本缓存
save_version_cache() {
    if [[ -n "$LATEST_VERSION" ]]; then
        echo "$LATEST_VERSION" > "$CACHE_FILE" 2>/dev/null || true
    fi
}

# 获取最新版本
get_latest_version() {
    # 如果指定了版本，直接使用
    if [[ -n "$USE_SPECIFIC_VERSION" ]]; then
        LATEST_VERSION="$USE_SPECIFIC_VERSION"
        log_version "使用指定版本: $LATEST_VERSION"
        return 0
    fi
    
    # 检查缓存
    if check_version_cache; then
        return 0
    fi
    
    log_info "正在获取最新版本信息..."
    
    # API源列表
    local apis=(
        "$GITEE_API_URL"
        "$GITHUB_API_URL"
    )
    
    local sources=("Gitee" "GitHub")
    
    for i in "${!apis[@]}"; do
        local api_url="${apis[$i]}"
        local source="${sources[$i]}"
        
        log_info "尝试从 $source API 获取版本信息..."
        
        local response=$(http_get "$api_url")
        if [[ $? -eq 0 && -n "$response" ]]; then
            # 尝试解析JSON获取tag_name
            local version=$(echo "$response" | jq -r '.tag_name // empty' 2>/dev/null)
            
            if [[ -n "$version" && "$version" != "null" ]]; then
                LATEST_VERSION="$version"
                log_success "从 $source 获取到最新版本: $LATEST_VERSION"
                save_version_cache
                return 0
            else
                log_warning "从 $source 获取的数据格式异常"
            fi
        else
            log_warning "从 $source API 获取失败"
        fi
    done
    
    # 如果所有API都失败，尝试使用默认版本
    log_error "无法获取最新版本信息"
    log_warning "将使用默认版本 v2.0.9"
    LATEST_VERSION="v2.0.9"
    return 1
}

# 下载文件函数
download_file() {
    local url=$1
    local output=$2
    local description=$3
    
    log_download "正在下载 $description..."
    log_info "下载地址: $url"
    
    if command -v wget &> /dev/null; then
        if wget --progress=bar:force --show-progress -q -O "$output" "$url" 2>&1; then
            return 0
        else
            return 1
        fi
    elif command -v curl &> /dev/null; then
        if curl -L --progress-bar -o "$output" "$url"; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# 尝试多个下载源
download_with_fallback() {
    local arch=$1
    local version=$2
    local binary_name="${BINARY_NAME}-linux-${arch}"
    local output_file="$TMP_DIR/$binary_name"
    
    # 下载源列表
    local urls=(
        "$GITEE_BASE_URL/$version/$binary_name"
        "$GITHUB_BASE_URL/$version/$binary_name"
    )
    
    local sources=("Gitee" "GitHub")
    
    for i in "${!urls[@]}"; do
        local url="${urls[$i]}"
        local source="${sources[$i]}"
        
        log_info "尝试从 $source 下载..."
        if download_file "$url" "$output_file" "$source ($binary_name)"; then
            log_success "从 $source 下载成功！"
            return 0
        else
            log_warning "从 $source 下载失败，尝试下一个源..."
        fi
    done
    
    log_error "所有下载源都失败了"
    return 1
}

# 显示帮助信息
show_help() {
    echo "1Panel迁移工具自动化脚本 v2.1"
    echo "支持自动获取最新版本的 1panel-migrator"
    echo ""
    echo "用法: $0 [选项] [参数]"
    echo ""
    echo "选项:"
    echo "  install [版本]        安装1panel-migrator工具（自动获取最新版本）"
    echo "  install-local         从本地文件安装（需手动下载到/tmp目录）"
    echo "  upgrade-master        升级为主节点（包含服务和网站升级）"
    echo "  upgrade-slave         升级为从节点（包含服务升级）"
    echo "  upgrade-slave-web     从节点网站升级（在主节点添加从节点后执行）"
    echo "  rollback              完整回滚（包含服务和网站回滚）"
    echo "  rollback-service      仅回滚服务"
    echo "  rollback-website      仅回滚网站"
    echo "  status                检查工具状态"
    echo "  version               显示版本信息"
    echo "  check-latest          检查最新版本"
    echo "  clear-cache           清除版本缓存"
    echo "  help                  显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 install            # 自动获取最新版本并安装"
    echo "  $0 install v2.0.8     # 安装指定版本"
    echo "  $0 check-latest       # 检查最新版本"
    echo "  $0 upgrade-master     # 升级为主节点"
    echo "  $0 clear-cache        # 清除版本缓存"
    echo ""
    echo "支持的架构: amd64, arm64, arm, ppc64le, s390x"
}

# 检查工具是否已安装
check_installed() {
    if command -v $BINARY_NAME &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 获取已安装版本
get_installed_version() {
    if check_installed; then
        # 尝试多种方式获取版本信息
        local version_output=""
        
        # 方法1: 尝试 --version 参数
        version_output=$($BINARY_NAME --version 2>/dev/null || echo "")
        if [[ -n "$version_output" && "$version_output" != "unknown" ]]; then
            echo "$version_output"
            return 0
        fi
        
        # 方法2: 尝试 -v 参数
        version_output=$($BINARY_NAME -v 2>/dev/null || echo "")
        if [[ -n "$version_output" && "$version_output" != "unknown" ]]; then
            echo "$version_output"
            return 0
        fi
        
        # 方法3: 尝试 version 子命令
        version_output=$($BINARY_NAME version 2>/dev/null || echo "")
        if [[ -n "$version_output" && "$version_output" != "unknown" ]]; then
            echo "$version_output"
            return 0
        fi
        
        # 方法4: 检查文件时间戳作为版本参考
        if [[ -f "$INSTALL_DIR/$BINARY_NAME" ]]; then
            local file_date=$(stat -c %y "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null | cut -d' ' -f1)
            echo "installed-$file_date"
        else
            echo "unknown"
        fi
    else
        echo "not_installed"
    fi
}

# 检查最新版本
check_latest_version() {
    log_info "检查最新版本..."
    
    if get_latest_version; then
        log_version "最新版本: $LATEST_VERSION"
        
        if check_installed; then
            local current_version=$(get_installed_version)
            log_info "当前安装版本: $current_version"
            
            if [[ "$current_version" == *"$LATEST_VERSION"* ]]; then
                log_success "您已安装最新版本！"
            else
                log_warning "发现新版本可用，建议更新"
                log_info "运行 '$0 install' 更新到最新版本"
            fi
        else
            log_warning "工具未安装"
            log_info "运行 '$0 install' 安装最新版本"
        fi
    else
        log_error "无法检查最新版本"
    fi
}

# 清除缓存
clear_cache() {
    if [[ -f "$CACHE_FILE" ]]; then
        rm -f "$CACHE_FILE"
        log_success "版本缓存已清除"
    else
        log_info "缓存文件不存在"
    fi
}

# 自动下载并安装1panel-migrator
install_migrator() {
    local specified_version="$1"
    
    # 如果指定了版本，使用指定版本
    if [[ -n "$specified_version" ]]; then
        USE_SPECIFIC_VERSION="$specified_version"
        log_info "将安装指定版本: $specified_version"
    fi
    
    log_info "开始安装1panel-migrator工具..."
    
    # 检查网络和工具
    check_network_tools
    
    # 获取版本信息
    if ! get_latest_version; then
        log_warning "版本获取出现问题，但将继续使用默认版本"
    fi
    
    local arch=$(detect_architecture)
    local binary_name="${BINARY_NAME}-linux-${arch}"
    local temp_file="$TMP_DIR/$binary_name"
    
    log_info "检测到系统架构: $arch"
    log_info "目标版本: $LATEST_VERSION"
    
    # 检查是否已安装
    if check_installed; then
        local current_version=$(get_installed_version)
        log_warning "检测到已安装版本: $current_version"
        
        if [[ "$current_version" == *"$LATEST_VERSION"* ]]; then
            log_success "已安装目标版本，无需重复安装"
            read -p "是否强制重新安装？(y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "安装已取消"
                exit 0
            fi
        elif [[ "$current_version" == "unknown" || "$current_version" == installed-* ]]; then
            log_warning "当前版本信息不明确，建议重新安装"
            read -p "是否重新安装？(Y/n): " -r
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                log_info "安装已取消"
                exit 0
            fi
        else
            read -p "是否覆盖安装？(y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "安装已取消"
                exit 0
            fi
        fi
    fi
    
    # 进入临时目录
    cd $TMP_DIR
    
    # 清理旧文件
    if [[ -f "$temp_file" ]]; then
        log_info "清理旧的临时文件..."
        rm -f "$temp_file"
    fi
    
    # 下载文件
    if ! download_with_fallback "$arch" "$LATEST_VERSION"; then
        log_error "下载失败，请检查网络连接或手动下载"
        log_info "手动下载地址："
        log_info "  Gitee: $GITEE_BASE_URL/$LATEST_VERSION/$binary_name"
        log_info "  GitHub: $GITHUB_BASE_URL/$LATEST_VERSION/$binary_name"
        log_info "下载后请运行: $0 install-local"
        exit 1
    fi
    
    # 验证下载的文件
    if [[ ! -f "$temp_file" ]] || [[ ! -s "$temp_file" ]]; then
        log_error "下载的文件不存在或为空"
        exit 1
    fi
    
    # 添加执行权限
    log_info "添加执行权限..."
    chmod +x "$temp_file"
    
    # 移动到系统PATH并重命名
    log_info "安装到系统目录..."
    mv "$temp_file" "$INSTALL_DIR/$BINARY_NAME"
    
    # 验证安装
    if check_installed; then
        log_success "1panel-migrator 安装成功！"
        local installed_version=$(get_installed_version)
        log_info "安装版本: $installed_version"
        log_info "安装路径: $INSTALL_DIR/$BINARY_NAME"
    else
        log_error "安装失败"
        exit 1
    fi
}

# 从本地文件安装
install_local() {
    log_info "从本地文件安装1panel-migrator工具..."
    
    local arch=$(detect_architecture)
    local binary_name="${BINARY_NAME}-linux-${arch}"
    
    log_info "检测到系统架构: $arch"
    log_info "查找本地文件: $binary_name"
    
    # 检查临时目录中是否存在文件
    if [[ ! -f "$TMP_DIR/$binary_name" ]]; then
        log_error "未找到本地安装包: $TMP_DIR/$binary_name"
        log_info "请手动下载对应架构的安装包并放置到 $TMP_DIR 目录"
        log_info "或者运行: $0 install 进行自动下载"
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
        log_success "1panel-migrator 安装成功！"
        local installed_version=$(get_installed_version)
        log_info "安装版本: $installed_version"
        log_info "安装路径: $INSTALL_DIR/$BINARY_NAME"
    else
        log_error "安装失败"
        exit 1
    fi
}

# 智能升级（自动安装工具如果未安装）
smart_upgrade() {
    if ! check_installed; then
        log_warning "1panel-migrator 未安装，正在自动安装最新版本..."
        install_migrator
        log_info "工具安装完成，继续升级流程..."
    else
        local current_version=$(get_installed_version)
        
        # 只在能够获取网络版本信息时进行版本比较
        if command -v jq &> /dev/null && get_latest_version &>/dev/null; then
            if [[ "$current_version" != *"$LATEST_VERSION"* ]] && [[ "$current_version" != "unknown" ]]; then
                log_warning "检测到新版本 $LATEST_VERSION，当前版本: $current_version"
                read -p "是否更新到最新版本？(y/N): " -r
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    install_migrator
                fi
            else
                log_info "当前工具版本: $current_version"
            fi
        else
            log_info "跳过版本检查，使用当前已安装的工具"
            log_info "当前工具版本: $current_version"
        fi
    fi
}

# 升级为主节点
upgrade_master() {
    log_info "开始升级为主节点..."
    
    smart_upgrade
    
    # 升级服务
    log_info "步骤1: 升级服务..."
    log_warning "即将开始服务升级，这会停止当前1Panel V1服务"
    
    # 执行服务升级
    if $BINARY_NAME upgrade core; then
        log_success "服务升级命令执行完成"
    else
        local exit_code=$?
        if [[ $exit_code -eq 1 ]]; then
            log_error "升级失败：当前版本过低，需要先在1Panel控制台更新到v1.10.29-lts或更高版本"
            log_info "请先在1Panel控制台右下角手动更新到最新版本，然后重新运行此脚本"
            exit 1
        else
            log_error "服务升级失败，退出码: $exit_code"
            exit 1
        fi
    fi
    
    log_warning "请检查V2服务是否正常启动"
    log_info "可以通过以下方式检查："
    log_info "  - 访问1Panel Web界面"
    log_info "  - 检查服务状态: systemctl status 1panel-core"
    log_info "  - 查看日志: journalctl -u 1panel-core -f"
    
    # 询问是否继续网站升级
    echo ""
    read -p "V2服务是否已正常启动？继续网站升级吗？(y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "步骤2: 升级网站..."
        log_warning "即将开始网站升级，升级期间网站将不可访问"
        
        if $BINARY_NAME upgrade website; then
            log_success "主节点升级完成！"
            log_info "升级完成后建议："
            log_info "  1. 检查所有网站是否正常访问"
            log_info "  2. 重新配置反代缓存（如需要）"
            log_info "  3. 检查PHP网站设置（静态网站可切换回PHP）"
        else
            log_error "网站升级失败"
            log_warning "请检查错误信息，必要时可以回滚: $0 rollback"
            exit 1
        fi
    else
        log_warning "网站升级已跳过"
        log_info "V2服务启动后，请手动执行网站升级:"
        log_info "  $BINARY_NAME upgrade website"
        log_info "或运行: $0 upgrade-master"
    fi
}

# 升级为从节点
upgrade_slave() {
    log_info "开始升级为从节点..."
    
    smart_upgrade
    
    # 升级服务
    log_info "升级从节点服务..."
    log_warning "即将开始从节点服务升级"
    
    if $BINARY_NAME upgrade agent; then
        log_success "从节点服务升级完成！"
        log_warning "请在主节点的【节点管理】页面添加此从节点"
        log_info "添加步骤："
        log_info "  1. 登录主节点1Panel控制台"
        log_info "  2. 导航到【节点管理】页面"
        log_info "  3. 点击【添加节点】"
        log_info "  4. 输入此服务器的IP地址和端口"
        log_info "  5. 系统会自动识别并处理V1历史数据"
        log_warning "添加完成后，请运行: $0 upgrade-slave-web 完成网站升级"
    else
        log_error "从节点服务升级失败"
        exit 1
    fi
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
        local current_version=$(get_installed_version)
        log_success "1panel-migrator 已安装"
        log_info "安装路径: $INSTALL_DIR/$BINARY_NAME"
        
        # 显示文件信息
        if [[ -f "$INSTALL_DIR/$BINARY_NAME" ]]; then
            local file_size=$(stat -c %s "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null)
            local file_date=$(stat -c %y "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null | cut -d' ' -f1)
            log_info "文件大小: $(numfmt --to=iec $file_size)B"
            log_info "文件日期: $file_date"
        fi
        
        log_info "版本信息: $current_version"
        
        # 检查最新版本
        if command -v jq &> /dev/null; then
            if get_latest_version &>/dev/null; then
                log_info "最新版本: $LATEST_VERSION"
                
                # 简化版本比较逻辑
                if [[ "$current_version" == *"$LATEST_VERSION"* ]]; then
                    log_success "版本匹配最新版本"
                elif [[ "$current_version" == "unknown" ]]; then
                    log_warning "无法获取当前版本信息，但工具已正确安装"
                    log_info "运行以下命令重新安装: $0 install"
                else
                    log_warning "可能有新版本可用"
                    log_info "运行以下命令更新: $0 install"
                fi
            else
                log_warning "无法检查最新版本信息（网络问题）"
            fi
        else
            log_warning "缺少jq工具，无法检查最新版本"
            log_info "安装jq: apt-get install jq 或 yum install jq"
        fi
        
        # 检查工具是否可执行
        if $BINARY_NAME --help &>/dev/null || $BINARY_NAME help &>/dev/null; then
            log_success "工具运行正常"
        else
            log_warning "工具可能存在问题，建议重新安装"
        fi
        
    else
        log_warning "1panel-migrator 未安装"
        log_info "请运行: $0 install 进行自动安装"
    fi
}

# 显示版本信息
show_version() {
    echo "1Panel迁移工具自动化脚本"
    echo "脚本版本: 2.1"
    echo "功能: 自动获取最新版本的1panel-migrator"
    echo "支持的架构: amd64, arm64, arm, ppc64le, s390x"
    echo ""
    
    if check_installed; then
        local current_version=$(get_installed_version)
        echo "已安装版本: $current_version"
    else
        echo "工具状态: 未安装"
    fi
    
    # 尝试获取最新版本
    if check_network_tools &>/dev/null && get_latest_version &>/dev/null; then
        echo "最新版本: $LATEST_VERSION"
    else
        echo "最新版本: 无法获取"
    fi
}

# 主函数
main() {
    # 检查root权限
    check_root
    
    case "${1:-help}" in
        "install")
            install_migrator "$2"
            ;;
        "install-local")
            install_local
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
        "version")
            show_version
            ;;
        "check-latest")
            check_latest_version
            ;;
        "clear-cache")
            clear_cache
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# 执行主函数
main "$@"

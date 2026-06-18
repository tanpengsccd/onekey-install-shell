#!/bin/bash
# ============================================================
#  哪吒面板入侵 自查/修复脚本 (nezha_ioc_check_delete.sh)
# ------------------------------------------------------------
#  用途:排查 2026-06 哪吒面板漏洞批量入侵的常见植入物
#  模式:
#    只读检测(默认): 仅检测不修改,可放心运行
#    修复模式(--fix / -x): 检测并自动清理植入物(危险,需确认)
#    GitHub 公钥(-g): 从 GitHub 获取公钥添加到 authorized_keys
#    修改密码(-p): 修改 root 用户密码
#  用法:
#    bash nezha_ioc_check_delete.sh                       # 只读检测
#    bash nezha_ioc_check_delete.sh --fix                 # 检测 + 自动修复
#    bash nezha_ioc_check_delete.sh -g <github_id>        # 检测 + 添加 GitHub 公钥
#    bash nezha_ioc_check_delete.sh -p '<new_password>'   # 检测 + 修改 root 密码
#    或批量: ssh 节点 'bash -s' < nezha_ioc_check_delete.sh
#           ssh 节点 'bash -s -- --fix -g <id> -p <pwd>' < nezha_ioc_check_delete.sh
# ------------------------------------------------------------
#  发现 [警] 即需处理;
#  不加 --fix 时显示 💡处理建议 和命令,加 --fix 则自动执行。
#  加 -g 可在清除后门公钥后,自动添加自己的 GitHub 公钥。
#  加 -p 可修改 root 密码(入侵后务必修改)。
# ============================================================

FIX_MODE=0
GITHUB_USER=""
GITHUB_KEY_OK=0
ROOT_PASSWD=""
ROOT_PASSWD_OK=0

# 解析参数
while [ $# -gt 0 ]; do
  case "$1" in
    --fix|-x) FIX_MODE=1 ;;
    -g) GITHUB_USER="$2"; shift ;;
    -p) ROOT_PASSWD="$2"; shift ;;
  esac
  shift
done

# ------------------------------------------------------------
# 辅助函数:只读模式打印修复建议,fix 模式执行修复命令
# 用法: fix_it "描述" "命令"
# ------------------------------------------------------------
fix_it() {
  local desc="$1"
  local cmd="$2"
  if [ "$FIX_MODE" -eq 1 ]; then
    echo "  [修复] $desc"
    if eval "$cmd" 2>/dev/null; then
      echo "  [完成] ✓"
    else
      echo "  [失败] ✗ (可能需要 root 权限或已不存在)"
    fi
  else
    echo "  💡 处理: $desc"
    echo "     命令: $cmd"
  fi
}

# 仅打印建议,永不自动执行(用于需人工判断的项)
suggest_only() {
  local desc="$1"
  local cmd="$2"
  echo "  💡 处理: $desc"
  echo "     命令: $cmd"
  echo "     ⚠️  此项需人工确认,不会自动执行"
}

# 从 GitHub 获取用户公钥
get_github_key() {
  local user="$1"
  echo "[GitHub] 获取 $user 的公钥..."
  PUB_KEY=$(curl -fsSL "https://github.com/${user}.keys" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$PUB_KEY" ]; then
    # GitHub API 某些地区不通,尝试代理
    PUB_KEY=$(curl -fsSL "https://rp.j8.work/https://github.com/${user}.keys" 2>/dev/null)
  fi
  if [ -z "$PUB_KEY" ]; then
    echo "  [错误] GitHub 账号 $user 无公钥或获取失败"
    return 1
  elif echo "$PUB_KEY" | grep -qi "Not Found"; then
    echo "  [错误] GitHub 账号 $user 不存在"
    return 1
  fi
  return 0
}

# 安装公钥到 authorized_keys (覆盖模式,-g 默认行为)
install_github_key() {
  if [ -z "$PUB_KEY" ]; then
    echo "  [错误] 没有获取到公钥,无法安装"
    return 1
  fi
  local ak="$HOME/.ssh/authorized_keys"
  # 确保 .ssh 目录存在
  if [ ! -d "$HOME/.ssh" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
  fi
  # 覆盖写入
  echo "$PUB_KEY" >"$ak"
  chmod 600 "$ak"
  local key_count=$(echo "$PUB_KEY" | wc -l | tr -d ' ')
  echo "  [结果] 已覆盖写入 $key_count 个公钥到 authorized_keys"
}

# 修改 root 密码
change_root_password() {
  local pwd="$1"
  if [ -z "$pwd" ]; then
    echo "  [错误] 密码不能为空"
    return 1
  fi
  echo "  [执行] 正在修改 root 密码..."
  if echo "root:$pwd" | chpasswd 2>/dev/null; then
    echo "  [完成] ✓ root 密码已修改"
    return 0
  elif echo "$pwd" | passwd --stdin root 2>/dev/null; then
    echo "  [完成] ✓ root 密码已修改"
    return 0
  else
    echo "  [失败] ✗ 密码修改失败(可能需要 root 权限)"
    return 1
  fi
}

ALERT=0
echo "=========================================="
echo " 哪吒入侵自查: $(hostname)  $(date '+%F %T')"
[ "$FIX_MODE" -eq 1 ] && echo " >>> 修复模式已启用 <<<"
echo "=========================================="

# ---- 1) memfd 内存马 ----
# 攻击者用 memfd_create 把恶意程序只放在内存、磁盘无文件,
# 常伪装成 [kworker/x:x]。靠 /proc/PID/exe 指向 memfd 识别。
echo "[1] memfd 内存马"
memfd_found=0
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
  if ls -l /proc/$pid/exe 2>/dev/null | grep -qi "memfd"; then
    echo "  [警] PID $pid 指向 memfd  cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
    ALERT=1
    fix_it "终止 memfd 进程 PID $pid" "kill -9 $pid"
    memfd_found=1
  fi
done
[ "$memfd_found" -eq 0 ] && echo "  未发现"

# ---- 2) kworker 伪装(进程名像内核线程,却有用户态 exe)----
# 真内核线程父进程是 kthreadd(PID 2)且无 exe;伪装的则有真实 exe。
# 注:请把下面 EXCLUDE 里换成你自己合法的、恰好以 k 开头的程序名(如 komari)。
EXCLUDE_COMM="kdump|komari|kubelet"
echo "[2] kworker 伪装进程"
kworker_found=0
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
  comm=$(cat /proc/$pid/comm 2>/dev/null)
  exe=$(readlink /proc/$pid/exe 2>/dev/null)
  ppid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null)
  case "$comm" in
    k*)
      if [ -n "$exe" ] && [ "$ppid" != "2" ]; then
        if ! echo "$comm" | grep -qE "^($EXCLUDE_COMM)" && [ "${exe#*/usr/lib/systemd/}" = "$exe" ]; then
          echo "  [警] PID $pid 进程名=$comm 父=$ppid exe=$exe"
          ALERT=1
          fix_it "终止伪装 kworker 进程 PID $pid (⚠️ 请确认非业务进程)" "kill -9 $pid"
          kworker_found=1
        fi
      fi
      ;;
  esac
done
[ "$kworker_found" -eq 0 ] && echo "  未发现"

# ---- 3) 执行已删除文件的进程((deleted))----
# 程序跑起来后删掉自身文件,只留内存副本。排除正常软件路径与升级残留。
# 注:把 /app 换成你自己正常程序所在目录,避免误报。
echo "[3] 已删除文件执行"
deleted_found=0
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
  exe=$(readlink /proc/$pid/exe 2>/dev/null)
  case "$exe" in
    *"(deleted)"*)
      case "$exe" in
        */usr/*|*/bin/*|*/sbin/*|*/app/*|*/snap/*) ;;
        *) echo "  [警] PID $pid exe=$exe"; ALERT=1
           fix_it "终止已删除文件进程 PID $pid" "kill -9 $pid"
           deleted_found=1 ;;
      esac
      ;;
  esac
done
[ "$deleted_found" -eq 0 ] && echo "  未发现"

# ---- 4) 恶意哪吒 Agent(随机后缀 config / service,连第三方主控)----
echo "[4] 恶意哪吒 Agent 残留"
agent_found=0
AGENT_PIDS=$(ps aux | grep -i 'nezha-agent' | grep -v grep | grep -E 'config-[a-z0-9]+\.yml' | awk '{print $2}')
ps aux | grep -i 'nezha-agent' | grep -v grep | grep -E 'config-[a-z0-9]+\.yml' \
  && { echo "  [警] 发现随机后缀 config 的 agent 进程"; ALERT=1; agent_found=1;
       for pid in $AGENT_PIDS; do
         fix_it "终止恶意 nezha-agent 进程 PID $pid" "kill -9 $pid"
       done; }

AGENT_SVCS=$(ls /etc/systemd/system/ 2>/dev/null | grep -E 'nezha-agent-[a-z0-9]+\.service')
if [ -n "$AGENT_SVCS" ]; then
  echo "$AGENT_SVCS"
  echo "  [警] 发现随机后缀 nezha service"
  ALERT=1; agent_found=1
  for svc in $AGENT_SVCS; do
    fix_it "停止并禁用 $svc" "systemctl stop '$svc' 2>/dev/null; systemctl disable '$svc' 2>/dev/null"
    fix_it "删除 service 文件 /etc/systemd/system/$svc" "rm -f '/etc/systemd/system/$svc'"
  done
  fix_it "重载 systemd daemon" "systemctl daemon-reload"
fi

AGENT_CFGS=$(ls /opt/nezha/agent/config-*.yml 2>/dev/null)
if [ -n "$AGENT_CFGS" ]; then
  echo "$AGENT_CFGS"
  echo "  [警] 发现随机 config 文件"
  ALERT=1; agent_found=1
  for cfg in $AGENT_CFGS; do
    fix_it "删除恶意 config 文件 $cfg" "rm -f '$cfg'"
  done
fi
[ "$agent_found" -eq 0 ] && echo "  未发现"

# ---- 5) 挖矿程序(XMRig / c3pool)----
echo "[5] 挖矿程序"
miner_found=0
if [ -e /root/c3pool ]; then
  echo "  [警] /root/c3pool 目录存在"; ALERT=1; miner_found=1
  fix_it "删除挖矿目录 /root/c3pool" "rm -rf /root/c3pool"
fi
if pgrep -x xmrig >/dev/null 2>&1; then
  echo "  [警] xmrig 进程在运行"; ALERT=1; miner_found=1
  fix_it "终止所有 xmrig 进程" "killall -9 xmrig 2>/dev/null"
fi
if [ -e /etc/systemd/system/c3pool_miner.service ]; then
  echo "  [警] c3pool_miner.service 存在"; ALERT=1; miner_found=1
  fix_it "停止并禁用 c3pool_miner" "systemctl stop c3pool_miner 2>/dev/null; systemctl disable c3pool_miner 2>/dev/null"
  fix_it "删除 c3pool_miner.service" "rm -f /etc/systemd/system/c3pool_miner.service"
  fix_it "重载 systemd daemon" "systemctl daemon-reload"
fi
[ "$miner_found" -eq 0 ] && echo "  未发现"

# ---- 6) traffmonetizer/cli_v2 容器 ----
# 攻击者利用被控机器运行 traffmonetizer 流量套利容器
echo "[6] traffmonetizer 容器"
traff_found=0
if command -v docker &>/dev/null; then
  TRAFF_IDS=$(docker ps -a --filter "ancestor=traffmonetizer/cli_v2:latest" --format "{{.ID}}" 2>/dev/null)
  if [ -n "$TRAFF_IDS" ]; then
    for cid in $TRAFF_IDS; do
      cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
      cimg=$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null)
      echo "  [警] 发现 traffmonetizer 容器 ID=$cid name=$cname image=$cimg"
      ALERT=1; traff_found=1
      fix_it "停止并删除容器 $cid ($cname)" "docker stop '$cid' 2>/dev/null; docker rm -f '$cid' 2>/dev/null"
    done
  fi
fi
[ "$traff_found" -eq 0 ] && echo "  未发现"

# ---- 7) 守护/复活服务(SystemLoger / systemlog.service)----
echo "[7] 守护复活服务"
systemlog_found=0
if pgrep -x SystemLoger >/dev/null 2>&1; then
  echo "  [警] SystemLoger 进程在运行"; ALERT=1; systemlog_found=1
  fix_it "终止所有 SystemLoger 进程" "killall -9 SystemLoger 2>/dev/null"
fi
if [ -e /opt/systemlog ]; then
  echo "  [警] /opt/systemlog 目录存在"; ALERT=1; systemlog_found=1
  fix_it "删除 /opt/systemlog 目录" "rm -rf /opt/systemlog"
fi
if [ -e /etc/systemd/system/systemlog.service ]; then
  echo "  [警] systemlog.service 存在"; ALERT=1; systemlog_found=1
  fix_it "停止并禁用 systemlog.service" "systemctl stop systemlog.service 2>/dev/null; systemctl disable systemlog.service 2>/dev/null"
  fix_it "删除 systemlog.service 文件" "rm -f /etc/systemd/system/systemlog.service"
  fix_it "重载 systemd daemon" "systemctl daemon-reload"
fi
[ "$systemlog_found" -eq 0 ] && echo "  未发现"

# ---- 8) SSH 安全(公钥/配置/触发脚本/PAM)----
echo "[8] SSH 安全"
ssh_found=0

# 8.1 authorized_keys 后门公钥
echo "  [8-1] authorized_keys"
if grep -iq "gary" ~/.ssh/authorized_keys 2>/dev/null; then
  echo "    [警] authorized_keys 含可疑公钥(gary)"; ALERT=1; ssh_found=1
  fix_it "备份 authorized_keys" "cp -f ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak.\$(date +%s)"
  fix_it "删除含 gary 的公钥行" "sed -i.bak '/gary/I d' ~/.ssh/authorized_keys"
fi
echo "    (当前 authorized_keys 公钥数: $(grep -c '^ssh-' ~/.ssh/authorized_keys 2>/dev/null))"

# 8.2 authorized_keys2 (已废弃但部分版本仍读取)
if [ -f ~/.ssh/authorized_keys2 ]; then
  echo "    [警] ~/.ssh/authorized_keys2 存在(已废弃但仍可能被读取):"; cat ~/.ssh/authorized_keys2 | sed 's/^/      /'; ALERT=1; ssh_found=1
  fix_it "备份并删除 authorized_keys2" "cp -f ~/.ssh/authorized_keys2 ~/.ssh/authorized_keys2.bak.\$(date +%s); rm -f ~/.ssh/authorized_keys2"
fi

# 8.3 sshd_config 风险配置(仅提示,不自动修改,防止锁死SSH)
echo "  [8-2] sshd_config 风险配置"
SSHD_CFG=""
for f in /etc/ssh/sshd_config /etc/sshd_config /usr/local/etc/ssh/sshd_config; do
  [ -f "$f" ] && { SSHD_CFG="$f"; break; }
done
if [ -n "$SSHD_CFG" ]; then
  # PermitRootLogin
  if grep -E '^\s*PermitRootLogin\s+yes' "$SSHD_CFG" 2>/dev/null; then
    echo "    [警] PermitRootLogin yes → 允许 root 远程登录"; ALERT=1; ssh_found=1
    suggest_only "建议禁用 root 登录" "sed -i 's/^[[:space:]]*PermitRootLogin.*/PermitRootLogin no/' $SSHD_CFG; systemctl restart sshd"
  fi
  # PasswordAuthentication
  if grep -E '^\s*PasswordAuthentication\s+yes' "$SSHD_CFG" 2>/dev/null; then
    echo "    [警] PasswordAuthentication yes → 允许密码登录(建议只用密钥)"; ALERT=1; ssh_found=1
    suggest_only "建议禁用密码登录" "sed -i 's/^[[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' $SSHD_CFG; systemctl restart sshd"
  fi
  # ChallengeResponseAuthentication
  if grep -E '^\s*ChallengeResponseAuthentication\s+yes' "$SSHD_CFG" 2>/dev/null; then
    echo "    [警] ChallengeResponseAuthentication yes → 允许键盘交互登录"; ALERT=1; ssh_found=1
    suggest_only "建议禁用键盘交互" "sed -i 's/^[[:space:]]*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' $SSHD_CFG; systemctl restart sshd"
  fi
  # AuthorizedKeysCommand (攻击者常用此后门)
  if grep -E '^\s*AuthorizedKeysCommand\s+[^#]' "$SSHD_CFG" 2>/dev/null; then
    echo "    [警] AuthorizedKeysCommand 已设置(攻击者常用此后门):"; grep 'AuthorizedKeysCommand' "$SSHD_CFG" | sed 's/^/      /'; ALERT=1; ssh_found=1
    suggest_only "检查并移除 AuthorizedKeysCommand" "sed -i '/^[[:space:]]*AuthorizedKeysCommand/s/^/#/' $SSHD_CFG; systemctl restart sshd"
  fi
  # AuthorizedKeysFile 指向非标准路径
  if grep -E '^\s*AuthorizedKeysFile\s+' "$SSHD_CFG" 2>/dev/null; then
    akf=$(grep -E '^\s*AuthorizedKeysFile\s+' "$SSHD_CFG")
    echo "    [信息] AuthorizedKeysFile 已指定: $akf (请核对是否非标准路径)"
  fi
  # PermitTunnel + GatewayPorts (可用于反向隧道持久化)
  if grep -E '^\s*PermitTunnel\s+yes' "$SSHD_CFG" 2>/dev/null; then
    echo "    [警] PermitTunnel yes → 允许SSH隧道"; ALERT=1; ssh_found=1
    suggest_only "建议禁用隧道" "sed -i 's/^[[:space:]]*PermitTunnel.*/PermitTunnel no/' $SSHD_CFG; systemctl restart sshd"
  fi
  if grep -E '^\s*GatewayPorts\s+yes' "$SSHD_CFG" 2>/dev/null; then
    echo "    [警] GatewayPorts yes → 允许隧道对外监听(可被用于反弹隧道)"; ALERT=1; ssh_found=1
    suggest_only "建议禁用 GatewayPorts" "sed -i 's/^[[:space:]]*GatewayPorts.*/GatewayPorts no/' $SSHD_CFG; systemctl restart sshd"
  fi
else
  echo "    (未找到 sshd_config)"
fi

# 8.4 登录触发脚本
echo "  [8-3] 登录触发脚本"
if [ -f ~/.ssh/rc ]; then
  echo "    [警] ~/.ssh/rc 存在(SSH登录时自动执行):"; cat ~/.ssh/rc | sed 's/^/      /'; ALERT=1; ssh_found=1
  fix_it "备份并删除 ~/.ssh/rc" "cp -f ~/.ssh/rc ~/.ssh/rc.bak.\$(date +%s); rm -f ~/.ssh/rc"
fi
if [ -f /etc/ssh/sshrc ]; then
  echo "    [警] /etc/ssh/sshrc 存在(全局SSH登录自动执行):"; cat /etc/ssh/sshrc | sed 's/^/      /'; ALERT=1; ssh_found=1
  fix_it "备份并删除 /etc/ssh/sshrc" "cp -f /etc/ssh/sshrc /etc/ssh/sshrc.bak.\$(date +%s); rm -f /etc/ssh/sshrc"
fi

# 8.5 PAM sshd 模块
echo "  [8-4] PAM sshd"
if [ -f /etc/pam.d/sshd ]; then
  # 检查是否有非标准 PAM 模块
  # 排除标准模块: Linux (pam_unix/pam_systemd/...) + macOS (pam_opendirectory/pam_launchd/...)
  # 排除标准模块/指令: pam_* 模块 + @include (Debian/Ubuntu) + substack + auth/account/password/session 关键字行
  PAM_SUS=$(grep -vE '^\s*#|^\s*$' /etc/pam.d/sshd | grep -vE '(^[[:space:]]*@include|^[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_|^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_|^[[:space:]]*auth[[:space:]]+optional[[:space:]]+pam_|^[[:space:]]*auth[[:space:]]+requisite[[:space:]]+pam_|^[[:space:]]*auth[[:space:]]+[[:space:]]+pam_|substack|pam_selinux|pam_loginuid|pam_keyinit|pam_namespace|pam_nologin|pam_unix|pam_systemd|pam_limits|pam_env|pam_mail|pam_motd|pam_deny|pam_permit|pam_access|pam_lastlog|pam_tally|pam_faillock|pam_google_authenticator|pam_duo|pam_krb5|pam_ntlm|pam_mount|pam_opendirectory|pam_sacl|pam_launchd|pam_umask|pam_cap)' || true)
  if [ -n "$PAM_SUS" ]; then
    echo "    [警] PAM sshd 含非标准模块(可能是后门):"; echo "$PAM_SUS" | sed 's/^/      /'; ALERT=1; ssh_found=1
    suggest_only "检查 /etc/pam.d/sshd 中可疑的 PAM 模块" "手动编辑 /etc/pam.d/sshd 删除可疑行"
  fi
fi

if [ "$ssh_found" -eq 0 ]; then echo "  SSH 安全: 未发现异常"; fi

# ---- 9) 自启动持久化(cron / 可疑 service)----
echo "[9] 持久化(cron)"
for u in $(cut -f1 -d: /etc/passwd); do
  c=$(crontab -l -u "$u" 2>/dev/null | grep -vE '^\s*#|^\s*$')
  [ -n "$c" ] && { echo "  [信息] 用户 $u 有 cron(请核对):"; echo "$c" | sed 's/^/      /'; }
done
SUS_CRON=$(grep -rEl 'curl|wget|/tmp/|base64 -d' /etc/cron* /var/spool/cron 2>/dev/null)
if [ -n "$SUS_CRON" ]; then
  echo "  [警] 上述 cron 文件含可疑下载/执行"; ALERT=1
  echo "$SUS_CRON" | while read -r f; do
    suggest_only "检查并清理可疑 cron 文件: $f" "手动编辑 $f 删除可疑行,或 crontab -e -u <用户> 清理"
  done
else
  echo "  未发现可疑 cron"
fi

# ---- 10) ld.so.preload 劫持 ----
echo "[10] ld.so.preload"
if [ -f /etc/ld.so.preload ]; then
  echo "  [警] /etc/ld.so.preload 存在(默认不该有):"; cat /etc/ld.so.preload | sed 's/^/      /'; ALERT=1
  fix_it "备份并删除 /etc/ld.so.preload" "mv /etc/ld.so.preload /etc/ld.so.preload.bak.\$(date +%s)"
else
  echo "  未发现"
fi

# ---- 11) GitHub 公钥安装(-g 参数触发) ----
if [ -n "$GITHUB_USER" ]; then
  echo "[11] GitHub 公钥安装 ($GITHUB_USER)"
  if get_github_key "$GITHUB_USER"; then
    install_github_key && GITHUB_KEY_OK=1
  fi
fi

# ---- 12) 修改 root 密码(-p 参数触发) ----
if [ -n "$ROOT_PASSWD" ]; then
  echo "[12] 修改 root 密码"
  change_root_password "$ROOT_PASSWD" && ROOT_PASSWD_OK=1
fi

# ---- 结论 ----
echo "=========================================="
if [ "$ALERT" -eq 0 ] && [ "$GITHUB_KEY_OK" -eq 0 ] && [ "$ROOT_PASSWD_OK" -eq 0 ]; then
  echo " 结论: 未发现已知植入物 ✅ (但不代表绝对安全,被 root 控制过仍建议重装)"
elif [ "$ALERT" -eq 0 ]; then
  _msg=" 结论: 未发现已知植入物 ✅"
  [ "$GITHUB_KEY_OK" -eq 1 ] && _msg="$_msg, GitHub 公钥已安装"
  [ "$ROOT_PASSWD_OK" -eq 1 ] && _msg="$_msg, root 密码已修改"
  echo "$_msg"
else
  if [ "$FIX_MODE" -eq 1 ]; then
    echo " 结论: 已尝试自动修复,请再次运行脚本(不加 --fix)验证是否清理干净"
  else
    echo " 结论: 发现 [警] 项,请逐条人工核查 ⚠️"
    echo " 提示: 使用 --fix 参数可自动执行上述修复命令"
  fi
fi
echo "=========================================="

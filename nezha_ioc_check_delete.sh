#!/bin/bash
# ============================================================
#  哪吒面板入侵 自查/修复脚本 (nezha_ioc_check_delete.sh)
# ------------------------------------------------------------
#  用途:排查 2026-06 哪吒面板漏洞批量入侵的常见植入物
#  模式:
#    只读检测(默认): 仅检测不修改,可放心运行
#    修复模式(--fix): 检测并自动清理植入物(危险,需确认)
#  用法:
#    bash nezha_ioc_check_delete.sh             # 只读检测
#    bash nezha_ioc_check_delete.sh --fix       # 检测 + 自动修复
#    或批量: ssh 节点 'bash -s' < nezha_ioc_check_delete.sh
#           ssh 节点 'bash -s -- --fix' < nezha_ioc_check_delete.sh
# ------------------------------------------------------------
#  发现 [警] 即需处理;
#  不加 --fix 时显示 💡处理建议 和命令,加 --fix 则自动执行。
# ============================================================

FIX_MODE=0
[ "$1" = "--fix" ] && FIX_MODE=1

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

# ---- 6) 守护/复活服务(SystemLoger / systemlog.service)----
echo "[6] 守护复活服务"
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

# ---- 7) SSH 后门公钥 ----
# 网传后门公钥常带 gary 之类注释;这里同时提示你核对公钥总数。
echo "[7] SSH 后门公钥"
ssh_found=0
if grep -iq "gary" ~/.ssh/authorized_keys 2>/dev/null; then
  echo "  [警] authorized_keys 含可疑公钥(gary)"; ALERT=1; ssh_found=1
  fix_it "备份 authorized_keys 到 authorized_keys.bak" "cp -f ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak.\$(date +%s)"
  fix_it "删除含 gary 的公钥行" "sed -i.bak '/gary/I d' ~/.ssh/authorized_keys"
fi
echo "  (当前 authorized_keys 公钥数: $(grep -c '^ssh-' ~/.ssh/authorized_keys 2>/dev/null))"
if [ "$ssh_found" -eq 0 ]; then echo "  未发现可疑 SSH 公钥"; fi

# ---- 8) 自启动持久化(cron / 可疑 service)----
echo "[8] 持久化(cron)"
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

# ---- 9) ld.so.preload 劫持 ----
echo "[9] ld.so.preload"
if [ -f /etc/ld.so.preload ]; then
  echo "  [警] /etc/ld.so.preload 存在(默认不该有):"; cat /etc/ld.so.preload | sed 's/^/      /'; ALERT=1
  fix_it "备份并删除 /etc/ld.so.preload" "mv /etc/ld.so.preload /etc/ld.so.preload.bak.\$(date +%s)"
else
  echo "  未发现"
fi

# ---- 结论 ----
echo "=========================================="
if [ "$ALERT" -eq 0 ]; then
  echo " 结论: 未发现已知植入物 ✅ (但不代表绝对安全,被 root 控制过仍建议重装)"
else
  if [ "$FIX_MODE" -eq 1 ]; then
    echo " 结论: 已尝试自动修复,请再次运行脚本(不加 --fix)验证是否清理干净"
  else
    echo " 结论: 发现 [警] 项,请逐条人工核查 ⚠️"
    echo " 提示: 使用 --fix 参数可自动执行上述修复命令"
  fi
fi
echo "=========================================="

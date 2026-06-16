#!/bin/bash
# ============================================================
#  哪吒面板入侵 自查脚本 (nezha_ioc_check.sh)
# ------------------------------------------------------------
#  用途:排查 2026-06 哪吒面板漏洞批量入侵的常见植入物
#  特点:只读检测,不删除/不修改任何东西,可放心运行
#  用法:直接在被检查的服务器上执行  bash nezha_ioc_check.sh
#        或从本地批量: ssh 节点 'bash -s' < nezha_ioc_check.sh
# ------------------------------------------------------------
#  发现 [警] 即需人工核查;全部显示"未发现"则该项干净。
#  注意:本脚本只负责"发现",清理请人工判断后手动进行。
# ============================================================

ALERT=0
echo "=========================================="
echo " 哪吒入侵自查: $(hostname)  $(date '+%F %T')"
echo "=========================================="

# ---- 1) memfd 内存马 ----
# 攻击者用 memfd_create 把恶意程序只放在内存、磁盘无文件,
# 常伪装成 [kworker/x:x]。靠 /proc/PID/exe 指向 memfd 识别。
echo "[1] memfd 内存马"
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
  if ls -l /proc/$pid/exe 2>/dev/null | grep -qi "memfd"; then
    echo "  [警] PID $pid 指向 memfd  cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
    ALERT=1
  fi
done

# ---- 2) kworker 伪装(进程名像内核线程,却有用户态 exe)----
# 真内核线程父进程是 kthreadd(PID 2)且无 exe;伪装的则有真实 exe。
# 注:请把下面 EXCLUDE 里换成你自己合法的、恰好以 k 开头的程序名(如 komari)。
EXCLUDE_COMM="kdump|komari|kubelet"
echo "[2] kworker 伪装进程"
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
        fi
      fi
      ;;
  esac
done

# ---- 3) 执行已删除文件的进程((deleted))----
# 程序跑起来后删掉自身文件,只留内存副本。排除正常软件路径与升级残留。
# 注:把 /app 换成你自己正常程序所在目录,避免误报。
echo "[3] 已删除文件执行"
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
  exe=$(readlink /proc/$pid/exe 2>/dev/null)
  case "$exe" in
    *"(deleted)"*)
      case "$exe" in
        */usr/*|*/bin/*|*/sbin/*|*/app/*|*/snap/*) ;;
        *) echo "  [警] PID $pid exe=$exe"; ALERT=1 ;;
      esac
      ;;
  esac
done

# ---- 4) 恶意哪吒 Agent(随机后缀 config / service,连第三方主控)----
echo "[4] 恶意哪吒 Agent 残留"
ps aux | grep -i 'nezha-agent' | grep -v grep | grep -E 'config-[a-z0-9]+\.yml' \
  && { echo "  [警] 发现随机后缀 config 的 agent 进程"; ALERT=1; }
ls /etc/systemd/system/ 2>/dev/null | grep -E 'nezha-agent-[a-z0-9]+\.service' \
  && { echo "  [警] 发现随机后缀 nezha service"; ALERT=1; }
ls /opt/nezha/agent/config-*.yml 2>/dev/null \
  && { echo "  [警] 发现随机 config 文件"; ALERT=1; }

# ---- 5) 挖矿程序(XMRig / c3pool)----
echo "[5] 挖矿程序"
[ -e /root/c3pool ] && { echo "  [警] /root/c3pool 目录存在"; ALERT=1; }
pgrep -x xmrig >/dev/null 2>&1 && { echo "  [警] xmrig 进程在运行"; ALERT=1; }
[ -e /etc/systemd/system/c3pool_miner.service ] && { echo "  [警] c3pool_miner.service 存在"; ALERT=1; }

# ---- 6) 守护/复活服务(SystemLoger / systemlog.service)----
echo "[6] 守护复活服务"
pgrep -x SystemLoger >/dev/null 2>&1 && { echo "  [警] SystemLoger 进程在运行"; ALERT=1; }
[ -e /opt/systemlog ] && { echo "  [警] /opt/systemlog 目录存在"; ALERT=1; }
[ -e /etc/systemd/system/systemlog.service ] && { echo "  [警] systemlog.service 存在"; ALERT=1; }

# ---- 7) SSH 后门公钥 ----
# 网传后门公钥常带 gary 之类注释;这里同时提示你核对公钥总数。
echo "[7] SSH 后门公钥"
grep -i "gary" ~/.ssh/authorized_keys 2>/dev/null \
  && { echo "  [警] authorized_keys 含可疑公钥(gary)"; ALERT=1; }
echo "  (当前 authorized_keys 公钥数: $(grep -c '^ssh-' ~/.ssh/authorized_keys 2>/dev/null))"

# ---- 8) 自启动持久化(cron / 可疑 service)----
echo "[8] 持久化(cron)"
for u in $(cut -f1 -d: /etc/passwd); do
  c=$(crontab -l -u "$u" 2>/dev/null | grep -vE '^\s*#|^\s*$')
  [ -n "$c" ] && { echo "  [信息] 用户 $u 有 cron(请核对):"; echo "$c" | sed 's/^/      /'; }
done
grep -rEl 'curl|wget|/tmp/|base64 -d' /etc/cron* /var/spool/cron 2>/dev/null \
  && { echo "  [警] 上述 cron 文件含可疑下载/执行"; ALERT=1; }

# ---- 9) ld.so.preload 劫持 ----
echo "[9] ld.so.preload"
[ -f /etc/ld.so.preload ] && { echo "  [警] /etc/ld.so.preload 存在(默认不该有):"; cat /etc/ld.so.preload | sed 's/^/      /'; ALERT=1; }

# ---- 结论 ----
echo "=========================================="
if [ "$ALERT" -eq 0 ]; then
  echo " 结论: 未发现已知植入物 ✅ (但不代表绝对安全,被 root 控制过仍建议重装)"
else
  echo " 结论: 发现 [警] 项,请逐条人工核查 ⚠️"
fi
echo "=========================================="

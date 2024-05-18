# onekey-install-shell
Linux常用shell脚本
## 更改服务器的出栈优先级为IPv4/IPv6脚本
1. 设置为IPv4优先
```
bash <(wget --no-check-certificate -qO- 'https://raw.github.com/tanpengsccd/onekey-install-shell/master/set-ip-priority.sh') -4
```
2. 设置为IPv6优先
```
bash <(wget --no-check-certificate -qO- 'https://raw.github.com/tanpengsccd/onekey-install-shell/master/set-ip-priority.sh') -6
```
3. 恢复默认
```
bash <(wget --no-check-certificate -qO- 'https://raw.github.com/tanpengsccd/onekey-install-shell/master/set-ip-priority.sh') -reset
```

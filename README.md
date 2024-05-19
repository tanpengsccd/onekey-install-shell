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
## ssh key 登陆 工具 
来自 https://github.com/P3TERX/SSH_Key_Installer, 具体使用说明见其网站. 
```
bash <(curl -fsSL https://raw.github.com/tanpengsccd/onekey-install-shell/master/ssh_pub_key_installer.sh) -g tanpengsccd -d -p10022  # -g github的帐户名 -d 删除密码登录 -p 设置ssh开放端口
```

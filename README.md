# onekey-install-shell
Linux 常自用shell脚本.
> 由于大陆地方访问GitHub有间接性阻断,所以使用镜像加速地址 https://iilog.com , 如不放心代码可自行替换替换URL地址 "https://iilog.com" ->  "https://raw.github.com/tanpengsccd/onekey-install-shell/master" .
## 配置自动挂载硬盘（改自宝塔挂载脚本）
 ```shell
 bash <(curl -fsSL iilog.com/auto-mount-disk.sh)  # 查看 已经挂载 和 可挂载的硬盘
 bash <(curl -fsSL iilog.com/auto-mount-disk.sh)  -a # 自动挂载
 ```
## 更改服务器的出栈优先级为IPv4/IPv6

  1. 设置为IPv4优先
  ```
  bash <(wget --no-check-certificate -qO- 'https://iilog.com/set-ip-priority.sh') -4
  ```
  2. 设置为IPv6优先
  ```
  bash <(wget --no-check-certificate -qO- 'https://iilog.com/set-ip-priority.sh') -6
  ```
  3. 恢复默认
  ```
  bash <(wget --no-check-certificate -qO- 'https://iilog.com/set-ip-priority.sh') -reset
  ```
## ssh key 登陆配置 
  改自 https://github.com/P3TERX/SSH_Key_Installer.   
  -g [github的帐户名]   : 设置github的帐户名下的ssh key, 需要该github的帐户已配置ssh key.  
  -d [y/n] : 关闭/开启远程root密码登录   
  -p [ssh开放的端口]  
  ```
  bash <(curl -fsSL iilog.com/ssh.sh) -g tanpengsccd -p10022 -d y  # -g github的帐户名 -d y/n 关闭/开启远程root密码登录 -p 设置ssh开放端口
  ```
## ddns 脚本  
  改自 https://github.com/yulewang/cloudflare-api-v4-ddns
  ```
  curl -s iilog.com/cf-v4-ddns.sh | bash -s  f87a1025822be51556071ef68f1e8af10fb32 tanpengcd@gmail.com  baidu.com mynode.baidu.com # -s后跟四个参数  [CF_Global_API_KEY] [CF_Email] [二级域名] [具体域名]
  ```
## 设置 dns 

  ```
  bash <(curl -fsSL iilog.com/set-dns.sh) 1.1.1.1 8.8.8.8 2606:4700:4700::1111 2001:4860:4860::8888 -p # -p 为永久设置;否则为临时设置,重启后失效
  ```
## 设置CloudFlare的安全等级 
如设置站点 5秒盾 
  - 用法： bash <(wget --no-check-certificate -qO- 'https://iilog.com/cf-security-level.sh') admin@badiu.com apikey30be7032ba0b0d870e74e3cdcd934ef zoneidcfe29838c671fbd522bc81856e under_attack
  - 更多信息参考 https://limbopro.com/archives/ChangeSecurity-Level-setting.html
  - 官方API     https://developers.cloudflare.com/api/operations/zone-settings-change-security-level-setting
  ```
  bash <(wget --no-check-certificate -qO- 'https://iilog.com/cf-security-level.sh') admin@badiu.com yourCfApiKey yourZoneId under_attack
  ```
## 1panel V2 升级脚本
 ```
 bash <(wget --no-check-certificate -qO- 'https://iilog.com/1panelV2Upgrade.sh')  upgrade-master
 ```


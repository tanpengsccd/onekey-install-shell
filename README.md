# onekey-install-shell
Linux 常自用shell脚本.

下面的地址可自己替换 "https://iilog.com" ->  "https://raw.github.com/tanpengsccd/onekey-install-shell/master"

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
  来自 https://github.com/P3TERX/SSH_Key_Installer, 具体使用说明见其网站. 
  ```
  bash <(curl -fsSL https://iilog.com/ssh_pub_key_installer.sh) -g tanpengsccd -d -p10022  # -g github的帐户名 -d 删除密码登录 -p 设置ssh开放端口
  ```
## ddns 脚本  
  改自 https://github.com/yulewang/cloudflare-api-v4-ddns
  ```
  curl -s https://iilog.com/cf-v4-ddns.sh | bash -s  f87a1025822be51556071ef68f1e8af10fb32 tanpengcd@gmail.com  baidu.com mynode.baidu.com # -s后跟四个参数  [CF_Global_API_KEY] [CF_Email] [二级域名] [具体域名]
  ```

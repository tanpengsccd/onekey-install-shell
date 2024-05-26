#!/usr/bin/env bash
# 用法： bash <(wget --no-check-certificate -qO- 'https://iilog.com/cf-security-level.sh') admin@badiu.com apikey30be7032ba0b0d870e74e3cdcd934ef zoneidcfe29838c671fbd522bc81856e under_attack
# 更多信息参考 https://limbopro.com/archives/ChangeSecurity-Level-setting.html
# 官方API     https://developers.cloudflare.com/api/operations/zone-settings-change-security-level-setting
# 读取环境变量或从命令行参数获取
CFEMAIL=${CFEMAIL:-$1}
CFAPIKEY=${CFAPIKEY:-$2}
ZONEID=${ZONEID:-$3}
LEVEL=${LEVEL:-$4}

# 检查是否所有必要的变量都已设置
if [ -z "$CFEMAIL" ] || [ -z "$CFAPIKEY" ] || [ -z "$ZONEID" ] || [ -z "$LEVEL" ]; then
    echo "错误! 必须提供 参数: CFEMAIL CFAPIKEY ZONEID LEVEL"
    echo "CFEMAIL: Cloudflare注册邮箱"
    echo "CFAPIKEY: https://dash.cloudflare.com/profile/api-tokens中的 Global API Key"
    echo "ZONEID: https://dash.cloudflare.com - 选择您的域名 - 概览 - API(在右侧栏) - 区域 ID"
    echo "LEVEL: 安全等级 off/essentially_off/low/medium/high/under_attack "
    echo "API Doc: https://developers.cloudflare.com/api/operations/zone-settings-change-security-level-setting"
    exit 1
else
    echo "CFEMAIL: $CFEMAIL"
    echo "CFAPIKEY: $CFAPIKEY"
    echo "ZONEID: $ZONEID"
    echo "LEVEL: $LEVEL"
fi

# 调用 Cloudflare API 更新安全级别
response=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONEID}/settings/security_level" \
    -H "X-Auth-Email: ${CFEMAIL}" \
    -H "X-Auth-Key: ${CFAPIKEY}" \
    -H "Content-Type: application/json" \
    --data '{"value": "'$LEVEL'"}')

# 检查 API 调用是否成功
if echo "$response" | grep -q '"success":true'; then
    echo "安全级别设置成功更新为${LEVEL}。"
else
    echo "错误：更新安全级别失败。"
    echo "响应内容：$response"
    exit 1
fi

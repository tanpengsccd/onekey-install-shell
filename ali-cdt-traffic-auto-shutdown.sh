#!/bin/bash
# 先设置 打开 https://cdt.console.aliyun.com/overview  的调试
# 找到请求 https://cdt.console.aliyun.com/data/api.json?_fetcher_=cdt__ListCdtInternetTraffic&product=cdt&action=ListCdtInternetTraffic
# 获取 其 cookie 和 请求体
# export ALICookie='cookie: _samesite_flag_=true; cookie2=XXXXXX;.....'
# export ALICDTBody='sec_token=xxxxxxxxxxx'
# export ALIECSStartBody='collina=140.....'
# export ALIECSStopBody='collina=140....'

# 使用提供的 curl 命令获取数据
json_response=$(curl 'https://cdt.console.aliyun.com/data/api.json?_fetcher_=cdt__ListCdtInternetTraffic&product=cdt&action=ListCdtInternetTraffic' \
    -H "$ALICookie" \
    --data-raw "$ALICDTBody" | jq '.')

# 解析 JSON 响应并检查 Traffic 值
traffic_value=$(echo $json_response | jq '.data.TrafficDetails[0].Traffic')
traffic_in_gb=$(echo "scale=2; $traffic_value/1024/1024/1024" | bc)
# 根据 Traffic 值返回相应的信号
if [ "$traffic_value" -gt 193273528320 ]; then
    echo "当月CDT流量:$traffic_in_gb ,已超过180G"
    curl 'https://ecs.console.aliyun.com/instance/operator/stopInstance.json' \
        -H "$ALICookie" \
        --data-raw "$ALIECSStopBody"
    echo "关机成功"
# 如果 == 0 说明流量重置了, 客服说是每月1日重置的, 所以需要开机
elif [ "$traffic_value" -eq 0 ]; then

    echo "当月CDT流量$traffic_in_gb ,已经恢复流量"
    curl 'https://ecs.console.aliyun.com/instance/operator/startInstance.json' \
        -H "$ALICookie" \
        --data-raw "$ALIECSStartBody"
    echo "开机成功"

else
    echo "当月CDT流量$traffic_in_gb ,还未超过180G"
fi

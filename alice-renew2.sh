#!/bin/bash

# --- 1. 配置信息 (从环境变量获取) ---

# 鉴权变量, 从 https://console.alice.ws/ephemera/evo-cloud 获取
ALICE_CLIENT_ID="${ALICE_CLIENT_ID}"
ALICE_API_SECRET="${ALICE_API_SECRET}"
AUTH_TOKEN="${ALICE_CLIENT_ID}:${ALICE_API_SECRET}"

# 实例部署配置
PRODUCT_ID=${PRODUCT_ID:-38}                 # 默认：SLC.Evo.Pro (ID 38)
OS_ID=${OS_ID:-1}                            # 默认：Debian 12 (ID 1)
DEPLOY_TIME_HOURS=${DEPLOY_TIME_HOURS:-24}   # 默认：24 小时
NODEJS_COMMAND="${NODEJS_COMMAND:-""}"       # nodejs-argo 远程脚本
ALICE_SSH_KEY_ID=""                          # 由脚本动态赋值

# Alice API 端点, 官方文档: https://api.aliceinit.io
API_BASE_URL="https://app.alice.ws/cli/v1"
API_DESTROY_URL="${API_BASE_URL}/evo/instances"          # DELETE 删除实例
API_DEPLOY_URL="${API_BASE_URL}/evo/instances/deploy"    # POST 部署实例
API_LIST_URL="${API_BASE_URL}/evo/instances"             # GET 实例列表
API_SSH_KEY_URL="${API_BASE_URL}/account/ssh-keys"       # GET SSH 公钥列表

# Telegram 通知配置 (需要从 GitHub action secrets 传入)
TG_BOT_TOKEN="${TG_BOT_TOKEN}"
TG_CHAT_ID="${TG_CHAT_ID}"
TG_API_BASE="https://api.telegram.org"

# --- 2. 辅助函数 ---

# 检查必需的令牌和依赖项
check_token_and_depend() {
    if [ -z "$ALICE_CLIENT_ID" ] || [ -z "$ALICE_API_SECRET" ]; then
        echo "❌ 错误：ALICE_CLIENT_ID 或 ALICE_API_SECRET 变量未设置" >&2
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "❌ 错误：未找到 'jq' 命令" >&2
        exit 1
    fi
}

# Telegram 通知函数
send_tg_notification() {
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "⚠️ 跳过 Telegram 通知 (未配置 TG_BOT_TOKEN 或 TG_CHAT_ID)" >&2
        return
    fi
    
    local message="$1"
    local URL="${TG_API_BASE}/bot${TG_BOT_TOKEN}/sendMessage"
    
    echo "▶️ 正在发送 Telegram 通知..." >&2
    if curl -s -f -X POST "$URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null; then
        echo "✅ Telegram 通知发送成功" >&2
        return 0
    else
        echo "❌ Telegram 通知发送失败" >&2
        return 1
    fi
}

# --- 3. 核心函数 ---

# 获取列表中的第一个 SSH Key ID
get_ssh_key_id() {
    echo "▶️ 正在尝试获取第一个可用的 SSH Key ID..." >&2
    SSH_KEY_RESPONSE=$(curl -L -s -X GET "$API_SSH_KEY_URL" -H "Authorization: Bearer $AUTH_TOKEN")
    local key_id=$(echo "$SSH_KEY_RESPONSE" | jq -r '.data[0].id // empty')

    if [ -n "$key_id" ]; then
        echo "✅ 成功获取 SSH Key ID: $key_id" >&2
        echo "$key_id"
    else
        echo "❌ 错误：获取 SSH Key ID 失败，API 响应中未找到 'id' 字段" >&2
        return 1
    fi
}

# 获取实例列表
get_instance_ids() {
    echo "▶️ 正在尝试获取实例列表..." >&2
    LIST_RESPONSE=$(curl -L -s -X GET "$API_LIST_URL" -H "Authorization: Bearer $AUTH_TOKEN")
    INSTANCE_IDS=$(echo "$LIST_RESPONSE" | jq -r '.data[].id // empty' | tr '\n' ' ')
    if [ -n "$INSTANCE_IDS" ]; then
        echo "✅ 成功获取到以下实例 ID：$INSTANCE_IDS" >&2
        echo "$INSTANCE_IDS"
        return 0
    else
        echo "⚠️ 未发现任何实例" >&2
        return 2
    fi
}

# 销毁实例
destroy_instance() {
    local instance_id="$1"
    RESPONSE=$(curl -L -s -X DELETE "$API_DESTROY_URL/${instance_id}" -H "Authorization: Bearer $AUTH_TOKEN")
    API_STATUS=$(echo "$RESPONSE" | jq -r '.code // empty')
    MESSAGE=$(echo "$RESPONSE" | jq -r '.message // "无消息"')

    if [ "$API_STATUS" == "200" ]; then
        echo "实例 $instance_id: ✅ 销毁成功" >&2
        echo "状态码: $API_STATUS" >&2
        echo "消息: $MESSAGE" >&2
        return 0
    else
        echo "实例 $instance_id: ❌ 销毁失败" >&2
        echo "状态码: $API_STATUS" >&2
        echo "消息: $MESSAGE" >&2
        return 1
    fi
}

# 创建实例（默认时长24小时）
deploy_instance() {
    # 获取 SSH Key ID 以绑定公钥
    ALICE_SSH_KEY_ID=$(get_ssh_key_id)
    GET_KEY_STATUS=$?
    if [ "$GET_KEY_STATUS" -ne 0 ]; then
        echo "⚠️ 获取 SSH Key ID失败, 无法绑定公钥, 需以密码连接 SSH" >&2
        echo "⚠️ 你也可以手动连接新实例 SSH 并执行 nodejs-argo 脚本" >&2
    fi

    # 使用 jq 构造 JSON 负载
    PAYLOAD=$(jq -n \
        --arg product_id "$PRODUCT_ID" \
        --arg os_id "$OS_ID" \
        --arg time "$DEPLOY_TIME_HOURS" \
        --arg ssh_key_id "$ALICE_SSH_KEY_ID" \
        '
        {
            "product_id": ($product_id | tonumber),
            "os_id": ($os_id | tonumber),
            "time": ($time | tonumber),
            "ssh_key_id": (if $ssh_key_id | length > 0 then ($ssh_key_id | tonumber) else null end)
        }
        '
    )
    
    RESPONSE=$(curl -L -s -X POST "$API_DEPLOY_URL" -H "Authorization: Bearer $AUTH_TOKEN" -H "Content-Type: application/json" -d "$PAYLOAD")
    API_STATUS=$(echo "$RESPONSE" | jq -r '.code // empty')
    MESSAGE=$(echo "$RESPONSE" | jq -r '.message // "无消息"')

    if [ "$API_STATUS" == "200" ]; then
        # 从 JSON 响应中提取关键信息
        NEW_ID=$(echo "$RESPONSE" | jq -r '.data.id // empty')
        NEW_PLAN=$(echo "$RESPONSE" | jq -r '.data.plan // empty')
        NEW_CPU=$(echo "$RESPONSE" | jq -r '.data.cpu // empty')
        NEW_MEM=$(echo "$RESPONSE" | jq -r '.data.memory // empty')
        NEW_DISK=$(echo "$RESPONSE" | jq -r '.data.disk // empty')
        NEW_OS=$(echo "$RESPONSE" | jq -r '.data.os // empty')
        NEW_IP=$(echo "$RESPONSE" | jq -r '.data.ipv4 // empty')
        NEW_IPV6=$(echo "$RESPONSE" | jq -r '.data.ipv6 // empty')
        NEW_HOST=$(echo "$RESPONSE" | jq -r '.data.hostname // empty')
        NEW_USER=$(echo "$RESPONSE" | jq -r '.data.user // empty')
        NEW_PASS=$(echo "$RESPONSE" | jq -r '.data.password // empty')
        NEW_STATUS=$(echo "$RESPONSE" | jq -r '.data.status // empty')
        NEW_CREAT=$(echo "$RESPONSE" | jq -r '.data.creation_at // empty')
        NEW_EXPIR=$(echo "$RESPONSE" | jq -r '.data.expiration_at // empty')
        NEW_REGION=$(echo "$RESPONSE" | jq -r '.data.region // empty')
        
        # 构造新实例详细信息 (用于日志和 TG)
        DETAILS_TEXT="实例 ID: $NEW_ID
部署方案: $NEW_PLAN
硬件配置: CPU: ${NEW_CPU}G, 内存: ${NEW_MEM}M, 磁盘: ${NEW_DISK}G
操作系统: $NEW_OS
区域: $NEW_REGION
状态: $NEW_STATUS
创建时间: $NEW_CREAT
过期时间: $NEW_EXPIR
剩余时间: $DEPLOY_TIME_HOURS 小时
------ SSH登录信息 ------
IPv4 地址: <code>${NEW_IP}</code>
IPv6 地址: <code>${NEW_IPV6}</code>
主机名: <code>${NEW_HOST}</code>
用户名: <code>${NEW_USER}</code>
密码: <code>${NEW_PASS}</code>"

        # 构造 Telegram 成功消息
        TG_SUCCESS_MSG=$(cat <<EOF
<b>🎉 Alice Evo 部署成功！</b>
========================
${DETAILS_TEXT}
========================
EOF
        )
        # 输出到终端
        DETAILS_TEXT_LOG=$(echo "$DETAILS_TEXT" | sed -e 's/<code>//g' -e 's/<\/code>//g')
        echo "实例状态: ✅ 创建成功" >&2
        echo "----- 新实例详情 -----" >&2
        echo "$DETAILS_TEXT_LOG" >&2
        echo "--------------------" >&2
        send_tg_notification "$TG_SUCCESS_MSG"
        
        # 输出顺序: ID IP USER PASS HOST
        echo "$NEW_ID $NEW_IP $NEW_USER $NEW_PASS $NEW_HOST"
        return 0

    else
        # 构造 Telegram 部署失败消息
        TG_FAIL_MSG=$(cat <<EOF
<b>❌ Alice Evo 部署失败！</b>
========================
状态码: ${API_STATUS}
错误消息: ${MESSAGE}
========================
请检查账户权限或 API 配置。
EOF
        )
        echo "实例状态: ❌ 创建失败" >&2
        echo "状态码: $API_STATUS" >&2
        echo "错误信息: $MESSAGE" >&2
        echo "$RESPONSE" | jq . >&2
        send_tg_notification "$TG_FAIL_MSG"
        exit 1
    fi
}

# --- 4. 主执行逻辑 ---
main() {
    check_token_and_depend  # 检查 Alice API 令牌和依赖项

    echo -e "\n======================================"
    echo "🚀 批量销毁现有实例"
    echo "======================================"

    ALL_IDS=$(get_instance_ids)
    if [ $? -eq 0 ]; then
        for id in $ALL_IDS; do destroy_instance "$id"; done
    else
        echo "⚠️ 未发现任何实例，跳过销毁阶段"
    fi

    # 部署新实例
    echo -e "\n======================================"
    echo "🚀 部署新实例"
    echo "======================================"
    echo "▶️ 正在部署新实例，实例方案..." >&2
    echo "💡 PRODUCT_ID: ${PRODUCT_ID}, OS_ID: ${OS_ID}, Time: ${DEPLOY_TIME_HOURS}h" >&2

    NEW_INSTANCE_INFO=$(deploy_instance)
    echo "$NEW_INSTANCE_INFO"
}

# 执行主函数
main

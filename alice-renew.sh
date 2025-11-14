#!/bin/bash

# --- 1. 配置信息 (从环境变量获取) ---

# 鉴权变量, 从 https://console.alice.ws/ephemera/evo-cloud 获取
ALICE_CLIENT_ID="${ALICE_CLIENT_ID}"
ALICE_API_SECRET="${ALICE_API_SECRET}"
AUTH_TOKEN="${ALICE_CLIENT_ID}:${ALICE_API_SECRET}"
ALICE_ACCOUNT_USER="${ALICE_ACCOUNT_USER}"                    # alice 注册账号的用户名
ALICE_SSH_HOST="${ALICE_ACCOUNT_USER}.evo.host.aliceinit.dev" # 默认 SSH 主机名

# 实例部署配置
PRODUCT_ID=${PRODUCT_ID:-38}                                  # 默认：SLC.Evo.Pro (ID 38)
OS_ID=${OS_ID:-1}                                             # 默认：Debian 12 (ID 1)
DEPLOY_TIME_HOURS=${DEPLOY_TIME_HOURS:-24}                    # 默认：24 小时
ALICE_SSH_KEY_NAME="${ALICE_SSH_KEY_NAME:-alice-yutian81}"    # 目标 SSH 公钥的名称
ALICE_SSH_KEY_ID=""                                           # 将通过脚本获取

# Alice API 端点
API_BASE_URL="https://app.alice.ws/cli/v1"
API_DESTROY_URL="${API_BASE_URL}/Evo/Destroy"
API_DEPLOY_URL="${API_BASE_URL}/Evo/Deploy"
API_LIST_URL="${API_BASE_URL}/Evo/Instance"
API_SSH_KEY_URL="${API_BASE_URL}/User/SSHKey"

# Telegram 通知配置 (需要从 GitHub action secrets 传入)
TG_BOT_TOKEN="${TG_BOT_TOKEN}"
TG_CHAT_ID="${TG_CHAT_ID}"
TG_API_BASE="${TG_API_BASE:-https://api.telegram.org}" # 默认使用官方 API

# 脚本中的 UUID/ARGO 等配置也需要从 GitHub action secrets 传入
NODEJS_COMMAND="
curl -o vpsnpm.sh -Ls \"https://raw.githubusercontent.com/yutian81/alice-evo/main/vpsnpm.sh\"
chmod +x vpsnpm.sh
export UUID=\"${UUID:-822fb34f-af37-445f-8c05-ae35d5423b34}\"
export NEZHA_SERVER=\"${NEZHA_SERVER:-}\"
export NEZHA_PORT=\"${NEZHA_PORT:-}\"
export NEZHA_KEY=\"${NEZHA_KEY:-}\"
export ARGO_DOMAIN=\"${ARGO_DOMAIN:-}\"
export ARGO_AUTH=\"${ARGO_AUTH:-}\"
export CFIP=\"${CFIP:-}\"
export NAME=\"${NAME:-}\"
./vpsnpm.sh
"

# --- 2. 辅助函数 ---

check_config() {
    if [ -z "$ALICE_CLIENT_ID" ] || [ -z "$ALICE_API_SECRET" ]; then
        echo "❌ 错误：ALICE_CLIENT_ID 或 ALICE_API_SECRET 变量未设置。" >&2
        exit 1
    fi
    if [ -z "$ALICE_SSH_KEY_NAME" ]; then
        echo "❌ 错误：ALICE_SSH_KEY_NAME 未设置，无法自动获取 SSH Key ID。" >&2
        exit 1
    fi
}

check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "❌ 错误：未找到 'jq' 命令。脚本无法继续执行。" >&2
        exit 1
    fi
}

# Telegram 通知函数
send_tg_notification() {
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "⚠️ 跳过 Telegram 通知 (缺少配置)。" >&2
        return
    fi
    
    local message="$1"
    local URL="${TG_API_BASE}/bot${TG_BOT_TOKEN}/sendMessage"
    
    echo "▶️ 正在发送 Telegram 通知..." >&2

    # 使用 curl 发送 POST 请求
    curl -s -X POST "$URL" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Telegram 通知发送成功。" >&2
    else
        echo "❌ Telegram 通知发送失败。" >&2
    fi
}

# HTML 转义
escape_html() {
    local text="$1"
    text=$(echo "$text" | sed -e 's/&/&amp;/g' \
                             -e 's/</&lt;/g' \
                             -e 's/>/&gt;/g')
    echo "$text"
}

# 获取指定名称的 SSH Key ID
get_ssh_key_id() {
    local key_name="$1"
    echo "▶️ 正在尝试获取 SSH Key ID (名称: **$key_name**)..." >&2
    
    SSH_KEY_RESPONSE=$(curl -L -s -X GET "$API_SSH_KEY_URL" -H "Authorization: Bearer $AUTH_TOKEN")
    API_STATUS=$(echo "$SSH_KEY_RESPONSE" | jq -r '.status // empty')

    if [ "$API_STATUS" != "200" ]; then
        echo "❌ 获取 SSH Key 列表失败 (API 错误 - Status: $API_STATUS)" >&2
        return 1
    fi

    local key_id=$(echo "$SSH_KEY_RESPONSE" | \
        jq -r --arg name "$key_name" '.data[] | select(.name == $name) | .id // empty')

    if [ -z "$key_id" ]; then
        echo "❌ 错误：未找到名称为 '**$key_name**' 的 SSH Key ID。" >&2
        echo "请注意：如果您希望使用的公钥尚未在 Alice 后台添加，请手动添加。" >&2
        return 2
    fi
    
    echo "✅ 成功获取 SSH Key ID: **$key_id**" >&2
    echo "$key_id"
    return 0
}

# 获取实例列表
get_instance_ids() {
    echo "▶️ 正在尝试从 Alice API 获取实例列表..." >&2
    LIST_RESPONSE=$(curl -L -s -X GET "$API_LIST_URL" -H "Authorization: Bearer $AUTH_TOKEN")
    API_STATUS=$(echo "$LIST_RESPONSE" | jq -r '.status // empty')
    
    if [ "$API_STATUS" != "200" ]; then
        echo "❌ 获取实例列表失败 (API 错误 - Status: $API_STATUS)" >&2
        return 1
    fi
    INSTANCE_IDS=$(echo "$LIST_RESPONSE" | jq -r '.data[].id // empty' | tr '\n' ' ')
    
    if [ -z "$INSTANCE_IDS" ]; then
        echo "⚠️ 实例列表为空或未找到有效 ID。" >&2
        return 2
    fi
    echo "✅ 成功获取到以下实例 ID：" $INSTANCE_IDS >&2
    echo "$INSTANCE_IDS"
    return 0
}

# 销毁实例
destroy_instance() {
    local instance_id="$1"
    echo -e "\n🔥 正在销毁实例 ID: ${instance_id}..." >&2
    
    RESPONSE=$(curl -L -s -X POST "$API_DESTROY_URL" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -F "id=$instance_id")
    CURL_STATUS=$?

    if [ "$CURL_STATUS" -ne 0 ]; then
        echo "❌ 实例 ${instance_id} 销毁失败 (cURL 连接错误: $CURL_STATUS)" >&2
        return 1
    fi

    API_STATUS=$(echo "$RESPONSE" | jq -r '.status // empty')
    MESSAGE=$(echo "$RESPONSE" | jq -r '.message // "无消息"')

    if [ "$API_STATUS" == "200" ]; then
        echo "状态: ✅ 销毁成功" >&2
        echo "消息: $MESSAGE" >&2
        return 0
    else
        echo "状态: ❌ 销毁失败 (API 错误 - Status: $API_STATUS)" >&2
        echo "错误信息: $MESSAGE" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi
}

# 创建实例（默认时长24小时）
deploy_instance() {
    echo -e "\n🚀 正在部署新实例 (Plan ID: ${PRODUCT_ID}, OS ID: ${OS_ID}, Time: ${DEPLOY_TIME_HOURS}h...)" >&2
    
    CURL_CMD="curl -L -s -X POST \"$API_DEPLOY_URL\" \
        -H \"Authorization: Bearer $AUTH_TOKEN\" \
        -F \"product_id=$PRODUCT_ID\" \
        -F \"os_id=$OS_ID\" \
        -F \"time=$DEPLOY_TIME_HOURS\""

    if [ -n "$ALICE_SSH_KEY_ID" ]; then
        CURL_CMD="$CURL_CMD -F \"sshKey=$ALICE_SSH_KEY_ID\""
    fi

    RESPONSE=$(eval "$CURL_CMD")
    CURL_STATUS=$?

    if [ "$CURL_STATUS" -ne 0 ]; then
        echo "❌ 实例创建失败 (cURL 连接错误: $CURL_STATUS)" >&2
        return 1
    fi

    API_STATUS=$(echo "$RESPONSE" | jq -r '.status // empty')
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
        
        # 计算剩余时间（小时）
        REMAINING="未知"
        if [ -n "$NEW_CREAT" ] && [ -n "$NEW_EXPIR" ]; then
            timestamp1=$(date +%s -d "$NEW_CREAT")
            timestamp2=$(date +%s -d "$NEW_EXPIR")
            time_diff_seconds=$((timestamp2 - timestamp1))

            if [ "$time_diff_seconds" -gt 0 ]; then
                time_diff_minutes=$((time_diff_seconds / 60))
                remaining_hours=$((time_diff_minutes / 60))
                remaining_minutes=$((time_diff_minutes % 60))
                REMAINING="${remaining_hours} 小时 ${remaining_minutes} 分钟"
            else
                REMAINING="已过期"
            fi
        fi

        # 构造新实例详细信息 (用于日志和 TG)
        DETAILS_TEXT="
实例 ID: $NEW_ID
部署方案: $NEW_PLAN
硬件配置: CPU: $NEW_CPU G | 内存: $NEW_MEM M | 磁盘: $NEW_DISK G
操作系统: $NEW_OS
区域: $NEW_REGION
状态: $NEW_STATUS
创建时间: $NEW_CREAT
过期时间: $NEW_EXPIR
剩余时间: $REMAINING
IPv4 地址: <code>${NEW_IP}</code>
IPv6 地址: <code>${NEW_IPV6}</code>
主机名: <code>${NEW_HOST}</code>
用户名: <code>${NEW_USER}</code>
密码: <code>${NEW_PASS:-(使用SSH Key)}</code>
"

        # 构造 Telegram 成功消息
        TG_SUCCESS_MSG=$(cat <<EOF
<b>🎉 Alice Evo 部署成功！</b>
========================
${DETAILS_TEXT}
========================
EOF
        )
        TG_SUCCESS_MSG=$(escape_html "$TG_SUCCESS_MSG")
        send_tg_notification "$TG_SUCCESS_MSG"

        # 打印到 stderr
        echo "状态: ✅ 创建成功" >&2
        echo "----- 新实例详情 -----" >&2
        echo "$DETAILS_TEXT" | sed -e 's/<code>//g' -e 's/<\/code>//g' >&2
        echo "--------------------" >&2
        
        # 返回新实例 ID IP USER PASS 以供后续使用
        echo "$NEW_ID $NEW_IP $NEW_USER $NEW_PASS"
        return 0

    else
        # 构造 Telegram 部署失败消息
        TG_FAIL_MSG=$(cat <<EOF
<b>❌ Alice Evo 部署失败！</b>
========================
错误状态: ${API_STATUS}
错误消息: ${MESSAGE}
========================
请检查账户余额或 API 配置。
EOF
        )
        TG_FAIL_MSG=$(escape_html "$TG_FAIL_MSG")
        send_tg_notification "$TG_FAIL_MSG"

        echo "状态: ❌ 创建失败 (API 错误 - Status: $API_STATUS)" >&2
        echo "错误信息: $MESSAGE" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi
}

# 💡 通过 SSH 登录并执行脚本
ssh_and_run_script() {
    local instance_ip="$1"
    local instance_user="$2"
    local max_retries=5
    local wait_time=15
    local run_time=30
    local config_succeeded=1

    echo -e "\n⚙️ 正在通过 SSH 登录并执行脚本..." >&2
    echo "目标: ${instance_user}@${instance_ip} (端口: 22)" >&2
    echo "🔑 请确保 SSH 私钥已通过 webfactory/ssh-agent Action 注入。" >&2
    
    # 循环尝试连接 SSH
    for ((i=1; i<=max_retries; i++)); do
        echo "尝试 SSH 连接和执行 (第 $i/$max_retries 次, 等待 ${wait_time} 秒)..." >&2
        
        # SSH 选项说明:
        # -o StrictHostKeyChecking=no: 避免首次连接的密钥确认提示
        # -o ConnectTimeout=10: 连接超时时间
        # -T: 禁止伪终端分配，适合远程执行脚本
        
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -T "${instance_user}@${instance_ip}" "bash -s" <<< "$NODEJS_COMMAND" ; then
            echo "✅ 远程脚本启动成功！" >&2
            config_succeeded=0
            break
        else
            echo "❌ SSH 连接或启动失败。等待 ${wait_time} 秒后重试..." >&2
            sleep "$wait_time"
        fi
    done
    
    if [ "$config_succeeded" -ne 0 ]; then
        echo "❌ 致命错误：SSH 连接或脚本启动在 ${max_retries} 次尝试后失败。" >&2
        return 1
    fi
}

# --- 4. 主函数 ---
main() {
    check_config
    check_jq

    # 自动获取 SSH Key ID
    ALICE_SSH_KEY_ID=$(get_ssh_key_id "$ALICE_SSH_KEY_NAME")
    GET_KEY_STATUS=$?
    if [ "$GET_KEY_STATUS" -ne 0 ]; then
        echo "❌ 无法获取 SSH Key ID，流程终止。" >&2
        exit 1
    fi

    # 获取并销毁现有实例
    ALL_INSTANCE_IDS=$(get_instance_ids)
    GET_ID_STATUS=$?
    DESTROY_COUNT=0
    DESTROY_FAIL=0

    echo -e "\n=========================================="
    echo "🔥 阶段一：批量销毁现有实例"
    echo "=========================================="

    if [ "$GET_ID_STATUS" -eq 0 ]; then
        read -ra ID_ARRAY <<< "$ALL_INSTANCE_IDS"
        for id in "${ID_ARRAY[@]}"; do
            if destroy_instance "$id"; then
                DESTROY_COUNT=$((DESTROY_COUNT + 1))
            else
                DESTROY_FAIL=$((DESTROY_FAIL + 1))
            fi
        done
        echo "总结: 成功销毁 ${DESTROY_COUNT} 个，失败 ${DESTROY_FAIL} 个。"
    elif [ "$GET_ID_STATUS" -eq 2 ]; then
        echo "⚠️ 未发现任何实例，跳过销毁阶段。"
    else
        echo "❌ 获取实例列表失败，跳过销毁阶段。"
    fi

    # 部署新实例
    echo -e "\n=========================================="
    echo "🚀 阶段二：部署新实例"
    echo "=========================================="

    # 捕获 ID, IP, USER, PASS
    NEW_INSTANCE_INFO=$(deploy_instance)
    DEPLOY_STATUS=$?

    if [ "$DEPLOY_STATUS" -ne 0 ]; then
        echo -e "\n❌ 流程失败：新实例部署失败，请检查账户余额和配置。"
        exit 1
    fi

    # 解析 deploy_instance 的返回值
    read -r NEW_ID NEW_IP NEW_USER NEW_PASS<<< "$NEW_INSTANCE_INFO"
    
    # 确定最终的 SSH 连接目标：优先使用 API 返回的 IP，否则使用预设 Hostname
    TARGET_IP=""
    if [ -n "$NEW_IP" ]; then
        TARGET_IP="$NEW_IP"
    else
        TARGET_IP="${ALICE_SSH_HOST}" # 如果 IP 为空，则回退到预设的主机名
    fi
    if [ -z "$NEW_USER" ]; then
        NEW_USER="root" # 默认用户名
    fi

    # SSH执行配置脚本
    echo -e "\n=========================================="
    echo "⚙️ 阶段三：通过 SSH 执行远程配置"
    echo "=========================================="

    local remote_file="/opt/nodejs-argo/tmp/sub.txt"
    if ssh_and_run_script "$TARGET_IP" "$NEW_USER"; then
        echo -e "\n🎉 流程完成！新实例 ${NEW_ID} 部署和配置已成功完成！"
        echo -e "\n🎉 由于Github action的限制，日志中输出的节点内容与 secret 相关的信息会被隐藏"
        echo -e "\n🎉 需要手动连接SSH，并执行 cat "${remote_file}" 命令获取完整节点内容"
        echo -e "\n🎉 SSH连接信息：IP: ${TARGET_IP}, 端口: 22, 用户名: ${NEW_USER}, 密码: ${NEW_PASS}"
    else
        echo -e "\n❌ 流程失败：远程配置脚本执行失败。实例 ${NEW_ID} 已创建，请手动使用 IP ${NEW_IP} 检查。"
        exit 1
    fi
}

# 执行主函数
main

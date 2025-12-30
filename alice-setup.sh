#!/bin/bash

# 拆分脚本：负责对重建的VPS执行远程脚本

NEW_ID=$1
NEW_IP=$2
NEW_USER=${3:-"root"}
NEW_PASS=$4
NEW_HOST=${5:-"yutian81.evo.host.aliceinit.dev"}
NODEJS_COMMAND="${NODEJS_COMMAND:-""}"

TARGET_IP="$NEW_IP"
[ "$TARGET_IP" == "null" ] || [ -z "$TARGET_IP" ] && TARGET_IP="$NEW_HOST"

ssh_and_run_script() {
    local addr="$1"
    local user="$2"
    local max_retries=5
    local wait_time=30
    local timeout=15

    echo "等待 VPS 初始化 (${wait_time} 秒)..." >&2
    sleep "$wait_time"

    for ((i=1; i<=max_retries; i++)); do
        echo "arrow 正在尝试 SSH 连接 (第 $i/$max_retries 次)..." >&2
        local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -o LogLevel=ERROR -o BatchMode=no"

        echo "优先以秘钥连接 SSH" >&2
        if ssh $ssh_opts -T "${user}@${addr}" "bash -s" <<< "$NODEJS_COMMAND"; then
            return 0
        fi
        echo "⚠️ 密钥连接失败，尝试回退到密码验证..." >&2

        echo "尝试以密码连接 SSH" >&2
        export SSHPASS="$NEW_PASS"
        if sshpass -e ssh $ssh_opts -T "${user}@${addr}" "bash -s" <<< "$NODEJS_COMMAND"; then
            return 0
        fi

        echo "❌ SSH 连接失败 (连接超时或服务未就绪), ${wait_time} 秒后重试..." >&2
        sleep "$wait_time"
    done
    return 1
}

main() {
    if [ -z "$TARGET_IP" ] || [ "$TARGET_IP" == "null" ]; then
        echo "❌ 错误：未接收到有效的 IP 或 Hostname" >&2
        exit 1
    fi

    echo -e "\n======================================"
    echo "🚀 连接 SSH 执行远程脚本"
    echo -e "\n======================================"
    echo "💡 SSH 目标: $NEW_USER@$TARGET_IP"

    if ssh_and_run_script "$TARGET_IP" "$NEW_USER"; then
        echo -e "\n======================================"
        echo "🎉 实例 ${NEW_ID} 配置已成功"
        echo "✅ 访问地址: ${TARGET_IP}"
        echo "✅ 登录用户: ${NEW_USER}"
        echo "✅ 登录密码: ${NEW_PASS}"
        echo "======================================"
    else
        echo -e "\n❌ 远程脚本执行最终失败。" >&2
        echo "💡 可能原因：VPS 初始化过慢、密码错误或 NODEJS_COMMAND 语法错误" >&2
        exit 1
    fi
}

main
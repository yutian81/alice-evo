#!/usr/bin/env bash

# --- 配置区 ---
SERVICE_NAME="nodejs-argo"
SERVICE_DIR="/opt/${SERVICE_NAME}"
SUB_FILE="${SERVICE_DIR}/.npm/sub.txt"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
OPENRC_CONF_FILE="/etc/conf.d/${SERVICE_NAME}"
TARGET_MODULE="nodejs-argo"
SYSTEM_USER="root"
MAX_WAIT=30
WAIT_INTERVAL=5

# 变量定义和赋值
define_vars() {
    unset NAME
    export UUID=${UUID:-'3001b2b7-e810-45bc-a1af-2c302b530d40'}
    export NEZHA_SERVER=${NEZHA_SERVER:-''}
    export NEZHA_PORT=${NEZHA_PORT:-''}
    export NEZHA_KEY=${NEZHA_KEY:-''}
    export ARGO_DOMAIN=${ARGO_DOMAIN:-''}
    export ARGO_AUTH=${ARGO_AUTH:-''}
    export CFIP=${CFIP:-'cf.090227.xyz'}
    export NAME=${NAME:-'NPM'}
}

# 清理系统锁
clean_sysblock() {
    [ "$EUID" -ne 0 ] && return
    echo "▶️ 正在深度清理系统软件包管理器锁"
    # 仅当 systemctl 存在时执行，避免 Alpine 报错
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop unattended-upgrades 2>/dev/null
        systemctl stop apt-daily.service 2>/dev/null
        systemctl stop apt-daily-upgrade.service 2>/dev/null
    fi
    
    for i in {1..5}; do
        LOCK_PIDS=$(lsof -t /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock 2>/dev/null)
        BASH_PIDS=$(pgrep -f "apt|dpkg")    
        ALL_PIDS=$(echo "$LOCK_PIDS $BASH_PIDS" | tr ' ' '\n' | sort -u)

        if [ -n "$ALL_PIDS" ]; then
            echo "⚠️ 检测到占用进程: $ALL_PIDS，尝试终止 (第 $i 次)..."
            echo "$ALL_PIDS" | xargs -r kill -9 2>/dev/null
            sleep 2
        else
            echo "✅ 未检测到锁定进程"
            break
        fi
    done

    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend

    if command -v dpkg >/dev/null 2>&1; then
        echo "▶️ 正在修复 dpkg 状态..."
        dpkg --configure -a
    fi
    echo "✅ 系统环境已强制解锁并修复完成"
}

# 创建工作文件夹
setup_environment() {
    # 权限检查：允许非 root 用户执行已安装的服务脚本，但首次安装必须是 root
    if [ "$EUID" -ne 0 ] && [ ! -f "$SERVICE_FILE" ] && [ ! -f "$OPENRC_SERVICE_FILE" ]; then
        echo "⚠️ 首次安装服务需要 root 权限, 请使用 sudo 运行此脚本"
        echo "sudo bash $0"
        exit 1
    fi

    mkdir -p "${SERVICE_DIR}"
    cd "${SERVICE_DIR}" || { echo "无法进入目录 ${SERVICE_DIR}，退出。"; exit 1; }
}

# 检查并安装系统依赖与 Node.js 环境
install_deps() {
    echo -e "\n▶️ 正在检查系统依赖与 Nodejs 环境"
    export DEBIAN_FRONTEND=noninteractive # 强制非交互模式
    
    # 如果是 root 且没 sudo，创建一个 alias
    if [ "$EUID" -eq 0 ] && ! command -v sudo >/dev/null 2>&1; then
        alias sudo=''
    fi

    # 基础工具预检
    local BASIC_TOOLS=("curl" "gnupg" "ca-certificates")
    local TO_INSTALL_TOOLS=()
    for tool in "${BASIC_TOOLS[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            TO_INSTALL_TOOLS+=("$tool")
        fi
    done

    # Node.js 环境预检
    local NEED_NODE=false
    if ! command -v node >/dev/null 2>&1; then
        NEED_NODE=true
    fi

    if [ ${#TO_INSTALL_TOOLS[@]} -eq 0 ] && [ "$NEED_NODE" = false ]; then
        echo "✅ 系统基础工具与 Node.js 已就绪 (版本: $(node -v))"
        return 0
    fi

    # 执行安装逻辑
    echo "▶️ 正在准备缺失环境: ${TO_INSTALL_TOOLS[*]} ${NEED_NODE:+nodejs}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|devuan)
                echo "🔧 正在尝试强制修复 apt 依赖冲突..."
                local OPTS="-y -f -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\""
                apt-get update -y
                apt-get install $OPTS
                
                if [ "$NEED_NODE" = true ]; then
                    echo "🌐 正在配置 NodeSource 软件源..."
                    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
                fi
                apt-get install $OPTS "${TO_INSTALL_TOOLS[@]}" ${NEED_NODE:+nodejs}
                apt-get clean
                ;;
            centos|rhel|fedora)
                if [ "$NEED_NODE" = true ]; then
                    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
                fi
                dnf install -y "${TO_INSTALL_TOOLS[@]}" ${NEED_NODE:+nodejs}
                ;;
            alpine)
                apk update
                apk add --no-cache "${TO_INSTALL_TOOLS[@]}" ${NEED_NODE:+nodejs npm}
                ;;
            *)
                echo "❌ 无法识别系统类型 ($ID)，请手动安装依赖"
                exit 1
                ;;
        esac
    else
        echo "❌ 无法获取系统信息，请手动安装基础工具和 Node.js"
        exit 1
    fi

    # 最终验证
    if command -v node >/dev/null 2>&1; then
        echo "🎉 环境配置成功！Node.js 版本: $(node -v)"
    else
        echo "❌ Node.js 安装验证失败，请检查网络或系统源"
        exit 1
    fi
}

# 安装 npm 包
install_npm() {
    echo -e "\n▶️ 检查和安装 npm 包: ${TARGET_MODULE} ---"
    if [ ! -d "node_modules" ] || ! npm list "${TARGET_MODULE}" --depth=0 >/dev/null 2>&1; then
        npm install "${TARGET_MODULE}"
    else
        echo "🎉 ${TARGET_MODULE} 已安装且版本匹配，跳过..."
    fi
}

# 创建并启动服务 (始终重建/覆盖)
create_service() {
    define_vars # 变量赋值
    local NODE_BIN=$(command -v node)
    local APP_BIN="${SERVICE_DIR}/node_modules/.bin/${TARGET_MODULE}"
    
    echo -e "\n▶️ 配置并重启服务"

    # openrc 服务
    if command -v rc-update >/dev/null 2>&1; then
        echo "▶️ 正在生成 OpenRC 系统服务配置文件: ${OPENRC_CONF_FILE}"
        cat > "$OPENRC_CONF_FILE" << EOF
# Configuration for ${SERVICE_NAME}
UUID="${UUID}"
NEZHA_SERVER="${NEZHA_SERVER}"
NEZHA_PORT="${NEZHA_PORT}"
NEZHA_KEY="${NEZHA_KEY}"
ARGO_DOMAIN="${ARGO_DOMAIN}"
ARGO_AUTH="${ARGO_AUTH}"
CFIP="${CFIP}"
NAME="${NAME}"
EOF
        chmod 644 "$OPENRC_CONF_FILE"

        echo "▶️ 正在生成 OpenRC 系统服务逻辑文件: ${OPENRC_SERVICE_FILE}"
        cat > "$OPENRC_SERVICE_FILE" << EOF
#!/sbin/openrc-run
name="${SERVICE_NAME}"
description="Auto-configured NodeJS Argo Tunnel Service"
command="${NODE_BIN}"
command_args="${APP_BIN}"
command_background="yes"
directory="${SERVICE_DIR}"
user="${SYSTEM_USER}"
pidfile="/run/\${RC_SVCNAME}.pid"
depend() { need net; }
start_pre() {
    export UUID NEZHA_SERVER NEZHA_PORT NEZHA_KEY ARGO_DOMAIN ARGO_AUTH CFIP NAME
}
EOF
        chmod +x "$OPENRC_SERVICE_FILE"
        
        echo "✅ OpenRC 系统服务配置完成"
        rc-service "${SERVICE_NAME}" stop 2>/dev/null || true
        rc-update add "${SERVICE_NAME}" default 2>/dev/null || true
        rc-service "${SERVICE_NAME}" start
        echo "🎉 服务启动成功！状态查询：rc-service ${SERVICE_NAME} status"
    
    # systemd 服务
    else
        echo "▶️ 正在生成 Systemd 系统服务文件: ${SERVICE_FILE}"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Auto-configured NodeJS Argo Tunnel Service (Simplified)
After=network.target

[Service]
Type=simple
User=${SYSTEM_USER}
WorkingDirectory=${SERVICE_DIR}
Environment=UUID=${UUID}
Environment=NEZHA_SERVER=${NEZHA_SERVER}
Environment=NEZHA_PORT=${NEZHA_PORT}
Environment=NEZHA_KEY=${NEZHA_KEY}
Environment=ARGO_DOMAIN=${ARGO_DOMAIN}
Environment=ARGO_AUTH=${ARGO_AUTH}
Environment=CFIP=${CFIP}
Environment=NAME=${NAME}
ExecStart=${NODE_BIN} ${APP_BIN}
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        echo "✅ Systemd 服务文件创建成功"
        systemctl daemon-reload
        systemctl enable "${SERVICE_NAME}.service"
        systemctl restart "${SERVICE_NAME}.service"
        echo "🎉 服务启动成功！状态查询：sudo systemctl status ${SERVICE_NAME}"
    fi
}

# 主执行逻辑
clean_sysblock
setup_environment # 设置环境和权限
install_deps # 安装基础依赖和 Node.js
install_npm # 安装npm包 nodejs-argo
create_service # 创建/重启服务

echo -e "\n▶️ 等待核心进程写入节点信息 (最多等待 30 秒)" >&2  
for ((i=0; i < MAX_WAIT; i+=WAIT_INTERVAL)); do
    if [ -f "${SUB_FILE}" ]; then
        echo "✅ 节点信息文件已找到！" >&2
        break
    fi
    echo "等待 ${WAIT_INTERVAL} 秒... (${i}/${MAX_WAIT} 秒)" >&2
    sleep ${WAIT_INTERVAL}
done

echo -e "\n----- 🚀 节点信息 (Base64) -----"
if [ -f "${SUB_FILE}" ]; then
    cat "${SUB_FILE}"
    echo -e "\n-----------------------------"
else
    echo "❌ 警告：未在预期时间内找到节点信息文件 ${SUB_FILE}"
    echo "⚠️ 请稍后手动通过 SSH 连接检查：cat ${SUB_FILE}"
fi

exit 0 # 安装模式结束，退出

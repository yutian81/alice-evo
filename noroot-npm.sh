#!/usr/bin/env bash

# --- 配置区 ---
SERVICE_NAME="nodejs-argo"
TARGET_MODULE="nodejs-argo"
SCRIPT_URL="https://raw.githubusercontent.com/yutian81/alice-evo/main/vpsnpm.sh"
MAX_WAIT=30
WAIT_INTERVAL=3

# --- 权限与路径初始化 ---
if [ "$EUID" -eq 0 ]; then
    SERVICE_DIR="/opt/${SERVICE_NAME}"
    SYSTEM_USER="root"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
    OPENRC_CONF_FILE="/etc/conf.d/${SERVICE_NAME}"
else
    # 非 root 用户安装到用户目录，完全避开 sudo
    SERVICE_DIR="${HOME}/.${SERVICE_NAME}"
    SYSTEM_USER="$(whoami)"
    SERVICE_FILE="${HOME}/.config/systemd/user/${SERVICE_NAME}.service"
    # OpenRC 不支持非 root 写入 init.d，故不配置
fi

SCRIPT_PATH="${SERVICE_DIR}/vpsnpm.sh"
SUB_FILE="${SERVICE_DIR}/.npm/sub.txt"

# 变量定义和赋值
define_vars() {
    export UUID=${UUID:-'3001b2b7-e810-45bc-a1af-2c302b530d40'}
    export NEZHA_SERVER=${NEZHA_SERVER:-''}
    export NEZHA_PORT=${NEZHA_PORT:-''}
    export NEZHA_KEY=${NEZHA_KEY:-''}
    export ARGO_DOMAIN=${ARGO_DOMAIN:-''}
    export ARGO_AUTH=${ARGO_AUTH:-''}
    export CFIP=${CFIP:-'cf.090227.xyz'}
    export NAME=${NAME:-'NPM'}
}

# 清理系统锁 (仅 root 执行)
clean_sysblock() {
    [ "$EUID" -ne 0 ] && return
    echo "▶️ 正在清理系统软件包管理器锁..."
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop unattended-upgrades apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
    fi
    
    local LOCKS=("/var/lib/dpkg/lock" "/var/lib/dpkg/lock-frontend" "/var/lib/apt/lists/lock" "/var/cache/apt/archives/lock")
    for lock in "${LOCKS[@]}"; do
        [ -f "$lock" ] && rm -f "$lock"
    done
    
    if command -v dpkg >/dev/null 2>&1; then
        dpkg --configure -a 2>/dev/null || true
    fi
}

# 全自动化环境安装 (含 Root 包管理与非 Root NVM 逻辑)
install_environment() {
    echo -e "\n▶️ 正在检查系统依赖与 Nodejs 环境"
    
    # 1. 如果已存在 node 和 npm，直接跳过
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        echo "✅ Node.js 已就绪: $(node -v)"
        return 0
    fi

    # 2. 如果是 Root，使用包管理器
    if [ "$EUID" -eq 0 ]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                debian|ubuntu|devuan)
                    export DEBIAN_FRONTEND=noninteractive
                    apt-get update -y
                    apt-get install -y curl ca-certificates gnupg
                    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
                    apt-get install -y nodejs
                    ;;
                centos|rhel|fedora)
                    yum install -y curl
                    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
                    yum install -y nodejs
                    ;;
                alpine)
                    apk add --no-cache curl nodejs npm bash
                    ;;
                *)
                    echo "❌ 无法识别系统 ($ID)，请手动安装 Node.js" && exit 1
                    ;;
            esac
        fi
    # 3. 如果是非 Root，使用 NVM 自动化安装
    else
        echo "🚀 检测到非 Root 权限，正在通过 NVM 自动化安装 Node.js..."
        export NVM_DIR="$HOME/.nvm"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install --lts
        nvm use --lts
        nvm alias default 'lts/*'
    fi

    # 验证
    if ! command -v node >/dev/null 2>&1; then
        echo "❌ Node.js 自动化安装失败，请检查网络" && exit 1
    fi
}

# 安装项目依赖
setup_app() {
    mkdir -p "${SERVICE_DIR}"
    cd "${SERVICE_DIR}" || exit 1
    
    echo "▶️ 下载核心逻辑脚本..."
    curl -o "$SCRIPT_PATH" -Ls "$SCRIPT_URL" && chmod +x "$SCRIPT_PATH"

    echo "▶️ 安装 npm 模块: ${TARGET_MODULE}"
    [ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"
    
    if [ ! -d "node_modules" ] || ! npm list "${TARGET_MODULE}" --depth=0 >/dev/null 2>&1; then
        npm install "${TARGET_MODULE}" --no-audit --no-fund
    fi
}

# 创建并启动服务
create_service() {
    define_vars
    local NODE_BIN=$(command -v node)
    echo -e "\n▶️ 配置并启动服务..."

    # A. Root 用户逻辑
    if [ "$EUID" -eq 0 ]; then
        if command -v systemctl >/dev/null 2>&1; then
            cat > "$SERVICE_FILE" << EOF
[Unit]
Description=${SERVICE_NAME} Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${SERVICE_DIR}
Environment=UUID=${UUID} NEZHA_SERVER=${NEZHA_SERVER} NEZHA_PORT=${NEZHA_PORT} NEZHA_KEY=${NEZHA_KEY} ARGO_DOMAIN=${ARGO_DOMAIN} ARGO_AUTH=${ARGO_AUTH} CFIP=${CFIP} NAME=${NAME}
ExecStart=${NODE_BIN} ${SERVICE_DIR}/node_modules/.bin/${TARGET_MODULE}
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable --now "${SERVICE_NAME}"
            echo "🎉 Systemd 系统服务已启动"
        elif command -v rc-service >/dev/null 2>&1; then
            cat > "$OPENRC_CONF_FILE" << EOF
UUID="${UUID}"
NEZHA_SERVER="${NEZHA_SERVER}"
NEZHA_PORT="${NEZHA_PORT}"
NEZHA_KEY="${NEZHA_KEY}"
ARGO_DOMAIN="${ARGO_DOMAIN}"
ARGO_AUTH="${ARGO_AUTH}"
CFIP="${CFIP}"
NAME="${NAME}"
EOF
            cat > "$OPENRC_SERVICE_FILE" << EOF
#!/sbin/openrc-run
name="${SERVICE_NAME}"
description="Argo Service"
command="${NODE_BIN}"
command_args="${SERVICE_DIR}/node_modules/.bin/${TARGET_MODULE}"
command_background="yes"
directory="${SERVICE_DIR}"
pidfile="/run/\${RC_SVCNAME}.pid"
export UUID NEZHA_SERVER NEZHA_PORT NEZHA_KEY ARGO_DOMAIN ARGO_AUTH CFIP NAME
depend() { need net; }
EOF
            chmod +x "$OPENRC_SERVICE_FILE"
            rc-update add "${SERVICE_NAME}" default
            rc-service "${SERVICE_NAME}" restart
            echo "🎉 OpenRC 系统服务已启动"
        fi

    # B. 非 Root 用户逻辑
    else
        if command -v systemctl >/dev/null 2>&1; then
            mkdir -p "$(dirname "$SERVICE_FILE")"
            cat > "$SERVICE_FILE" << EOF
[Unit]
Description=${SERVICE_NAME} User Service

[Service]
Type=simple
WorkingDirectory=${SERVICE_DIR}
Environment=UUID=${UUID} NEZHA_SERVER=${NEZHA_SERVER} NEZHA_PORT=${NEZHA_PORT} NEZHA_KEY=${NEZHA_KEY} ARGO_DOMAIN=${ARGO_DOMAIN} ARGO_AUTH=${ARGO_AUTH} CFIP=${CFIP} NAME=${NAME}
ExecStart=${NODE_BIN} ${SERVICE_DIR}/node_modules/.bin/${TARGET_MODULE}
Restart=always

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload
            systemctl --user enable --now "${SERVICE_NAME}"
            echo "🎉 Systemd 用户服务已启动 (查看状态: systemctl --user status ${SERVICE_NAME})"
        else
            echo "⚠️ 无 Systemd 环境，使用 nohup 运行..."
            pkill -f "${TARGET_MODULE}" || true
            nohup env UUID="${UUID}" NEZHA_SERVER="${NEZHA_SERVER}" NEZHA_PORT="${NEZHA_PORT}" NEZHA_KEY="${NEZHA_KEY}" ARGO_DOMAIN="${ARGO_DOMAIN}" ARGO_AUTH="${ARGO_AUTH}" CFIP="${CFIP}" NAME="${NAME}" \
            ${NODE_BIN} "${SERVICE_DIR}/node_modules/.bin/${TARGET_MODULE}" > "${SERVICE_DIR}/argo.log" 2>&1 &
            echo "🎉 进程已在后台运行，日志：${SERVICE_DIR}/argo.log"
        fi
    fi
}

# 主程序入口
if [[ -z "$INVOCATION_ID" && -z "$OPENRC_INIT_DIR" ]]; then
    clean_sysblock
    install_environment
    setup_app
    create_service

    echo -e "\n▶️ 等待写入节点信息 (最多 30s)..."
    for ((i=0; i < MAX_WAIT; i+=WAIT_INTERVAL)); do
        if [ -f "${SUB_FILE}" ]; then
            echo "✅ 节点信息已生成！"
            echo -e "\n----- 🚀 节点信息 (Base64) -----"
            cat "${SUB_FILE}"
            echo -e "\n-----------------------------\n"
            exit 0
        fi
        sleep ${WAIT_INTERVAL}
    done
    echo "❌ 警告：未找到节点文件 ${SUB_FILE}，请检查日志。"
    exit 0
fi

# 核心进程启动逻辑 (用于被服务调用)
[ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"
npx "${TARGET_MODULE}"

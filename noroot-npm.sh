#!/usr/bin/env bash

# --- 1. 全局配置区 ---
SERVICE_NAME="nodejs-argo"
TARGET_MODULE="nodejs-argo"
SCRIPT_URL="https://raw.githubusercontent.com/yutian81/alice-evo/main/noroot-npm.sh"

# --- 2. 动态权限与路径识别 ---
if [ "$EUID" -eq 0 ]; then
    # [Root 模式]
    SERVICE_DIR="/opt/${SERVICE_NAME}"
    SYSTEM_USER="root"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
    OPENRC_CONF_FILE="/etc/conf.d/${SERVICE_NAME}"
else
    # [非 Root 模式] 路径位于用户主目录，无需 sudo
    SERVICE_DIR="${HOME}/.${SERVICE_NAME}"
    SYSTEM_USER="$(whoami)"
    SERVICE_FILE="${HOME}/.config/systemd/user/${SERVICE_NAME}.service"
    # 非 Root 无法写入系统级 /etc/init.d，OpenRC 将降级为 nohup
fi

SCRIPT_PATH="${SERVICE_DIR}/vpsnpm.sh"
SUB_FILE="${SERVICE_DIR}/.npm/sub.txt"
MAX_WAIT=30
WAIT_INTERVAL=3

# --- 3. 环境变量定义 ---
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

# --- 4. 系统锁清理 (仅 Root 有效) ---
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

# --- 5. 环境安装 (Root 包管理器 / 非 Root NVM) ---
install_environment() {
    echo -e "\n▶️ 检查系统依赖与 Node.js 环境..."
    
    # 5.1 检查是否存在可用 Node
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        echo "✅ Node.js 已就绪: $(node -v)"
        return 0
    fi

    # 5.2 Root 用户安装策略
    if [ "$EUID" -eq 0 ]; then
        [ -f /etc/os-release ] || { echo "❌ 无法读取系统信息，请手动安装 nodejs 后重试"; exit 1; }
        . /etc/os-release

        local APT_OPTS="-y -f -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\""
        export DEBIAN_FRONTEND=noninteractive
        
        case "$ID" in
            debian|ubuntu|devuan|kali)
                echo "🔧 检测到 Debian 系，使用 apt 安装..."
                apt-get update -y
                apt-get install $APT_OPTS curl ca-certificates gnupg
                curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
                apt-get install $APT_OPTS nodejs
                ;;
            centos|rhel|fedora|almalinux|rocky)
                echo "🔧 检测到 RHEL 系，使用 yum/dnf 安装..."
                local PKG_MGR="yum"
                command -v dnf >/dev/null 2>&1 && PKG_MGR="dnf"
                $PKG_MGR install -y curl ca-certificates
                curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
                $PKG_MGR install -y nodejs
                ;;
            alpine)
                echo "🔧 检测到 Alpine，使用 apk 安装..."
                apk add --no-cache curl nodejs npm bash ca-certificates
                ;;
            *)
                echo "❌ 不支持的系统: $ID，请手动安装 Node.js 后重试" && exit 1
                ;;
        esac

    # 5.3 非 Root 用户安装策略 (NVM)
    else
        echo "🚀 [非 Root] 正在通过 NVM 自动化安装 Node.js..."
        export NVM_DIR="$HOME/.nvm"
        
        # 安装 NVM
        if [ ! -d "$NVM_DIR" ]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        fi
        
        # 激活并安装 NVM
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        echo "⬇️ 正在下载 Node.js LTS..."
        nvm install --lts
        nvm use --lts
        nvm alias default 'lts/*'
    fi

    # 5.4 最终验证
    if ! command -v node >/dev/null 2>&1; then
        echo "❌ Node.js 安装失败，请检查网络连接。" && exit 1
    else
        echo "✅ Node.js 安装完成: $(node -v)"
    fi
}

# --- 6. 部署业务代码 ---
setup_app() {
    mkdir -p "${SERVICE_DIR}"
    cd "${SERVICE_DIR}" || exit 1
    
    echo "▶️ 下载辅助脚本..."
    curl -o "$SCRIPT_PATH" -Ls "$SCRIPT_URL" && chmod +x "$SCRIPT_PATH"

    echo "▶️ 安装/更新业务模块: ${TARGET_MODULE}"
    # 再次确保环境加载 (针对 NVM)
    [ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"
    
    # 初始化 package.json 并安装
    if [ ! -f "package.json" ]; then
        npm init -y >/dev/null 2>&1
    fi
    
    if ! npm list "${TARGET_MODULE}" --depth=0 >/dev/null 2>&1; then
        npm install "${TARGET_MODULE}" --no-audit --no-fund
    fi
}

# --- 7. 创建并启动服务 ---
create_service() {
    define_vars
    # 获取 node 的绝对路径 (至关重要，解决 systemd 找不到 nvm node 的问题)
    local NODE_BIN=$(command -v node)
    local APP_BIN="${SERVICE_DIR}/node_modules/.bin/${TARGET_MODULE}"
    
    echo -e "\n▶️ 生成并启动服务..."
    echo "   Node 路径: ${NODE_BIN}"
    echo "   程序 路径: ${APP_BIN}"

    # === 分支 A: Root 用户 (Systemd / OpenRC) ===
    if [ "$EUID" -eq 0 ]; then
        # A1. Systemd
        if command -v systemctl >/dev/null 2>&1; then
            cat > "$SERVICE_FILE" << EOF
[Unit]
Description=${SERVICE_NAME} Service (Systemd)
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
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable --now "${SERVICE_NAME}"
            echo "🎉 Systemd 系统服务已启动"

        # A2. OpenRC
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
description="Argo Service (OpenRC)"
command="${NODE_BIN}"
command_args="${APP_BIN}"
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

    # === 分支 B: 非 Root 用户 (Systemd User / Nohup) ===
    else
        # B1. Systemd (User Mode)
        if command -v systemctl >/dev/null 2>&1; then
            if [ ! -f "/var/lib/systemd/linger/${SYSTEM_USER}" ]; then
                echo "🔧 正在开启用户驻留模式 (Linger)..."
                loginctl enable-linger "${SYSTEM_USER}" || echo "⚠️ 自动开启 Linger 失败，请手动执行: loginctl enable-linger ${SYSTEM_USER}"
            else
                echo "✅ 用户驻留模式 (Linger) 已处于开启状态"
            fi
            mkdir -p "$(dirname "$SERVICE_FILE")"
            cat > "$SERVICE_FILE" << EOF
[Unit]
Description=${SERVICE_NAME} User Service

[Service]
Type=simple
WorkingDirectory=${SERVICE_DIR}
Environment=UUID=${UUID} NEZHA_SERVER=${NEZHA_SERVER} NEZHA_PORT=${NEZHA_PORT} NEZHA_KEY=${NEZHA_KEY} ARGO_DOMAIN=${ARGO_DOMAIN} ARGO_AUTH=${ARGO_AUTH} CFIP=${CFIP} NAME=${NAME}
ExecStart=${NODE_BIN} ${APP_BIN}
Restart=always
RestartSec=10s

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload
            systemctl --user enable --now "${SERVICE_NAME}"
            echo "🎉 Systemd 用户服务已启动"
            echo "⚠️  提示: 建议执行 'loginctl enable-linger $(whoami)' 以保持断开 SSH 后服务运行。"

        # B2. Nohup (兜底方案，适用于无 Systemd 的普通用户)
        else
            echo "⚠️ 无 Systemd 环境，降级使用 nohup 后台运行..."
            pkill -f "${TARGET_MODULE}" || true
            nohup env UUID="${UUID}" NEZHA_SERVER="${NEZHA_SERVER}" NEZHA_PORT="${NEZHA_PORT}" NEZHA_KEY="${NEZHA_KEY}" ARGO_DOMAIN="${ARGO_DOMAIN}" ARGO_AUTH="${ARGO_AUTH}" CFIP="${CFIP}" NAME="${NAME}" \
            "${NODE_BIN}" "${APP_BIN}" > "${SERVICE_DIR}/argo.log" 2>&1 &
            echo "🎉 进程已在后台启动，日志文件: ${SERVICE_DIR}/argo.log"
        fi
    fi
}

# --- 8. 主执行流程 ---
clean_sysblock
install_environment
setup_app
create_service

# --- 9. 结果展示 ---
echo -e "\n▶️ 等待节点信息生成 (超时 ${MAX_WAIT}s)..."
for ((i=0; i < MAX_WAIT; i+=WAIT_INTERVAL)); do
    if [ -f "${SUB_FILE}" ]; then
        echo "✅ 节点部署成功！"
        echo -e "\n----- 🚀 节点信息 (Base64) -----"
        cat "${SUB_FILE}"
        echo -e "\n-----------------------------\n"
        exit 0
    fi
    sleep ${WAIT_INTERVAL}
done

echo "❌ 警告：未在预期时间内找到节点文件 (${SUB_FILE})"
echo "   请检查服务状态或日志文件。"
exit 0

#!/usr/bin/env python3
# coding: utf-8

import os
import sys
import time
import shlex
import subprocess
import requests
import json
from datetime import datetime, timezone

# ----------------------------
# 配置（从环境变量读取）
# ----------------------------
ALICE_CLIENT_ID = os.environ.get("ALICE_CLIENT_ID", "")
ALICE_API_SECRET = os.environ.get("ALICE_API_SECRET", "")
AUTH_TOKEN = f"{ALICE_CLIENT_ID}:{ALICE_API_SECRET}"

ALICE_ACCOUNT_USER = os.environ.get("ALICE_ACCOUNT_USER", "")
ALICE_SSH_HOST = f"{ALICE_ACCOUNT_USER}.evo.host.aliceinit.dev" if ALICE_ACCOUNT_USER else ""

PRODUCT_ID = os.environ.get("PRODUCT_ID", "38")
OS_ID = os.environ.get("OS_ID", "1")
DEPLOY_TIME_HOURS = os.environ.get("DEPLOY_TIME_HOURS", "24")
ALICE_SSH_KEY_NAME = os.environ.get("ALICE_SSH_KEY_NAME", "alice-yutian81")
ALICE_SSH_KEY_ID = os.environ.get("ALICE_SSH_KEY_ID", "")  # 可被自动覆盖
NODEJS_COMMAND = os.environ.get("NODEJS_COMMAND", "")

API_BASE_URL = os.environ.get("API_BASE_URL", "https://app.alice.ws/cli/v1")
API_DESTROY_URL = f"{API_BASE_URL}/Evo/Destroy"
API_DEPLOY_URL = f"{API_BASE_URL}/Evo/Deploy"
API_LIST_URL = f"{API_BASE_URL}/Evo/Instance"
API_SSH_KEY_URL = f"{API_BASE_URL}/User/SSHKey"

TG_BOT_TOKEN = os.environ.get("TG_BOT_TOKEN", "")
TG_CHAT_ID = os.environ.get("TG_CHAT_ID", "")
TG_API_BASE = "https://api.telegram.org"

REQUEST_TIMEOUT = 20  # seconds

# ----------------------------
# 工具函数
# ----------------------------
def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def check_config():
    if not ALICE_CLIENT_ID or not ALICE_API_SECRET:
        eprint("❌ 错误：ALICE_CLIENT_ID 或 ALICE_API_SECRET 未设置。")
        sys.exit(1)
    if not ALICE_SSH_KEY_NAME:
        eprint("❌ 错误：ALICE_SSH_KEY_NAME 未设置，无法自动获取 SSH Key ID。")
        sys.exit(1)

def ensure_binary(name):
    """确保系统存在某个可执行文件（ssh）"""
    from shutil import which
    if which(name) is None:
        eprint(f"❌ 错误：系统中未找到 {name} 可执行文件，脚本无法继续。")
        sys.exit(1)

def escape_html(text: str) -> str:
    if text is None:
        return ""
    return (text.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;"))

# ----------------------------
# Telegram 通知
# ----------------------------
def send_tg_notification(message: str):
    if not TG_BOT_TOKEN or not TG_CHAT_ID:
        eprint("⚠️ 跳过 Telegram 通知 (未配置 TG_BOT_TOKEN 或 TG_CHAT_ID)。")
        return False

    url = f"{TG_API_BASE}/bot{TG_BOT_TOKEN}/sendMessage"
    eprint("▶️ 正在发送 Telegram 通知...")
    try:
        r = requests.post(url, data={
            "chat_id": TG_CHAT_ID,
            "text": message,
            "parse_mode": "HTML"
        }, timeout=10)
    except Exception as exc:
        eprint(f"❌ Telegram 连接失败: {exc}")
        return False

    if r.status_code == 200:
        eprint("✅ Telegram 通知发送成功。")
        return True
    else:
        eprint(f"❌ Telegram 通知发送失败 (HTTP {r.status_code})")
        try:
            eprint(r.text)
        except:
            pass
        return False

# ----------------------------
# 时间解析与剩余时间计算
# ----------------------------
def parse_datetime(s: str):
    if not s:
        return None
    # 尝试处理 ISO 格式（含 Z）
    try:
        # handle trailing Z
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        return datetime.fromisoformat(s)
    except Exception:
        # 备选简单解析：常见格式
        fmts = [
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%dT%H:%M:%S",
            "%Y-%m-%dT%H:%M:%S%z",
            "%Y-%m-%d %H:%M:%S%z",
        ]
        for f in fmts:
            try:
                return datetime.strptime(s, f)
            except Exception:
                continue
    return None

def calculate_remaining(creation_at: str, expiration_at: str) -> str:
    t1 = parse_datetime(creation_at)
    t2 = parse_datetime(expiration_at)
    if not t1 or not t2:
        return "未知"
    # 保证为 timezone-aware 或 naive 一致处理
    try:
        diff = int((t2 - t1).total_seconds())
    except Exception:
        return "未知"
    if diff <= 0:
        return "已过期"
    hours = diff // 3600
    minutes = (diff % 3600) // 60
    return f"{hours} 小时 {minutes} 分钟"

# ----------------------------
# Alice API：获取 SSH Key ID
# ----------------------------
def get_ssh_key_id(key_name: str):
    eprint(f"▶️ 正在尝试获取 SSH Key ID (名称: {key_name})...")
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    try:
        r = requests.get(API_SSH_KEY_URL, headers=headers, timeout=REQUEST_TIMEOUT)
    except Exception as exc:
        eprint(f"❌ 获取 SSH Key 列表失败（请求错误）：{exc}")
        return None, 1

    if r.status_code != 200:
        eprint(f"❌ 获取 SSH Key 列表失败 (HTTP {r.status_code})")
        return None, 1

    try:
        resp = r.json()
    except Exception:
        eprint("❌ 无法解析 SSH Key 列表响应为 JSON。")
        return None, 1

    status = resp.get("status")
    if status != 200:
        eprint(f"❌ 获取 SSH Key 列表失败 (API 状态: {status})")
        return None, 1

    data = resp.get("data", [])
    for item in data:
        if item.get("name") == key_name:
            key_id = item.get("id")
            eprint(f"✅ 成功获取 SSH Key ID: {key_id}")
            return key_id, 0

    eprint(f"❌ 错误：未找到名称为 {key_name} 的 SSH Key ID。")
    eprint("请注意：如果您希望使用的公钥尚未在 Alice 后台添加，请手动添加。")
    return None, 2

# ----------------------------
# Alice API：获取实例列表
# ----------------------------
def get_instance_ids():
    eprint("▶️ 正在尝试从 Alice API 获取实例列表...")
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    try:
        r = requests.get(API_LIST_URL, headers=headers, timeout=REQUEST_TIMEOUT)
    except Exception as exc:
        eprint(f"❌ 获取实例列表失败（请求错误）：{exc}")
        return None, 1

    if r.status_code != 200:
        eprint(f"❌ 获取实例列表失败 (HTTP {r.status_code})")
        return None, 1

    try:
        resp = r.json()
    except Exception:
        eprint("❌ 无法解析实例列表响应为 JSON。")
        return None, 1

    status = resp.get("status")
    if status != 200:
        eprint(f"❌ 获取实例列表失败 (API 状态: {status})")
        return None, 1

    ids = [str(item.get("id")) for item in resp.get("data", []) if item.get("id") is not None]
    if not ids:
        eprint("⚠️ 实例列表为空或未找到有效 ID。")
        return [], 2

    eprint("✅ 成功获取到以下实例 ID：" + " ".join(ids))
    return ids, 0

# ----------------------------
# Alice API：销毁实例
# ----------------------------
def destroy_instance(instance_id: str) -> bool:
    eprint(f"\n🔥 正在销毁实例 ID: {instance_id}...")
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    try:
        r = requests.post(API_DESTROY_URL, headers=headers, data={"id": instance_id}, timeout=REQUEST_TIMEOUT)
    except Exception as exc:
        eprint(f"❌ 实例 {instance_id} 销毁失败 (请求错误): {exc}")
        return False

    if r.status_code != 200:
        eprint(f"❌ 实例 {instance_id} 销毁失败 (HTTP {r.status_code})")
        return False

    try:
        resp = r.json()
    except Exception:
        eprint(f"❌ 实例 {instance_id} 销毁失败：无法解析 JSON")
        return False

    api_status = resp.get("status")
    message = resp.get("message", "无消息")
    if api_status == 200:
        eprint("状态: ✅ 销毁成功")
        eprint(f"消息: {message}")
        return True
    else:
        eprint("状态: ❌ 销毁失败")
        eprint(f"API 状态: {api_status}")
        eprint(f"错误信息: {message}")
        eprint(json.dumps(resp, indent=2))
        return False

# ----------------------------
# Alice API：部署实例
# ----------------------------
def deploy_instance():
    eprint(f"\n🚀 正在部署新实例 (Plan ID: {PRODUCT_ID}, OS ID: {OS_ID}, Time: {DEPLOY_TIME_HOURS}h...)")
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    data = {
        "product_id": PRODUCT_ID,
        "os_id": OS_ID,
        "time": DEPLOY_TIME_HOURS
    }
    if ALICE_SSH_KEY_ID:
        data["sshKey"] = ALICE_SSH_KEY_ID

    try:
        r = requests.post(API_DEPLOY_URL, headers=headers, data=data, timeout=REQUEST_TIMEOUT)
    except Exception as exc:
        eprint(f"❌ 实例创建失败：无法连接 API: {exc}")
        sys.exit(1)

    if r.status_code != 200:
        eprint(f"❌ API HTTP 错误: {r.status_code}")
        eprint(r.text)
        sys.exit(1)

    try:
        resp = r.json()
    except Exception:
        eprint("❌ 无法解析 API 返回（非 JSON）")
        eprint(r.text)
        sys.exit(1)

    status = resp.get("status")
    message = resp.get("message", "")

    if status != 200:
        TG_FAIL_MSG = (
            f"<b>❌ Alice Evo 部署失败！</b>\n"
            "========================\n"
            f"错误状态: {status}\n"
            f"错误消息: {escape_html(str(message))}\n"
            "========================\n"
            "请检查账户权限或 API 配置。"
        )
        send_tg_notification(TG_FAIL_MSG)
        eprint("状态: ❌ 创建失败")
        eprint("API 返回:")
        eprint(json.dumps(resp, indent=2, ensure_ascii=False))
        sys.exit(1)

    # 成功，提取字段
    data = resp.get("data", {}) or {}
    NEW_ID = str(data.get("id", ""))
    NEW_PLAN = data.get("plan", "")
    NEW_CPU = data.get("cpu", "")
    NEW_MEM = data.get("memory", "")
    NEW_DISK = data.get("disk", "")
    NEW_OS = data.get("os", "")
    NEW_IP = data.get("ipv4", "")
    NEW_IPV6 = data.get("ipv6", "")
    NEW_HOST = data.get("hostname", "")
    NEW_USER = data.get("user", "") or ""
    NEW_PASS = data.get("password", "") or ""
    NEW_STATUS = data.get("status", "")
    NEW_CREAT = data.get("creation_at", "")
    NEW_EXPIR = data.get("expiration_at", "")
    NEW_REGION = data.get("region", "")

    REMAINING = calculate_remaining(NEW_CREAT, NEW_EXPIR)

    DETAILS_TEXT = (
        f"\n实例 ID: {NEW_ID}\n"
        f"部署方案: {NEW_PLAN}\n"
        f"硬件配置: CPU: {NEW_CPU} G, 内存: {NEW_MEM} M, 磁盘: {NEW_DISK} G\n"
        f"操作系统: {NEW_OS}\n"
        f"区域: {NEW_REGION}\n"
        f"状态: {NEW_STATUS}\n"
        f"创建时间: {NEW_CREAT}\n"
        f"过期时间: {NEW_EXPIR}\n"
        f"剩余时间: {REMAINING}\n"
        f"IPv4 地址: <code>{NEW_IP}</code>\n"
        f"IPv6 地址: <code>{NEW_IPV6}</code>\n"
        f"主机名: <code>{NEW_HOST}</code>\n"
        f"用户名: <code>{NEW_USER}</code>\n"
        f"密码: <code>{NEW_PASS}</code>\n"
    )

    TG_SUCCESS_MSG = (
        f"<b>🎉 Alice Evo 部署成功！</b>\n"
        "========================\n"
        f"{DETAILS_TEXT}\n"
        "========================\n"
    )

    send_tg_notification(TG_SUCCESS_MSG)

    eprint("状态: ✅ 创建成功")
    eprint("----- 新实例详情 -----")
    eprint(DETAILS_TEXT)
    eprint("--------------------")

    # 返回字符串，保持兼容原 bash（NEW_ID NEW_IP NEW_USER NEW_PASS）
    return f"{NEW_ID} {NEW_IP} {NEW_USER} {NEW_PASS}"

# ----------------------------
# SSH 并执行远程脚本（使用系统 ssh）
# ----------------------------
def ssh_and_run_script(instance_ip: str, instance_user: str) -> bool:
    max_retries = 5
    wait_time = 10
    config_succeeded = False

    eprint("\n⚙️ 正在通过 SSH 登录并执行脚本...")
    eprint(f"目标: {instance_user}@{instance_ip} (端口: 22)")
    eprint("🔑 请确保 SSH 私钥已通过 webfactory/ssh-agent Action 注入。")

    # 将 NODEJS_COMMAND 作为 stdin 传给远程的 "bash -s"
    for i in range(1, max_retries + 1):
        eprint(f"尝试 SSH 连接和执行 (第 {i}/{max_retries} 次, 等待 {wait_time} 秒)...")
        ssh_cmd = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=15",
            "-T",
            f"{instance_user}@{instance_ip}",
            "bash -s"
        ]
        try:
            proc = subprocess.run(ssh_cmd, input=NODEJS_COMMAND.encode('utf-8'),
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
        except subprocess.TimeoutExpired:
            eprint("❌ SSH 命令超时。")
            proc = None

        if proc and proc.returncode == 0:
            eprint("✅ 远程脚本启动成功！")
            config_succeeded = True
            # 可选择打印远程输出到 stderr（如需）
            try:
                out = proc.stdout.decode('utf-8', errors='ignore')
                err = proc.stderr.decode('utf-8', errors='ignore')
                if out:
                    eprint("远程 stdout:")
                    eprint(out)
                if err:
                    eprint("远程 stderr:")
                    eprint(err)
            except Exception:
                pass
            break
        else:
            eprint("❌ SSH 连接或启动失败。")
            if proc:
                try:
                    eprint("远程 stderr:")
                    eprint(proc.stderr.decode('utf-8', errors='ignore'))
                except Exception:
                    pass
            eprint(f"等待 {wait_time} 秒后重试...")
            time.sleep(wait_time)

    if not config_succeeded:
        eprint(f"❌ 致命错误：SSH 连接或脚本启动在 {max_retries} 次尝试后失败。")
        return False

    return True

# ----------------------------
# 主流程
# ----------------------------
def main():
    ensure_binary("ssh")
    check_config()

    # 尝试获取 SSH Key ID（如果未提前提供）
    global ALICE_SSH_KEY_ID
    if not ALICE_SSH_KEY_ID:
        key_id, status = get_ssh_key_id(ALICE_SSH_KEY_NAME)
        if status != 0:
            eprint("❌ 无法获取 SSH Key ID，流程终止。")
            sys.exit(1)
        ALICE_SSH_KEY_ID = key_id

    # 获取并销毁现有实例
    ids, get_id_status = get_instance_ids()
    destroy_count = 0
    destroy_fail = 0

    eprint("\n==========================================")
    eprint("🔥 阶段一：批量销毁现有实例")
    eprint("==========================================")

    if get_id_status == 0:
        for iid in ids:
            ok = destroy_instance(iid)
            if ok:
                destroy_count += 1
            else:
                destroy_fail += 1
        eprint(f"✅ 成功销毁 {destroy_count} 个，失败 {destroy_fail} 个。")
    elif get_id_status == 2:
        eprint("⚠️ 未发现任何实例，跳过销毁阶段。")
    else:
        eprint("❌ 获取实例列表失败，跳过销毁阶段。")

    # 部署新实例
    eprint("\n==========================================")
    eprint("🚀 阶段二：部署新实例")
    eprint("==========================================")

    new_info = deploy_instance()
    if not new_info:
        eprint("\n❌ 流程失败：新实例部署失败，请检查账户权限和配置。")
        sys.exit(1)

    # 解析 deploy_instance 的返回值
    try:
        NEW_ID, NEW_IP, NEW_USER, NEW_PASS = new_info.split(None, 3)
    except Exception:
        eprint("❌ 无法解析 deploy_instance 的返回数据。")
        sys.exit(1)

    # 确定最终的 SSH 连接目标：优先使用 API 返回的 IP，否则使用预设 Hostname
    target_ip = NEW_IP if NEW_IP else ALICE_SSH_HOST
    if not NEW_USER:
        NEW_USER = "root"

    # SSH 执行配置脚本
    eprint("\n==========================================")
    eprint("⚙️ 阶段三：通过 SSH 执行远程配置")
    eprint("==========================================")

    remote_file = "/opt/nodejs-argo/tmp/sub.txt"
    if ssh_and_run_script(target_ip, NEW_USER):
        eprint(f"\n🎉 流程完成！新实例 {NEW_ID} 部署和配置已成功完成！")
        eprint(f"🎉 可手动连接 SSH，并执行 cat \"{remote_file}\" 命令获取节点内容")
        eprint(f"🎉 SSH连接信息：IP: {target_ip}, 端口: 22, 用户名: {NEW_USER}, 密码: {NEW_PASS}")
    else:
        eprint(f"\n❌ 流程失败：远程配置脚本执行失败。实例 {NEW_ID} 已创建，请登录 SSH 检查。")
        sys.exit(1)

if __name__ == "__main__":
    main()

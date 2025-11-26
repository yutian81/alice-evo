# alice-evo

## 一键全自动安装，适用于任意vps

> 支持 Debian | 乌班图 | Alpine

```bash
curl -o vpsnpm.sh -Ls "https://raw.githubusercontent.com/yutian81/alice-evo/main/vpsnpm.sh" && \
chmod +x vpsnpm.sh && \
UUID=822fb34f-af37-445f-8c05-ae35d5423b34 \
NEZHA_SERVER=nezha.example.com \
NEZHA_KEY=abcd1234 \
ARGO_DOMAIN=myargo.site \
ARGO_AUTH=eyJhIjoixxxxxx \
./vpsnpm.sh
```

一键卸载

```bash
bash <(curl -Ls https://raw.githubusercontent.com/yutian81/alice-evo/main/un-vpsnpm.sh)
```

## alice auto deploy

### 必须变量
- **ALICE_CLIENT_ID**
- **ALICE_API_SECRET**
- **ALICE_SSH_KEY**：私钥内容
- **NODEJS_COMMAND**: nodejs-argo远程脚本，必须包含 `ARGO_DOMAIN` 和 `ARGO_AUTH` 两个外置变量，以确保节点保活，内容为上述 `全自动安装代码`

### 可选变量
- ALICE_ACCOUNT_USER：alice账号用户名
- TG_BOT_TOKEN：TG通知需要
- TG_CHAT_ID：TG通知需要

### 实例参数配置
- PRODUCT_ID：部署方案ID，可选 38 | 39 | 40 | 41
- OS_ID：部署系统ID，可选 1-10
- DEPLOY_TIME_HOURS：VPS存活时长，可选1-24，单位：小时
- PRODUCT_ID 明细

| 参数   | ID值   | 名称    | 配置    |
| ------ | ----- | ------ |-------- |
| PRODUCT_ID | 38 | SLC.Evo.Micro 入门版 | 2c-4g-60g |
| PRODUCT_ID | 39 | SLC.Evo.Standard 标准版 | 4c-8g-120g |
| PRODUCT_ID | 40 | SLC.Evo.Pro 专业版 | 8c-16g-200g |
| PRODUCT_ID | 41 | SLC.Evo.Ultra 豪华版 | 16c-32g-300g |

- OS_ID 明细

| 参数  | ID值 | 系统类型 | 系统版本                         |
| ----- | --- | -------- | ------------------------------- |
| OS_ID | 1   | Debian   | Debian 12 (Bookworm) Minimal    |
| OS_ID | 2   | Debian   | Debian 11 (Bullseye) Minimal    |
| OS_ID | 10  | Debian   | Debian 12 DevKit    |
| OS_ID | 13  | Debian   | Debian 13 (Trixie) Minimal    |
| OS_ID | 3   | Ubuntu   | Ubuntu Server 20.04 LTS Minimal |
| OS_ID | 4   | Ubuntu   | Ubuntu Server 22.04 LTS Minimal |
| OS_ID | 5   | CentOS   | CentOS 7 Minimal |
| OS_ID | 6   | CentOS   | CentOS Stream 9 Minimal |
| OS_ID | 7   | AlmaLinux   | AlmaLinux 8 Minimal |
| OS_ID | 8   | AlmaLinux   | AlmaLinux 8 Minimal |
| OS_ID | 9   | Alpine    | Alpine Linux 3.19 |

### alice API

- **官方文档**：https://api.aliceinit.io/
- **基础地址 API_BASE_URL**: `https://app.alice.ws/cli/v1`
- **本项目使用到的 API 接口**

  - 授权类型：`Authorization: Bearer $AUTH_TOKEN`
  - Headers: `Content-Type:application/json`

| 接口功能   | 接口路径              | 请求方式 | 请求体 |
| --------- | --------------------- | ------- | ------ |
| 删除实例   | `/evo/instances/<id>` | DELETE  | 无     |
| 部署实例   | `/evo/instances/deploy` | POST  | "product_id": 38,</br>"os_id": 1,</br>"time": 24,</br>"ssh_key_id": 1099,</br>"boot_script": "base64编码后的命令" |
| 实例列表   | `/evo/instances`      | GET     | 无     |
| 用户信息   | `/account/profile`    | GET     | 无     |
| SSH 公钥列表 | `/account/ssh-keys` | GET     | 无     |

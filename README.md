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
NAME=IDX \
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
- **ALICE_SSH_KEY_NAME**：公钥名称
- **ALICE_SSH_KEY**：私钥内容
- **ARGO_DOMAIN**：重建实例后保持argo节点可用
- **ARGO_AUTH**：重建实例后保持argo节点可用

### 可选变量
- ALICE_ACCOUNT_USER：账号用户名
- UUID：哪吒需要
- NEZHA_SERVER：哪吒需要
- NEZHA_PORT：哪吒v0需要
- NEZHA_KEY：哪吒需要
- CFIP：CF优选域名或IP
- NAME：节点前缀名
- TG_BOT_TOKEN：TG通知需要
- TG_CHAT_ID：TG通知需要

### 实例参数配置
- PRODUCT_ID：部署方案ID，可选 38 | 39 | 40 | 41
- OS_ID：部署系统ID，可选 1-10
- DEPLOY_TIME_HOURS：部署系统时长，可选1-24，单位：小时

- PRODUCT_ID 明细

| 参数   | ID值   | 名称    | 注释    |
| ------ | ----- | ------ |-------- |
| PRODUCT_ID | 38 | SLC.Evo.Micro 入门版 | 2c-4g-60g |
| PRODUCT_ID | 39 | SLC.Evo.Standard 标准版 | 4c-8g-120g |
| PRODUCT_ID | 40 | SLC.Evo.Pro 专业版 | 8c-16g-200g |
| PRODUCT_ID | 41 | SLC.Evo.Pro 专业版 | 16c-32g-300g |

- OS_ID 明细

| 参数   | ID值   | 系统   | 版本参数   | ID值   | 版本号 |
| ------ | ----- | ------ |-----------|---------|------|
| group_id | 1 | Debian | OS_ID | 1 | Debian 12 (Bookworm) Minimal |
| group_id | 1 | Debian | OS_ID | 2 | Debian 11 (Bullseye) Minimal |
| group_id | 1 | Debian | OS_ID | 10 | Debian 12 DevKit |
| group_id | 2 | Ubuntu | OS_ID | 3 | Ubuntu Server 20.04 LTS Minimal |
| group_id | 2 | Ubuntu | OS_ID | 4 | Ubuntu Server 22.04 LTS Minimal |
| group_id | 3 | Centos | OS_ID | 5 | CentOS 7 Minimal |
| group_id | 3 | Centos | OS_ID | 6 | CentOS Stream 9 Minimal |
| group_id | 4 | AlmaLinux | OS_ID | 7 | AlmaLinux 8 Minimal |
| group_id | 4 | AlmaLinux | OS_ID | 8 | AlmaLinux 9 Latest |
| group_id | 6 | Alpine Linux | OS_ID | 9 | Alpine Linux 3.19 |

### alice API

- **官方文档**：https://api.aliceinit.io/

- 基础地址 **API_BASE_URL**
```
https://app.alice.ws/cli/v1
```

- API 端点明细

| 功能          | 端点             | 请求方式 | Bearer Token | 请求体 Body (formdata) | 
| ------------- | --------------- | ------- | ------------ | ---------------------- |
| 获取实例列表   | /Evo/Instance   | GET     | Token        | 无                    | 
| 部署实例      | /Evo/Deploy      | POST    | Token        | product_id、os_id、time、bootScript、sshKey  | 
| 销毁实例      | /Evo/Destroy     | POST    | Token        | id | 
| 操作实例      | /Evo/Power       | POST    | Token        | id、action |
| 重装系统      | /Evo/Rebuild     | POST    | Token        | id、os、bootScript、sshKey |
| 续订实例      | /Evo/Renewal     | POST    | Token        | id、time |
| 实例详情      | /Evo/State       | POST    | Token        | id |
| 异步执行命令  | /Command/executeAsync | POST | Token       | server_id、command |
| 命令执行结果  | /Command/getResult | POST   | Token        | command_uid、output_base64 |
| 实例方案列表  | /Evo/Plan         | GET     | Token        | 无 |
| 方案系统列表  | /Evo/getOSByPlan  | POST    | Token        | plan_id |
| 用户公钥列表  | /User/SSHKey      | GET     | Token        | 无 |
| 用户实例部署权限      | /User/EVOPermissions      | GET     | Token        | 无 |
| 用户信息      | /User/Info        | GET     | Token        | 无 |

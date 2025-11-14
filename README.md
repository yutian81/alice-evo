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

## alice alive
### 变量
- ALICE_CLIENT_ID
- ALICE_API_SECRET

### 常量
- **EVO 实例可选方案**

| 参数   | ID值   | 名称    | 注释    |
| ------ | ----- | ------ |-------- |
| PRODUCT_ID | 38 | SLC.Evo.Micro 入门版 | 2c-4g-60g |
| PRODUCT_ID | 39 | SLC.Evo.Standard 标准版 | 4c-8g-120g |
| PRODUCT_ID | 40 | SLC.Evo.Pro 专业版 | 8c-16g-200g |
| PRODUCT_ID | 41 | SLC.Evo.Pro 专业版 | 16c-32g-300g |

- **EVO 实例可选系统**

| 参数   | ID值   | 名称   | 版本参数   | ID值   | 版本号 |
| ------ | ----- | ------ |-----------|---------|------|
| group_id | 1 | Debian | OD_ID | 1 | Debian 12 (Bookworm) Minimal |
| group_id | 1 | Debian | OD_ID | 2 | Debian 11 (Bullseye) Minimal |
| group_id | 1 | Debian | OD_ID | 10 | Debian 12 DevKit |
| group_id | 2 | Ubuntu | OD_ID | 3 | Ubuntu Server 20.04 LTS Minimal |
| group_id | 2 | Ubuntu | OD_ID | 4 | Ubuntu Server 22.04 LTS Minimal |
| group_id | 3 | Centos | OD_ID | 5 | CentOS 7 Minimal |
| group_id | 3 | Centos | OD_ID | 6 | CentOS Stream 9 Minimal |
| group_id | 4 | AlmaLinux | OD_ID | 7 | AlmaLinux 8 Minimal |
| group_id | 4 | AlmaLinux | OD_ID | 8 | AlmaLinux 9 Latest |
| group_id | 6 | Alpine Linux | OD_ID | 9 | Alpine Linux 3.19 |

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

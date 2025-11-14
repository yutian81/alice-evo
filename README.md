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

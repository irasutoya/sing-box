# 代理服务一键安装脚本

## sing-box 版本

## 功能介绍

这是一个用于自动安装和配置 sing-box 的脚本，主要功能包括：

- 自动检测系统架构并安装对应版本
- 自动生成自签名证书
- 配置 hysteria2 协议
- 创建并启用 systemd 服务
- 生成客户端配置信息

## 系统要求

- 支持 Debian/Ubuntu 或 CentOS/RHEL 系列 Linux 系统
- 需要 root 权限运行
- 支持的系统架构：amd64, arm64, armv7, armv6, 386, mips64le, mipsle, ppc64le, riscv64, s390x, loong64

## 使用方法

### sing-box 安装

```shell
bash <(curl -fsSL https://raw.githubusercontent.com/irasutoya/sing-box/main/install.sh)
```

## 命令选项

### sing-box 选项

```shell
用法: install.sh [选项]

选项:
  -port        设置监听端口 (默认: 443)
  -password    设置访问密码 (默认: 随机生成)
  -uninstall   卸载 sing-box 服务及所有相关文件
  -help        显示帮助信息
```

### Xray 选项

```shell
用法: xray-install.sh [选项]

选项:
  -port        设置监听端口 (默认: 443)
  -uuid        设置 VLESS UUID (默认: 随机生成)
  -uninstall   卸载 Xray 服务及所有相关文件
  -help        显示帮助信息
```

## 安装路径

### sing-box 路径

- 主目录: `/root/sing-box`
- 可执行文件: `/root/sing-box/bin/sing-box`
- 配置文件: `/root/sing-box/config/config.json`
- 证书文件: `/root/sing-box/config/cert.pem` 和 `/root/sing-box/config/key.pem`
- 服务文件: `/etc/systemd/system/sing-box.service`

### Xray 路径

- 主目录: `/root/xray`
- 可执行文件: `/root/xray/bin/xray`
- 配置文件: `/root/xray/config/config.json`
- 服务文件: `/etc/systemd/system/xray.service`

## 客户端配置

安装完成后，脚本会自动生成以下格式的客户端配置信息：

### sing-box 客户端配置

#### VLESS URL 格式

```
vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&publicKey=${PUBLIC_KEY}&shortId=${SHORT_ID}#${SERVER_IP}
```

#### Clash Meta 格式

```yaml
proxies:
  - name: ${SERVER_IP}
    server: ${SERVER_IP}
    port: ${PORT}
    type: vless
    uuid: ${UUID}
    tls: true
    flow: xtls-rprx-vision
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
      servername: ${DOMAIN}
    client-fingerprint: chrome
    network: tcp
```

### Xray 客户端配置

#### VLESS URL 格式

```
vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#${SERVER_IP}
```

#### Clash Meta 格式

```yaml
proxies:
  - name: ${SERVER_IP}
    server: ${SERVER_IP}
    port: ${PORT}
    type: vless
    uuid: ${UUID}
    tls: true
    flow: xtls-rprx-vision
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
      servername: ${DOMAIN}
    client-fingerprint: chrome
    network: tcp

```
hysteria2://{PASSWORD}@{SERVER_IP}:{PORT}/?insecure=1#{SERVER_IP}
```

### Clash Meta 格式

```yaml
proxies:
  - name: {SERVER_IP}
    type: hysteria2
    server: {SERVER_IP}
    port: {PORT}
    password: {PASSWORD}
    skip-cert-verify: true
```

## 故障排除

- 如果服务启动失败，可以使用 `journalctl -u sing-box` 查看详细日志
- 确保防火墙已开放对应端口
- 如需重新配置，可以先卸载再重新安装

## 警告

本程序仅供学习了解, 非盈利目的，请于下载后 24 小时内删除, 不得用作任何商业用途, 文字、数据及图片均有所属版权, 如转载须注明来源。

使用本程序必循遵守部署免责声明。使用本程序必循遵守部署服务器所在地、所在国家和用户所在国家的法律法规, 程序作者不对使用者任何不当行为负责。

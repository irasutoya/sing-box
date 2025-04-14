#!/bin/bash

# 默认参数
BASE_DIR="/root/sing-box"
INSTALL_DIR="${BASE_DIR}/bin"
CONFIG_DIR="${BASE_DIR}/config"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DOMAIN="gateway.icloud.com"
CERT_FILE="${CONFIG_DIR}/cert.pem"
KEY_FILE="${CONFIG_DIR}/key.pem"
PORT=443
PASSWORD=$(cat /proc/sys/kernel/random/uuid)

# 打印日志函数
log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}

error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# 帮助信息
show_help() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -port        设置监听端口 (默认: 443)"
  echo "  -password    设置访问密码 (默认: 随机生成)"
  echo "  -uninstall   卸载 sing-box 服务及所有相关文件"
  echo "  -help        显示帮助信息"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    -port)
      PORT="$2"
      shift 2
      ;;
    -password)
      PASSWORD="$2"
      shift 2
      ;;
    -uninstall)
      UNINSTALL=true
      shift
      ;;
    -help)
      show_help
      exit 0
      ;;
    *)
      error "未知参数: $1"
      show_help
      exit 1
      ;;
  esac
done

# 检查是否是 root 用户
if [ "$EUID" -ne 0 ]; then
  error "请使用 root 用户运行此脚本"
  exit 1
fi

# 卸载函数
uninstall() {
  log "开始卸载 sing-box 服务和相关文件..."
  
  systemctl stop sing-box 2>/dev/null
  systemctl disable sing-box 2>/dev/null
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  rm -rf "$BASE_DIR"
  
  log "卸载完成！"
  exit 0
}

# 如果传入 -uninstall 参数，则执行卸载
if [ "$UNINSTALL" = true ]; then
  uninstall
fi

# 安装依赖
install_dependencies() {
  log "安装必要的依赖..."
  if command -v apt-get > /dev/null; then
    apt-get update -qq && apt-get install -y -qq curl wget jq openssl
  elif command -v yum > /dev/null; then
    yum install -y -q curl wget jq openssl
  else
    error "不支持的包管理器，请手动安装 curl、wget、jq 和 openssl"
    exit 1
  fi
  log "依赖安装完成！"
}

# 确定架构
determine_architecture() {
  log "检测系统架构..."
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    armv6l) ARCH="armv6" ;;
    i386 | i686) ARCH="386" ;;
    mips64le) ARCH="mips64le" ;;
    mipsle) ARCH="mipsle" ;;
    ppc64le) ARCH="ppc64le" ;;
    riscv64) ARCH="riscv64" ;;
    s390x) ARCH="s390x" ;;
    loongarch64) ARCH="loong64" ;;
    *) error "不支持的架构：$ARCH"; exit 1 ;;
  esac
  log "检测到架构：$ARCH"
}

# 下载并安装 sing-box
install_sing_box() {
  log "下载并安装 sing-box..."
  mkdir -p "$INSTALL_DIR"
  LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
  DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION:1}-linux-${ARCH}.tar.gz"

  wget -q -O "/tmp/sing-box.tar.gz" "${DOWNLOAD_URL}"
  tar -xzf "/tmp/sing-box.tar.gz" -C "/tmp"
  mv "/tmp/sing-box-${LATEST_VERSION:1}-linux-${ARCH}/sing-box" "${INSTALL_DIR}/sing-box"
  rm -rf "/tmp/sing-box.tar.gz" "/tmp/sing-box-${LATEST_VERSION:1}-linux-${ARCH}"
  chmod +x "${INSTALL_DIR}/sing-box"
  log "sing-box 已安装到 ${INSTALL_DIR}/sing-box"
}

# 生成自签名证书
generate_certificates() {
  log "生成自签名证书..."
  mkdir -p "$CONFIG_DIR"
  openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" -days 3650 -nodes -subj "/CN=${DOMAIN}" > /dev/null 2>&1
  log "自签名证书已生成！"
}

# 创建配置文件
create_config_file() {
  log "创建配置文件..."
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<EOF
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${PORT},
            "users": [
                {
                    "password": "${PASSWORD}"
                }
            ],
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "${CERT_FILE}",
                "key_path": "${KEY_FILE}"
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF
  log "配置文件已生成：${CONFIG_FILE}"
}

# 创建 systemd 服务文件
create_systemd_service() {
  log "创建 systemd 服务文件..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sing-box Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  log "systemd 服务文件已创建：${SERVICE_FILE}"
}

# 打印客户端配置
print_client_config() {
  SERVER_IP=$(curl -s https://api.ipify.org)
  V2RAY_URL="hysteria2://${PASSWORD}@${SERVER_IP}:${PORT}/?insecure=1#${SERVER_IP}"
  CLASH_META_URL="proxies:
  - name: ${SERVER_IP}
    type: hysteria2
    server: ${SERVER_IP}
    port: ${PORT}
    password: ${PASSWORD}
    skip-cert-verify: true"
  
  echo
  echo -e "\033[1;34m====== 客户端配置 (V2Ray 格式) ======\033[0m"
  echo "${V2RAY_URL}"
  echo
  echo -e "\033[1;34m====== 客户端配置 (Clash Meta 格式) ======\033[0m"
  echo "${CLASH_META_URL}"
  echo
}

# 启动服务
start_service() {
  log "启动 sing-box 服务..."
  systemctl start sing-box
  systemctl enable sing-box
  log "sing-box 服务已启动并设置为开机启动！"
}

# 主函数
main() {
  install_dependencies
  determine_architecture
  install_sing_box
  generate_certificates
  create_config_file
  create_systemd_service
  start_service
  log "sing-box 安装完成！文件路径：${BASE_DIR}"
  print_client_config
}

main

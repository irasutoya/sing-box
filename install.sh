#!/bin/bash

# 默认参数
BASE_DIR="/root/hysteria2"
INSTALL_DIR="${BASE_DIR}/bin"
CONFIG_DIR="${BASE_DIR}/config"
SERVICE_FILE="/etc/systemd/system/hysteria2.service"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
CERT_FILE="${CONFIG_DIR}/cert.pem"
KEY_FILE="${CONFIG_DIR}/key.pem"
LOG_FILE="${BASE_DIR}/hysteria2.log"
PORT=443
DOMAIN="bing.com"
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
  echo "  -dir         设置文件存放的基础目录 (默认: /root/hysteria2)"
  echo "  -port        设置监听端口 (默认: 443)"
  echo "  -domain      设置伪装域名 (默认: bing.com)"
  echo "  -password    设置访问密码 (默认: 随机生成)"
  echo "  -help        显示帮助信息"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    -dir)
      BASE_DIR="$2"
      shift 2
      ;;
    -port)
      PORT="$2"
      shift 2
      ;;
    -domain)
      DOMAIN="$2"
      shift 2
      ;;
    -password)
      PASSWORD="$2"
      shift 2
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

# 根据 BASE_DIR 设置其他路径
INSTALL_DIR="${BASE_DIR}/bin"
CONFIG_DIR="${BASE_DIR}/config"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
CERT_FILE="${CONFIG_DIR}/cert.pem"
KEY_FILE="${CONFIG_DIR}/key.pem"
LOG_FILE="${BASE_DIR}/hysteria2.log"

# 检查是否是 root 用户
if [ "$EUID" -ne 0 ]; then
  error "请使用 root 用户运行此脚本"
  exit 1
fi

# 安装依赖
install_dependencies() {
  log "安装必要的依赖..."
  if command -v apt-get > /dev/null; then
    apt-get update -qq > /dev/null && apt-get install -y -qq curl wget jq openssl > /dev/null
  elif command -v yum > /dev/null; then
    yum install -y -q curl wget jq openssl > /dev/null
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
    i386 | i686) ARCH="386" ;;
    x86_64)
      if grep -q avx /proc/cpuinfo; then
        ARCH="amd64-avx"
      else
        ARCH="amd64"
      fi
      ;;
    armv5*) ARCH="armv5" ;;
    armv7l) ARCH="arm" ;;
    aarch64) ARCH="arm64" ;;
    mipsle) ARCH="mipsle" ;;
    mipsle-sf) ARCH="mipsle-sf" ;;
    riscv64) ARCH="riscv64" ;;
    s390x) ARCH="s390x" ;;
    *)
      error "不支持的架构：$ARCH"
      exit 1
      ;;
  esac
  log "检测到架构：$ARCH"
}

# 下载并安装 hysteria2
install_hysteria2() {
  log "下载并安装 hysteria2..."

  # 如果服务正在运行，先停止服务
  if systemctl is-active --quiet hysteria2; then
    log "检测到 hysteria2 服务正在运行，停止服务以更新文件..."
    systemctl stop hysteria2
  fi

  mkdir -p "$INSTALL_DIR"
  LATEST_VERSION=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | jq -r .tag_name)
  DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_VERSION}/hysteria-linux-${ARCH}"

  wget -q -O "${INSTALL_DIR}/hysteria2" "${DOWNLOAD_URL}"
  chmod +x "${INSTALL_DIR}/hysteria2"
  log "hysteria2 已成功安装到 ${INSTALL_DIR}/hysteria2"
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
# 监听地址与端口
listen: :${PORT}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}

# 认证方式
auth:
  type: password
  password: ${PASSWORD}

# 流量伪装
masquerade:
  type: proxy
  proxy:
    url: https://${DOMAIN}
    rewriteHost: true
EOF
  log "配置文件已生成：${CONFIG_FILE}"
}

# 创建 systemd 服务文件
create_systemd_service() {
  log "创建 systemd 服务文件..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Hysteria2 Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/hysteria2 server --config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  log "systemd 服务文件已创建：${SERVICE_FILE}"
}

# 打印客户端配置 (hysteria2 URL)
print_client_config() {
  SERVER_IP=$(curl -s ifconfig.me) # 自动获取服务器外网 IP
  HYSTERIA_URL="hysteria2://${PASSWORD}@${SERVER_IP}:${PORT}/?insecure=1&sni=${DOMAIN}#${SERVER_IP}"
  CLASH_META_URL="proxies:
  - name: ${SERVER_IP}
    type: hysteria2
    server: ${SERVER_IP}
    port: ${PORT}
    password: ${PASSWORD}
    sni: ${DOMAIN}
    alpn:
      - h3"
  
  echo
  echo -e "\033[1;34m====== 客户端配置 (URL 格式) ======\033[0m"
  echo "${HYSTERIA_URL}"
  echo
  echo -e "\033[1;34m====== 客户端配置 (Clash Meta 格式) ======\033[0m"
  echo "${CLASH_META_URL}"
  echo
}

# 启动并启用服务
start_service() {
  log "启动 hysteria2 服务..."
  systemctl start hysteria2 > /dev/null 2>&1
  systemctl enable hysteria2 > /dev/null 2>&1
  log "hysteria2 服务已启动并设置为开机启动！"
}

# 主函数
main() {
  install_dependencies
  determine_architecture
  install_hysteria2
  generate_certificates
  create_config_file
  create_systemd_service
  start_service
  log "hysteria2 安装完成！所有文件存放于：${BASE_DIR}"
  log "配置文件路径：${CONFIG_FILE}"
  print_client_config
}

main

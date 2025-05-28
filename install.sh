#!/bin/bash

# sing-box 安装脚本

# 全局变量定义
BASE_DIR="/root/sing-box"
INSTALL_DIR="${BASE_DIR}/bin"
CONFIG_DIR="${BASE_DIR}/config"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DOMAIN="itunes.apple.com"
CERT_FILE="${CONFIG_DIR}/cert.pem"
KEY_FILE="${CONFIG_DIR}/key.pem"
PORT=443
PASSWORD=$(cat /proc/sys/kernel/random/uuid)

# 颜色定义
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

# 日志函数
log() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
  echo -e "${BLUE}sing-box 安装脚本${NC}"
  echo -e "用法: $0 [选项]"
  echo
  echo -e "选项:"
  echo -e "  ${GREEN}-port${NC}        设置监听端口 (默认: 443)"
  echo -e "  ${GREEN}-password${NC}    设置访问密码 (默认: 随机生成)"
  echo -e "  ${GREEN}-uninstall${NC}   卸载 sing-box 服务及所有相关文件"
  echo -e "  ${GREEN}-help${NC}        显示帮助信息"
}

# 参数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    -port)
      if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then
        error "端口必须是有效的数字"
        exit 1
      fi
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

# 检查是否为 root 用户
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

# 如果是卸载模式，执行卸载函数
if [ "$UNINSTALL" = true ]; then
  uninstall
fi

# 安装依赖
install_dependencies() {
  log "安装必要的依赖..."
  if command -v apt-get > /dev/null; then
    apt-get update -qq && apt-get install -y -qq curl wget jq openssl || {
      error "安装依赖失败，请检查网络连接或手动安装"
      exit 1
    }
  elif command -v yum > /dev/null; then
    yum install -y -q curl wget jq openssl || {
      error "安装依赖失败，请检查网络连接或手动安装"
      exit 1
    }
  else
    error "不支持的包管理器，请手动安装 curl、wget、jq 和 openssl"
    exit 1
  fi
  log "依赖安装完成！"
}

# 检测系统架构
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
    *) 
      error "不支持的架构：$ARCH"
      exit 1 
      ;;
  esac
  log "检测到架构：$ARCH"
}

# 安装 sing-box
install_sing_box() {
  log "下载并安装 sing-box..."
  mkdir -p "$INSTALL_DIR"
  
  # 获取最新版本
  LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
  if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
    error "获取最新版本失败，请检查网络连接或 GitHub API 访问"
    exit 1
  fi
  
  DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION:1}-linux-${ARCH}.tar.gz"
  log "下载版本: ${LATEST_VERSION}, 架构: ${ARCH}"
  
  # 下载并解压
  wget -q -O "/tmp/sing-box.tar.gz" "$DOWNLOAD_URL" || {
    error "下载 sing-box 失败，请检查网络连接"
    exit 1
  }
  
  tar -xzf "/tmp/sing-box.tar.gz" -C "/tmp" || {
    error "解压 sing-box 失败"
    exit 1
  }
  
  # 移动文件并清理
  mv "/tmp/sing-box-${LATEST_VERSION:1}-linux-${ARCH}/sing-box" "$INSTALL_DIR/sing-box" || {
    error "安装 sing-box 失败"
    exit 1
  }
  
  rm -rf "/tmp/sing-box.tar.gz" "/tmp/sing-box-${LATEST_VERSION:1}-linux-${ARCH}"
  chmod +x "$INSTALL_DIR/sing-box"
  log "sing-box 已安装到 $INSTALL_DIR/sing-box"
}

# 生成证书
generate_certificates() {
  log "生成自签名证书..."
  mkdir -p "$CONFIG_DIR"
  openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" -days 3650 -nodes -subj "/CN=${DOMAIN}" > /dev/null 2>&1 || {
    error "生成证书失败"
    exit 1
  }
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
        "server_name": "${DOMAIN}",
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
  log "配置文件已生成：$CONFIG_FILE"
}

# 创建 systemd 服务
create_systemd_service() {
  log "创建 systemd 服务文件..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=sing-box Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload || {
    error "重新加载 systemd 失败"
    exit 1
  }
  log "systemd 服务文件已创建：$SERVICE_FILE"
}

# 打印客户端配置
print_client_config() {
  log "获取服务器 IP 地址..."
  SERVER_IP=$(curl -s https://api.ipify.org)
  if [[ -z "$SERVER_IP" ]]; then
    warn "无法获取服务器 IP 地址，将使用 localhost 代替"
    SERVER_IP="localhost"
  fi
  
  # 生成 V2Ray 格式的 URL
  V2RAY_URL="hysteria2://${PASSWORD}@${SERVER_IP}:${PORT}/?insecure=1&sni=${DOMAIN}#${SERVER_IP}"
  CLASH_META_CONFIG="proxies:
  - name: ${SERVER_IP}
    type: hysteria2
    server: ${SERVER_IP}
    port: ${PORT}
    password: ${PASSWORD}
    sni: ${DOMAIN}
    alpn: 
      - h3
    skip-cert-verify: true"

  # 打印配置信息
  echo
  echo -e "${BLUE}====== 客户端配置 (V2Ray 格式) ======${NC}"
  echo "$V2RAY_URL"
  echo
  echo -e "${BLUE}====== 客户端配置 (Clash Meta 格式) ======${NC}"
  echo "$CLASH_META_CONFIG"
  echo
}

start_service() {
  log "启动 sing-box 服务..."
  systemctl start sing-box || {
    error "启动 sing-box 服务失败，请检查日志: journalctl -u sing-box"
    exit 1
  }
  
  systemctl enable sing-box || {
    warn "设置 sing-box 服务开机启动失败"
  }
  
  # 检查服务状态
  if systemctl is-active --quiet sing-box; then
    log "sing-box 服务已成功启动并设置为开机启动！"
  else
    error "sing-box 服务启动失败，请检查日志: journalctl -u sing-box"
    exit 1
  fi
}

# 主函数
main() {
  log "开始安装 sing-box..."
  install_dependencies
  determine_architecture
  install_sing_box
  generate_certificates
  create_config_file
  create_systemd_service
  start_service
  log "sing-box 安装完成！文件路径：$BASE_DIR"
  print_client_config
}

# 执行主函数
main
#!/bin/bash

# Xray VLESS + Vision + REALITY 安装脚本

# 全局变量定义
BASE_DIR="/root/xray"
INSTALL_DIR="${BASE_DIR}/bin"
CONFIG_DIR="${BASE_DIR}/config"
SERVICE_FILE="/etc/systemd/system/xray.service"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DOMAIN="updates.cdn-apple.com"
PORT=443
UUID=$(cat /proc/sys/kernel/random/uuid)
PRIVATE_KEY=""
PUBLIC_KEY=""
SHORT_ID=$(openssl rand -hex 8)

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
  echo -e "${BLUE}Xray VLESS + Vision + REALITY 安装脚本${NC}"
  echo -e "用法: $0 [选项]"
  echo
  echo -e "选项:"
  echo -e "  ${GREEN}-port${NC}        设置监听端口 (默认: 443)"
  echo -e "  ${GREEN}-uuid${NC}        设置 VLESS UUID (默认: 随机生成)"
  echo -e "  ${GREEN}-uninstall${NC}   卸载 Xray 服务及所有相关文件"
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
    -uuid)
      UUID="$2"
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
  log "开始卸载 Xray 服务和相关文件..."
  systemctl stop xray 2>/dev/null
  systemctl disable xray 2>/dev/null
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
    x86_64) ARCH="64" ;;
    aarch64) ARCH="arm64-v8a" ;;
    armv7l) ARCH="arm32-v7a" ;;
    armv6l) ARCH="arm32-v6" ;;
    i386 | i686) ARCH="32" ;;
    mips64le) ARCH="mips64le" ;;
    mipsle) ARCH="mipsle" ;;
    *)
      error "不支持的架构：$ARCH"
      exit 1
      ;;
  esac
  log "检测到架构：$ARCH"
}

# 安装 Xray
install_xray() {
  log "下载并安装 Xray..."
  mkdir -p "$INSTALL_DIR"

  # 获取最新版本
  LATEST_VERSION=$(curl -s -m 10 https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
  if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
    warn "获取最新版本失败，尝试使用备用方法..."
    LATEST_VERSION=$(curl -s -m 10 https://api.github.com/repos/XTLS/Xray-core/tags | jq -r '.[0].name')
    
    if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
      error "无法获取 Xray 版本信息，请检查网络连接或 GitHub API 访问"
      exit 1
    fi
  fi

  DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_VERSION}/Xray-linux-${ARCH}.zip"
  log "下载版本: ${LATEST_VERSION}, 架构: ${ARCH}"

  # 下载并解压
  wget -q -O "/tmp/xray.zip" "$DOWNLOAD_URL" || {
    error "下载 Xray 失败，请检查网络连接"
    exit 1
  }
  
  # 验证下载文件
  if [ -s "/tmp/xray.zip" ]; then
    log "下载完成，验证文件..."
  else
    error "下载的文件为空，请检查网络连接或下载链接"
    exit 1
  fi

  mkdir -p "/tmp/xray"
  unzip -q "/tmp/xray.zip" -d "/tmp/xray" || {
    error "解压 Xray 失败"
    exit 1
  }

  # 移动文件并清理
  mv "/tmp/xray/xray" "$INSTALL_DIR/xray" || {
    error "安装 Xray 失败"
    exit 1
  }

  rm -rf "/tmp/xray.zip" "/tmp/xray"
  chmod +x "$INSTALL_DIR/xray"
  log "Xray 已安装到 $INSTALL_DIR/xray"
}

# 生成 REALITY 密钥对
generate_reality_keypair() {
  log "生成 REALITY 密钥对..."
  warn "这可能需要一些时间，请耐心等待..."
  KEYPAIR=$($INSTALL_DIR/xray x25519)
  if [ $? -ne 0 ]; then
    error "生成 REALITY 密钥对失败"
    exit 1
  fi
  
  # 解析密钥对
  PRIVATE_KEY=$(echo "$KEYPAIR" | grep "Private key" | awk -F: '{print $2}' | tr -d ' ')
  PUBLIC_KEY=$(echo "$KEYPAIR" | grep "Public key" | awk -F: '{print $2}' | tr -d ' ')
  
  if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    error "解析 REALITY 密钥对失败"
    exit 1
  fi
  
  log "REALITY 密钥对已生成！"
}

# 创建配置文件
create_config_file() {
  log "创建配置文件..."
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "::",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DOMAIN}:443",
          "serverNames": ["${DOMAIN}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
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
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/xray run -c ${CONFIG_FILE}
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

  VLESS_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#${SERVER_IP}"
  CLASH_META_CONFIG="proxies:
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
    network: tcp"

  # 打印配置信息
  echo
  echo -e "${BLUE}====== 客户端配置 (VLESS URL) ======${NC}"
  echo "$VLESS_URL"
  echo
  echo -e "${BLUE}====== 客户端配置 (Clash Meta 格式) ======${NC}"
  echo -e "$CLASH_META_CONFIG"
  echo
}

start_service() {
  log "启动 Xray 服务..."
  systemctl start xray || {
    error "启动 Xray 服务失败，请检查日志: journalctl -u xray"
    exit 1
  }

  systemctl enable xray || {
    warn "设置 Xray 服务开机启动失败"
  }

  # 检查服务状态
  if systemctl is-active --quiet xray; then
    log "Xray 服务已成功启动并设置为开机启动！"
  else
    error "Xray 服务启动失败，请检查日志: journalctl -u xray"
    exit 1
  fi
}

# 处理中断信号
cleanup() {
  echo
  warn "安装被用户中断，正在清理..."
  rm -rf "/tmp/xray.zip" "/tmp/xray"
  exit 1
}

# 设置中断处理
trap cleanup INT TERM

# 主函数
main() {
  log "开始安装 Xray..."
  install_dependencies
  determine_architecture
  install_xray
  generate_reality_keypair
  create_config_file
  create_systemd_service
  start_service
  log "Xray 安装完成！文件路径：$BASE_DIR"
  print_client_config
}

# 执行主函数
main
#!/bin/bash
# Multi-OS: VLESS+TLS+XHTTP+CF SaaS (极速纯净修复版)

# 0. 权限检查
[ "$(id -u)" != "0" ] && echo "请使用 root 运行: sudo su -" && exit 1

clear
echo "=== VLESS+TLS+XHTTP+CF SaaS 极简安装 ==="

# 1. 信息收集
read_input() {
    printf "%s" "$1"
    read -r "$2"
}

read_input "证书模式 [1.CF自动申请 2.自定义路径 3.自签IP证书] (默认 1): " C; C=${C:-1}

if [ "$C" = "1" ]; then
    read_input "主域名 (例如 example.com): " D
    read_input "域名前缀 (默认 $(hostname)): " P; P=${P:-$(hostname)}
    read_input "CF 注册邮箱: " M
    read_input "CF API Token (拥有 DNS 编辑权限): " T
    FD="$P.$D"
    [ -z "$D" ] || [ -z "$M" ] || [ -z "$T" ] && echo "参数缺失！" && exit 1
elif [ "$C" = "2" ]; then
    read_input "绑定域名/IP: " FD
    read_input "公钥绝对路径: " C_P
    read_input "私钥绝对路径: " K_P
    [ ! -f "$C_P" ] || [ ! -f "$K_P" ] && echo "证书文件不存在！" && exit 1
else
    read_input "绑定域名/公网IP: " FD
    [ -z "$FD" ] && exit 1
fi

read_input "优选IP (默认 saas.sin.fan): " CDN; CDN=${CDN:-saas.sin.fan}
read_input "监听端口 (443/2053/2083/2087/2096/8443, 默认443): " PORT; PORT=${PORT:-443}

echo "$PORT" | grep -Eq '^(443|2053|2083|2087|2096|8443)$' || { echo "端口不支持 Cloudflare HTTPS！"; exit 1; }

# 2. 按需安装基础依赖
echo "正在检查系统依赖..."
install_deps() {
    if command -v apt-get >/dev/null 2>&1; then 
        apt-get update -qq && apt-get install -y -qq "$@"
    elif command -v apk >/dev/null 2>&1; then 
        apk update -q && apk add -q "$@"
    elif command -v yum >/dev/null 2>&1; then 
        yum install -y -q "$@"
    fi
}

DEPS=""
for cmd in curl wget openssl; do
    command -v $cmd >/dev/null 2>&1 || DEPS="$DEPS $cmd"
done
[ "$C" = "1" ] && { command -v socat >/dev/null 2>&1 || DEPS="$DEPS socat"; }
[ -n "$DEPS" ] && install_deps $DEPS

# 3. 环境清理与安装 Xray
CMD_RESTART="systemctl restart xray"
CMD_STOP="systemctl stop xray"
if ! command -v systemctl >/dev/null 2>&1 && command -v rc-service >/dev/null 2>&1; then
    CMD_RESTART="rc-service xray restart"
    CMD_STOP="rc-service xray stop"
fi

$CMD_STOP >/dev/null 2>&1 || true
mkdir -p /etc/ssl/xray
mkdir -p /usr/local/etc/xray

if ! command -v xray >/dev/null 2>&1; then
    echo "正在安装 Xray..."
    bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1 || { echo "Xray 安装失败"; exit 1; }
fi

# 生成随机路径和UUID
RP_RAW=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 12)
RP="/$RP_RAW"
ID=$(command -v uuidgen >/dev/null 2>&1 && uuidgen || cat /proc/sys/kernel/random/uuid)

# OpenRC 适配 (Alpine Linux)
if ! command -v systemctl >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
    printf "#!/sbin/openrc-run\ncommand=\"/usr/local/bin/xray\"\ncommand_args=\"run -config /usr/local/etc/xray/config.json\"\ncommand_background=true\npidfile=\"/run/xray.pid\"\n" > /etc/init.d/xray
    chmod +x /etc/init.d/xray
    rc-update add xray default >/dev/null 2>&1
fi

# 4. 证书处理
echo "正在配置证书..."
if [ "$C" = "1" ]; then
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        curl -sL https://get.acme.sh | sh -s email=$M >/dev/null 2>&1
    fi

    # 针对新版限定权限 Token 的环境变量
    # acme.sh 对于新版 API Token 使用 CF_Token 变量
    export CF_Token="$T"
    export CF_Email="$M"
    
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$FD" --keylength ec-256 || { echo "证书申请失败！请检查 Token 权限（需 DNS:Edit）和域名。"; exit 1; }
    
    ~/.acme.sh/acme.sh --install-cert -d "$FD" --ecc \
        --fullchain-file /etc/ssl/xray/cert.pem \
        --key-file /etc/ssl/xray/key.pem >/dev/null 2>&1
elif [ "$C" = "2" ]; then
    cp "$C_P" /etc/ssl/xray/cert.pem
    cp "$K_P" /etc/ssl/xray/key.pem
else
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/ssl/xray/key.pem -out /etc/ssl/xray/cert.pem \
        -subj "/CN=$FD" >/dev/null 2>&1
fi

# 修复安全权限
chmod 755 /etc/ssl/xray
chmod 644 /etc/ssl/xray/cert.pem
chmod 600 /etc/ssl/xray/key.pem

# 5. 写入配置并启动
echo "正在写入配置..."
cat > /usr/local/etc/xray/config.json <<EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$ID"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "xhttp",
      "xhttpSettings": { "path": "$RP" },
      "security": "tls",
      "tlsSettings": {
        "alpn": ["h2", "http/1.1"],
        "certificates": [{
          "certificateFile": "/etc/ssl/xray/cert.pem",
          "keyFile": "/etc/ssl/xray/key.pem"
        }]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 防火墙放行
if command -v ufw >/dev/null 2>&1; then
    ufw allow $PORT/tcp >/dev/null 2>&1
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=$PORT/tcp >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
fi

# 重启服务
$CMD_RESTART
command -v systemctl >/dev/null 2>&1 && systemctl enable xray >/dev/null 2>&1

# 6. 输出节点链接
INS=""
[ "$C" = "3" ] && INS="&allowInsecure=1"
LINK="vless://${ID}@${CDN}:${PORT}?security=tls&encryption=none&type=xhttp&sni=${FD}${INS}&path=%2F${RP_RAW}&alpn=h2,http/1.1#${FD}"

echo -e "\n部署成功！"
echo -e "----------------------------------------------------------------"
echo -e "主域名 (SNI): ${FD}"
echo -e "UUID: ${ID}"
echo -e "路径: ${RP}"
echo -e "----------------------------------------------------------------"
echo -e "VLESS 链接 (请确保客户端支持 xhttp 协议):"
echo -e "\033[36m${LINK}\033[0m"
echo -e "----------------------------------------------------------------\n"

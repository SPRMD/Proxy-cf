#!/bin/bash
# Debian 13: VLESS+TLS+XHTTP+CF SaaS (极简极速版)

[ "$(id -u)" != "0" ] && echo "请使用 root 运行: sudo su -" && exit 1

# 1. 收集信息
read -p "主域名 (如 domain.com): " D
read -p "域名前缀 (默认 sub): " P; P=${P:-sub}; FD="$P.$D"
read -p "CF 注册邮箱: " M
read -p "CF API Token (需要 Zone-DNS-Edit 权限): " T
read -p "优选域名/IP (默认 saas.sin.fan): " CDN; CDN=${CDN:-saas.sin.fan}

[ -z "$D" ] || [ -z "$M" ] || [ -z "$T" ] && echo "参数缺失，退出。" && exit 1
echo -e "\n开始自动部署业务域名: $FD ..."
echo -e "使用的优选地址为: $CDN\n"

# 2. 环境清理与依赖
systemctl stop xray 2>/dev/null
rm -rf /usr/local/etc/xray /usr/local/bin/xray /etc/ssl/xray
apt update -y && apt install curl wget socat cron -y
command -v ufw >/dev/null && ufw allow 443/tcp >/dev/null 2>&1
command -v iptables >/dev/null && iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null

# 3. 申请证书 (仅申请，暂不执行重启 Xray 的安装命令)
curl https://get.acme.sh | sh -s email=$M
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
export CF_Token="$T"
~/.acme.sh/acme.sh --issue --dns dns_cf -d "$FD" --keylength ec-256 || { echo "证书申请失败！"; exit 1; }

# 4. 安装 Xray 与配置写入
RP="/$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 12)"
ID=$(cat /proc/sys/kernel/random/uuid)
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1

mkdir -p /etc/ssl/xray
cat > /usr/local/etc/xray/config.json <<JSON_EOF
{
  "inbounds": [{
    "port": 443, "protocol": "vless",
    "settings": { "clients": [{"id": "$ID"}], "decryption": "none" },
    "streamSettings": {
      "network": "xhttp", "xhttpSettings": { "path": "$RP" },
      "security": "tls", "tlsSettings": {
        "alpn": ["h2", "http/1.1"],
        "certificates": [{ "certificateFile": "/etc/ssl/xray/cert.pem", "keyFile": "/etc/ssl/xray/key.pem" }]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
JSON_EOF

# 5. 安装证书并启动服务
~/.acme.sh/acme.sh --install-cert -d "$FD" --ecc \
    --fullchain-file /etc/ssl/xray/cert.pem \
    --key-file /etc/ssl/xray/key.pem \
    --reloadcmd "chmod 644 /etc/ssl/xray/*.pem && systemctl restart xray"

# 确保初始权限正确并设置开机自启
chmod 755 /etc/ssl/xray && chmod 644 /etc/ssl/xray/*.pem
systemctl restart xray && systemctl enable xray

# 6. 输出链接 (对 path 中的 / 进行 URL 编码处理)
ENCODED_RP="%2F${RP:1}"
LINK="vless://${ID}@${CDN}:443?security=tls&encryption=none&type=xhttp&sni=${FD}&path=${ENCODED_RP}&alpn=h2,http/1.1#${P}-SaaS"

echo -e "\n\033[32m部署成功！\033[0m"
echo -e "请确保 CF 后台 $FD 已开启橙色小云朵，且 SSL/TLS 设置为 Full (Strict)。\n"

if [ "$CDN" == "saas.sin.fan" ]; then
    echo -e "\033[33m注意：当前使用了公共 SaaS 域名作为客户端连接地址。\n建议后续在客户端中将其修改为你自己的优选 IP 或 CNAME 域名以保证稳定性。\033[0m\n"
fi

echo -e "\033[33m一键导入链接：\033[0m"
echo -e "\033[36m$LINK\033[0m\n"

# Proxy-cf: 极简极速 VLESS + XHTTP + CF SaaS 一键部署

这是一个适用于 Debian/Ubuntu 系统的极简一键部署脚本，采用最新的 **XHTTP** 传输协议结合 **VLESS**，并搭配 **Cloudflare SaaS** 实现极速、高匿的代理节点搭建。
本项目使用 Gemini 辅助完成。
## ✨ 脚本特性

* **前沿协议**：采用最新的 XHTTP 传输协议，多路复用性能更佳，伪装性更强。
* **极致简化**：一键执行，自动完成环境清理、依赖安装、证书申请及 Xray Core 配置。
* **自动化证书**：内置原生 `acme.sh` 脚本，通过 Cloudflare API 自动申请并续签泛域名/单域名证书。
* **CDN 优选友好**：支持自定义优选 IP 或 CNAME 域名（默认提供公共 SaaS 回退域名），彻底解决硬编码断联风险。
* **URL 编码兼容**：自动对 XHTTP 的 Path 参数进行标准的 URL 编码，完美兼容各类主流客户端。

---

## 📋 准备工作 (非常重要)

在运行脚本之前，请务必确保你已完成以下准备工作：

1.  **一台纯净的 VPS**：推荐使用 Debian 11/12/13 或 Ubuntu 20.04+ 系统，**必须使用 root 用户执行**。
2.  **一个托管在 Cloudflare 的域名**：
    * 在 DNS 记录中，将你的目标子域名（例如 `sub.domain.com`）解析到该 VPS 的公网 IP。
    * **必须开启** 橙色小云朵（Proxy status: Proxied）。
3.  **获取 Cloudflare API Token**：
    * 登录 CF 后台 -> 我的个人资料 -> API 令牌 -> 创建令牌。
    * 选择 **编辑区域 DNS (Edit zone DNS)** 模板。
    * 权限包含 `Zone - DNS - Edit` 即可。
4.  **配置 Cloudflare SSL/TLS 模式**：
    * 进入对应域名的 SSL/TLS 设置。
    * **必须将加密模式设置为 完全 (严格) / Full (Strict)**。
    

---

## 🚀 一键安装

SSH 登录到你的 VPS（使用 root 用户），直接复制并运行以下命令：

```bash
wget -O start.sh https://raw.githubusercontent.com/SPRMD/Proxy-cf/main/start.sh && bash start.sh

# 安全策略

## 支持范围

安全修复只针对 `main` 分支的最新版本。由于目标系统已停止获得常规安全更新，
本项目不能使旧版 iOS 本身变得安全。

## 报告问题

请通过 GitHub 仓库的 **Security → Report a vulnerability** 私下报告漏洞。若仓库
尚未启用 Private vulnerability reporting，请联系维护者，但不要在公开 Issue 中
发布可利用细节、真实 IP、账户、密码、私钥、Cookie 或日志中的敏感信息。

报告中建议包含受影响版本、复现步骤、影响、建议修复方式和最小化测试材料。

## 部署边界

- iPad、SSH 和 NAS 管理页面仅应位于受信任或隔离的局域网。
- `nas-manager` 使用 HTTP Basic Auth，本身不提供 TLS；跨不可信网络访问时必须
  放在可信反向代理之后并启用 HTTPS。
- 使用 NAS 专用只读账户和独立 SSH 密钥，修改越狱环境的默认 root 密码。
- 充电与显示守护进程以 root 运行。修改命令解析或远程控制接口时请重点审查命令
  注入、权限扩大和未经授权的状态更改。

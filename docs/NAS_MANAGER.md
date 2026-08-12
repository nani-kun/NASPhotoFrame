# NAS 管理服务

`nas-manager` 是一个可选的局域网 Web 页面，通过 SSH 控制已安装 NAS Photo
Frame 的 iPad。它可以查看状态、修改相框设置和显示/充电策略，以及执行息屏、
唤醒和应用重启。

## 安全边界

服务使用 HTTP Basic Auth，但不内置 TLS。请只在受信任局域网运行；如需跨网络
访问，必须通过带 HTTPS 和访问控制的反向代理。不要把容器端口或 iPad SSH 暴露
到公网。

## 配置

```sh
cd nas-manager
cp .env.example .env
```

编辑 `.env`：

```dotenv
PORT=8787
IPAD_HOST=192.168.1.100
IPAD_USER=root
ADMIN_USER=admin
ADMIN_PASSWORD=replace-with-a-long-random-password
```

`.env` 和 `data/` 已被忽略，不会进入 Git。启动服务：

```sh
docker compose up -d --build
docker compose logs -f
```

## 首次 SSH 授权

容器首次启动时会在 `nas-manager/data/ssh/` 生成独立 RSA 密钥。打开管理页面并登录，
页面会显示公钥。把它追加到 iPad root 用户的 `authorized_keys`，然后重新加载页面。

请仅复制 `.pub` 公钥内容。不要把 `id_rsa` 私钥复制到项目目录、聊天记录或 Git。

## 更新

```sh
git pull --ff-only
docker compose up -d --build
```

应用 `.deb` 仍应通过构建机或你自己的受控发布流程安装。仓库不包含绑定个人 NAS
目录、用户名、IP 或固定包版本的部署脚本。

## 数据目录

`data/` 中包含 SSH 私钥、`known_hosts` 和由页面更新后的管理员密码文件。请做好
仅管理员可读的备份与权限控制。删除此目录会丢失 iPad SSH 授权对应的私钥，并在
下次启动时生成新密钥。

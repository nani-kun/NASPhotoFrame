# NAS Photo Frame

把一台越狱的旧 iPad 变成可长期运行的 NAS 电子相框。

NAS Photo Frame 是面向 iPad 4 / iOS 8 的全屏照片播放器。它通过内嵌的
`libsmb2` 直接读取 NAS 上的 SMB2/SMB3 图片，支持离线缓存、照片索引、
低内存解码、定时息屏/唤醒和充电保护，并附带一个可选的局域网管理页面。

> 这是面向越狱旧设备的实验性项目，会使用 root 守护进程和 iOS 私有接口。
> 请只在你拥有并能恢复的设备上使用，不要把旧 iOS 或管理页面暴露到公网。

## 功能

- SMB2/SMB3 + NTLMSSP 访问 NAS，不要求开启 SMB1
- JPG、JPEG、PNG、GIF、BMP、TIFF 递归扫描与 SQLite 本地索引
- 顺序/随机播放、交叉淡入淡出、平移与可选 Ken Burns 动效
- EXIF/IPTC 日期与 GPS 地点显示，支持 GeoNames 离线城市回退
- 原图磁盘缓存、LRU 清理、断网熔断与离线继续播放
- ImageIO 后台降采样，适配仅 1 GB 内存的 iPad 4
- Keychain 保存 SMB 密码，普通配置存入 `NSUserDefaults`
- 可选充电守护进程，以滞回阈值降低长期插电带来的电池压力
- 可选定时锁屏、唤醒、解锁和自动打开相框
- 可选 Docker 局域网管理页面

## 运行环境

- 越狱 iPad，推荐 iPad 4 + iOS 8.4.1
- macOS 构建机
- Theos
- 原始 iPhoneOS 8.4 SDK（来自 Apple 官方 Xcode 6.4）
- 支持 SMB2/SMB3 的 NAS

本仓库不包含 Theos、Apple SDK、Xcode 镜像、构建产物或签名材料。Apple SDK
受其许可条款约束，请自行从 Apple Developer Downloads 获取，不要上传到本仓库。

## 获取与构建

```sh
git clone https://github.com/<your-account>/NASPhotoFrame.git
cd NASPhotoFrame
export THEOS=/path/to/theos
make clean package
```

工程固定为 `armv7`、iPhoneOS 8.4 SDK、最低 iOS 8.0。完整的环境准备、SDK
放置方式、安装和故障排查见 [构建指南](docs/BUILDING.md)。

## 使用

1. 在 NAS 上创建权限仅覆盖照片目录的专用只读账户。
2. 启用 SMB2 或 SMB3；不要为了本项目启用 SMB1。
3. 安装生成的 `.deb`，从桌面打开“NAS 相框”。
4. 填写 NAS 地址、共享名、共享内相对目录、用户名和密码。
5. 先执行连接测试，再保存配置并等待首次索引完成。

NAS 建议填写固定局域网 IPv4 地址。共享名只填写名称（如 `Photos`），不要填写
`smb://`；目录填写共享内的相对路径（如 `Family/Album`）。

## 工程结构

```text
Sources/          iPad 应用源码
ChargeLimiter/    充电保护守护进程
DisplayScheduler/ 息屏、唤醒和亮度调度守护进程
RemoteControl/    局域网管理服务调用的命令行桥接程序
Resources/        图标、Info.plist 与 GeoNames 离线数据库
layout/           Debian 包安装/卸载脚本与 launchd 配置
nas-manager/      可选的 Docker 局域网管理页面
scripts/          数据生成辅助脚本
ThirdParty/       随源码分发的第三方组件及其许可证
docs/             架构、构建、管理服务和发布文档
```

更详细的线程、缓存和故障策略见 [架构说明](docs/ARCHITECTURE.md)。

## NAS 管理页面（可选）

管理页面通过 SSH 调用设备上的 `PFDisplayScheduler`、`PFChargeLimiter` 和
`PFRemoteControl`。它使用 HTTP Basic Auth，默认没有 TLS，因此只适合受信任的
局域网。配置和首次授权步骤见 [NAS 管理服务指南](docs/NAS_MANAGER.md)。

## 安全提示

- 旧版 iOS、设备 SSH 和管理页面都不应暴露到公网。
- 建议把 iPad 放入隔离的家庭 LAN/VLAN，只允许访问 NAS 和管理主机。
- 为照片共享创建专用只读账户，不要复用 NAS 管理员账户。
- 使用 SSH 密钥，修改默认 root 密码，并限制可访问设备的来源地址。
- 发现安全问题时请按 [安全策略](SECURITY.md) 私下报告，不要公开凭据或漏洞细节。

## 参与贡献

欢迎提交问题和 Pull Request。开始前请阅读 [贡献指南](CONTRIBUTING.md)。发布者可
按照 [发布清单](docs/RELEASING.md) 检查版本、许可证、敏感信息和构建产物。

## 许可证

项目自有代码采用 [MIT License](LICENSE)。`ThirdParty/libsmb2` 采用 LGPL-2.1，
GeoNames 派生数据采用 CC BY 4.0；具体归属和本地修改见
[第三方声明](THIRD_PARTY_NOTICES.md)。各第三方组件仍受其各自许可证约束。

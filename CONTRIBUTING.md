# 贡献指南

感谢你愿意改进 NAS Photo Frame。

## 开始之前

1. 搜索现有 Issue，避免重复工作。
2. 较大的功能或架构变化请先发 Issue 讨论。
3. 不要提交 Apple SDK、Xcode 镜像、`.deb`、设备日志、照片、密码、私钥或真实 `.env`。
4. 第三方代码的改动必须说明上游版本、修改原因和许可证影响。

## 本地开发

按照 `docs/BUILDING.md` 准备 Theos 和 iPhoneOS 8.4 SDK。提交前至少运行：

```sh
python3 -m py_compile nas-manager/server.py
sh -n nas-manager/entrypoint.sh layout/DEBIAN/postinst layout/DEBIAN/prerm
git diff --check
```

如果具备完整旧版 SDK 环境，还应运行：

```sh
make clean package
```

涉及设备行为的变更，请在 Pull Request 中写明测试的 iPad 型号、iOS 版本、越狱
环境和恢复方案。充电、唤醒、锁屏等 root 组件必须在可恢复设备上测试。

## 提交与 Pull Request

- 每个提交只处理一个清晰主题，使用祈使语气描述变更。
- 保持 iOS 8 / Objective-C 运行时兼容，不要无意引入新系统 API。
- UI 更新必须考虑 iPad 4 的 1 GB 内存和 `armv7` 性能限制。
- PR 需说明问题、解决方式、验证方法、风险以及必要的回滚步骤。
- 若更新版本，同时修改 `control`、`Resources/Info.plist` 和发布说明。

## 代码风格

- 沿用现有 Objective-C 风格和 ARC 设置。
- UIKit 更新只在主线程执行；网络、SQLite、图片下载和解码放在后台队列。
- 文件写入优先使用临时文件加原子替换，避免断电留下损坏数据。
- 错误信息应能帮助旧设备用户定位网络、认证或存储问题。

# GitHub 发布清单

## 首次公开前

- 确认 `LICENSE` 中姓名与许可证选择符合你的意愿。
- 确认仓库可见性、默认分支和 GitHub Security 设置。
- 在 GitHub 启用 Private vulnerability reporting。
- 确认未提交 `.env`、私钥、公钥、真实内网地址、设备日志或个人照片。
- 确认没有 Apple SDK、Xcode 镜像、Theos 工具链和 `.deb` 被 Git 跟踪。
- 核对 `THIRD_PARTY_NOTICES.md` 与第三方许可证文件。

建议在推送前运行：

```sh
git status --short
git ls-files | grep -E '(\.env$|\.dmg$|\.xip$|\.deb$|\.p12$|\.mobileprovision$|id_rsa)'
git grep -n -E '(BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|ADMIN_PASSWORD=.+)'
```

后两条命令没有输出才符合预期；`.env.example` 中的占位符除外。

## 创建 GitHub 仓库

在 GitHub 新建一个空仓库，不要再次生成 README、`.gitignore` 或 LICENSE。然后：

```sh
git remote add origin git@github.com:<your-account>/NASPhotoFrame.git
git push -u origin main
```

也可以使用 GitHub CLI：

```sh
gh repo create NASPhotoFrame --public --source=. --remote=origin --push
```

## 版本发布

1. 更新 `control` 中的 `Version`。
2. 更新 `Resources/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`。
3. 运行静态检查和 `make clean package`。
4. 在测试设备完成安装、SMB 连接、缓存、息屏/唤醒和充电策略验证。
5. 提交版本变更，创建带注释标签并推送：

```sh
git tag -a v1.2.5 -m 'NAS Photo Frame 1.2.5'
git push origin main v1.2.5
```

6. 在 GitHub Release 中记录功能、修复、兼容性、升级和回滚方式。

是否上传 `.deb` 由维护者决定。若发布二进制包，必须同时保证对应源码、构建说明、
libsmb2 LGPL 许可证和本地修改可从同一发布版本获取；不要把 Apple SDK 打入附件。

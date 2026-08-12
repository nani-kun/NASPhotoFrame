# 构建与安装

## 1. 准备 Theos

按 Theos 官方说明安装所需依赖并克隆仓库，例如：

```sh
git clone --recursive https://github.com/theos/theos.git /opt/theos
export THEOS=/opt/theos
```

本项目已在 Theos 提交 `5280bd038207e14f8bd76f5417aa2fe641c03228` 上验证。
较新的 Theos 可能同样可用，但应重新验证旧 SDK、`armv7` 链接和打包结果。

## 2. 准备 iPhoneOS 8.4 SDK

当前 Xcode 不再提供可链接的 32 位 iOS 8 系统库。请登录 Apple Developer
Downloads，自行获取 Xcode 6.4，并从中提取原始 `iPhoneOS8.4.sdk`。不要把 Xcode
镜像或 SDK 提交到 Git 仓库。

把 SDK 放到：

```text
$THEOS/sdks/iPhoneOS8.4.sdk
```

确认路径：

```sh
test -d "$THEOS/sdks/iPhoneOS8.4.sdk/System/Library/Frameworks"
```

## 3. 构建 Debian 包

```sh
export THEOS=/path/to/theos
make clean package
```

成功后，安装包位于 `packages/`。该目录已被 `.gitignore` 排除。

工程的关键构建目标为：

```make
ARCHS = armv7
TARGET = iphone:clang:8.4:8.0
```

## 4. 安装到设备

推荐先为设备配置 SSH 主机别名，不要把真实地址写入仓库：

```sshconfig
Host nas-photo-frame-ipad
    HostName 192.168.1.100
    User root
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
```

老设备可能只提供已被新版 OpenSSH 默认禁用的 `ssh-rsa` 主机密钥。以上兼容配置
应只对这一台隔离设备生效，不要全局降低 SSH 安全策略。

使用 Theos 安装：

```sh
export THEOS_DEVICE_IP=nas-photo-frame-ipad
export THEOS_DEVICE_PORT=22
make package install
```

也可以传输 `.deb` 后在设备上安装：

```sh
scp packages/com.wangxiaoxiang.nasphotoframe_*.deb nas-photo-frame-ipad:/tmp/
ssh nas-photo-frame-ipad 'dpkg -i /tmp/com.wangxiaoxiang.nasphotoframe_*.deb && uicache'
```

## 5. 验证

应用包与三个辅助程序应均为 `armv7`，最低系统版本应为 iOS 8.0。安装后检查：

```sh
/usr/libexec/PFChargeLimiter status
/usr/libexec/PFDisplayScheduler status
/usr/libexec/PFDisplayScheduler power-events
```

然后从桌面打开“NAS 相框”，执行 NAS 连接测试并完成首次索引。

## 常见问题

### 找不到 iPhoneOS8.4.sdk

检查 `$THEOS` 是否指向正确目录，SDK 文件夹名称是否精确为
`iPhoneOS8.4.sdk`。不要使用只有符号或不含 32 位库的现代 SDK 替代。

### Keychain 返回 `errSecMissingEntitlement (-34018)`

确认应用和 `PFRemoteControl` 都使用了 `NASPhotoFrame.entitlements`，且包内签名没有
被其他步骤移除。

### 新版 macOS 无法链接

`Makefile` 会在存在 `ld-classic` 时优先使用它。若仍失败，记录 Xcode 命令行工具、
Theos 提交和完整链接错误后再提交 Issue。

### 安装后设备不稳定

先卸载包。卸载脚本会尝试恢复正常充电。若曾手工卸载充电守护进程，还应执行：

```sh
/usr/libexec/PFChargeLimiter enable
```

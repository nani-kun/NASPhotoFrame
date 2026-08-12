# 第三方声明

## libsmb2

- 项目：https://github.com/sahlberg/libsmb2
- 上游提交：`0b2aa4310c7a0510c666fe7da0eebce0f7e93824`
- 许可证：GNU Lesser General Public License 2.1
- 源码目录：`ThirdParty/libsmb2`
- 许可证文件：`ThirdParty/libsmb2/LICENCE-LGPL-2.1.txt`

仓库内保留了用于构建应用的完整上游源码。`lib/aes_apple.c` 增加了一个 iOS 8
兼容定义，使旧版 CommonCrypto 头文件可以识别 AES 算法常量。修改详情见
`ThirdParty/libsmb2/UPSTREAM.md`。

## GeoNames

- 项目：https://www.geonames.org/
- 数据集：`cities15000` 与 `admin1CodesASCII`
- 许可证：Creative Commons Attribution 4.0 International
- 派生文件：`Resources/GeoNamesCities.sqlite3`
- 声明文件：`Resources/GeoNames-LICENSE.txt`

项目包含一个用于离线最近城市查询的紧凑派生数据库。数据按原样提供，不保证
准确性、及时性或完整性。

## Apple 平台组件

项目构建时会链接 Apple SDK 中的系统框架，也会在越狱设备上调用部分私有接口。
Apple SDK、Xcode 和系统框架不随本仓库分发，其使用受 Apple 相应许可条款约束。

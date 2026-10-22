# 地点回归测试

在 macOS 上运行，无需设备或 iOS SDK：

```sh
sh scripts/test_geocoder.sh
PF_TEST_LANGUAGE=en sh scripts/test_geocoder.sh
```

测试直接编译实际的 `PFOfflineGeocoder.m`，使用内存 SQLite 场景与项目内置城市库，覆盖：

- 相邻照片缓存串用、旧缓存失效、语言与解析方式隔离。
- 搜索框外更近的地名、日期变更线、南北极附近。
- 50 公里距离上限、空库、非法坐标和海上坐标回退。
- “附近”提示及真实上海坐标的回归案例。
- 150 组坐标与独立球面距离公式的全库穷举结果对照。

可通过第一个参数指定另一套源码目录：

```sh
sh scripts/test_geocoder.sh /absolute/path/to/Sources
```

离线库提供地名点，不含行政区边界。测试验证最近点和距离限制，不能验证一个坐标所属的行政区或上游地名数据的准确性。

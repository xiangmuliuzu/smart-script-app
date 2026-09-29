# smart-script-app

智能剧本创作平台 Flutter App。功能源码位于 `lib/`，资源由 `pubspec.yaml` 声明，普通测试与设备集成测试分别位于 `test/`、`integration_test/`。

## 依赖与启动

后端环境变量、数据库初始化及启动流程见 [后端 README](../smart-script-backend/README.md)。App 的接口约定见 [共享资源](../shared/README.md)。

```powershell
flutter pub get
flutter run --dart-define=BASE_URL=http://10.0.2.2:8080/api/v1
```

Android 模拟器访问宿主机使用 `10.0.2.2`；真机使用后端实际地址。构建 Android 时按 `rules.md` 使用 JDK 17。

## 校验

```powershell
flutter analyze
flutter test test/a5 test/a6 test/auth test/widget_test.dart
```

`test/live/` 要求运行中的后端及 `LIVE_SMS_CODE` 等联调环境变量；其设置要求见测试文件。`integration_test/` 在设备或模拟器上运行。

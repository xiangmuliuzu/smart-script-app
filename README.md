# smart-script-app

智能剧本创作平台 Flutter App。功能源码位于 `lib/`，资源由 `pubspec.yaml` 声明，普通测试与设备集成测试分别位于 `test/`、`integration_test/`。

## 依赖与启动

后端环境变量、数据库初始化及启动流程见 [后端 README](../smart-script-backend/README.md)。App 的接口约定见 [共享资源](../shared/README.md)。

```powershell
flutter pub get
flutter run
```

App 默认连接服务器统一入口 `https://www.eyhereal.site/api/v1`，模拟器和真机均无需在本机启动后端。构建 Android 时按 `rules.md` 使用 JDK 17。

## 构建测试安装包

直接构建即可使用服务器统一入口：

```powershell
flutter build apk --debug
```

测试安装包输出到 `build/app/outputs/flutter-apk/app-debug.apk`。切换接口地址后需重新运行或安装新构建的 APK。

## 本地后端联调

需要连接本机后端时，显式覆盖地址；`10.0.2.2` 只会访问 Android 模拟器所在电脑，真机需改用电脑的局域网 IP。

```powershell
flutter run --dart-define=BASE_URL=http://10.0.2.2:8080/api/v1
```

## 校验

```powershell
flutter analyze
flutter test test/a5 test/a6 test/auth test/widget_test.dart
```

`test/live/` 要求运行中的后端及 `LIVE_SMS_CODE` 等联调环境变量；其设置要求见测试文件。`integration_test/` 在设备或模拟器上运行。

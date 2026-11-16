# smart-script-app

智能剧本创作平台 Flutter App。功能源码位于 `lib/`，资源由 `pubspec.yaml` 声明，普通测试与设备集成测试分别位于 `test/`、`integration_test/`。

## 依赖与启动

后端环境变量、数据库初始化及启动流程见 [后端 README](../smart-script-backend/README.md)。App 接口与当前后端各业务模块保持一致。

```powershell
flutter pub get
flutter run
```

App 默认连接服务器统一入口 `https://www.eyhereal.site/api/v1`，模拟器和真机均无需在本机启动后端。构建 Android 时按 `rules.md` 使用 JDK 17。

## AI 创作与 AI 记录

「我的作品」右上角「新建」先选方式：**AI 创作** 进入 `/ai/create`（设定 → 大纲 → 章节三步），**自己编辑** 进入原来的新建作品表单。

- 设定：书名、灵感、题材、集数、导演(skill)、模型；展示剩余积分。
- 大纲：流式生成并实时列出已出现的分集；长按选中任意段落在菜单里选「修改这段」，填写意见后只重写这一段（流式原位替换，失败还原）；也可切「手动编辑」逐字改。
- 章节：确认大纲时创建草稿作品，逐章生成并逐章落库；可停止、重试、展开预览，完成后进入作品工作台。

章节正文的 prompt 带 `[AI创作]` 前缀落进 `sys_ai_write_record.input_prompt`，AI 记录页据此把「一次 AI 创作」的大纲与它生成的章节合并成一条「AI 创作」：展开可看设定、大纲和已生成章节，并可「继续这次创作」带回 AI 创作页；「记录管理」按整组勾选批量删除（后端 `DELETE /api/v1/content/ai/write-records`）。工作台等其他入口生成的正文没有标记，保持各自单条。

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

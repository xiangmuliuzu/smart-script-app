# 智能剧本创作平台 · App 项目目录说明书

> 适用工程：`app/`（Flutter 工程根）
> 对应团队仓库：根目录三目录 `pc/`（Vue 管理后台）、`app/`（本工程，Flutter）、`backend/`（Spring Boot 2.7.18 共享后端）中的 `app/`。
> 当前状态：**底部导航已完成、内容页全部占位**（对应排期"完成APP端框架搭建"），登录注册等业务由后续分任务补齐。
> 一句话定位：本说明书讲清楚"工程里每个目录/文件是干嘛的、谁该改哪里、怎么跑起来"。

---

## 1. 本工程在团队里的边界

- 本工程**只含 Flutter 前端**。后端是团队共享的 `backend/`（包名 `com.smartscript.platform`），不在本目录内，也不由 App 框架负责人维护。
- App 只调用 `backend/` 中各业务模块 `controller/app/` 暴露的 `/api/v1/*` 接口；`controller/admin/` 供 PC 后台调用，`service/` 两端共用。
- App **不直连数据库**。根目录《数据库接入.txt》的 MySQL 信息只服务于 `backend/`，且密码严禁提交入库。
- 响应契约与后端对齐：统一 `{code, message, data}`；`code=200` 成功；`code=401` 时 App 自动清登录态并跳回登录页；分页为 `{total, list}`。

---

## 2. 顶层目录（`app/` 下）

```
app/
├── lib/                  # ★ 全部框架与业务代码（见第 3 节）
├── test/                 # 测试：widget_test.dart 为冒烟测试（验证 ProviderScope 能起来）
├── android/  ios/        # 平台壳工程。android 已换自定义图标与桌面名"剧本创作"
├── web/  windows/  linux/  macos/   # 其它平台壳（当前主要用 android）
├── pubspec.yaml          # 依赖清单：riverpod / go_router / dio / shared_preferences
├── pubspec.lock          # 依赖锁定（入库）
├── analysis_options.yaml # Dart 静态分析规则
├── .gitignore            # 忽略 build/ .dart_tool/ 等产物
├── APP框架说明书.md       # 本文件
├── README.md             # Flutter 默认 README（可删或合并进本文件）
└── script_app.iml        # IDE 模块残留（可删）
```

不入库的产物目录：`build/`、`.dart_tool/`、`.idea/`。

Android 图标与名称：图标在 `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`（已换成深湖蓝主题图标）；桌面名在 `android/app/src/main/AndroidManifest.xml` 的 `android:label="剧本创作"`。

---

## 3. `lib/` 逐层说明（核心）

```
lib/
├── main.dart             # 入口：初始化 SharedPreferences 并 override 进 ProviderScope
├── app.dart              # 根组件：MaterialApp.router + 全局主题
│
├── core/                 # 【框架层·公共地基，改动需对齐】
│   ├── config/app_config.dart        # 后端地址(默认 http://10.0.2.2:3000/api/v1)、超时、日志开关
│   ├── constants/
│   │   ├── api_endpoints.dart        # 接口路径唯一出处（2.1~2.10 全登记），页面禁止手写 URL
│   │   └── app_constants.dart        # 存储 key、成功码 200、分页默认值
│   ├── network/
│   │   ├── api_client.dart           # 网络唯一出口：get/post/put/delete/upload，自动解包与抛错
│   │   ├── api_response.dart         # 统一响应 {code,message,data}
│   │   ├── api_exception.dart        # 统一异常 ApiException
│   │   ├── session_events.dart       # 401 会话失效信号总线
│   │   └── interceptors/auth_interceptor.dart  # 自动带 Bearer token + 日志拦截器
│   ├── providers/
│   │   ├── app_providers.dart        # 依赖注入：dio/apiClient/tokenStorage 等
│   │   └── auth_providers.dart       # 登录会话 AuthController（含 DEMO_SESSION 演示开关）
│   ├── router/
│   │   ├── route_paths.dart          # 路由 path/name 登记表（home 指向真实路由 /bookstore）
│   │   └── app_router.dart           # 路由表 + 登录重定向 + 底部五格 StatefulShellRoute
│   ├── storage/token_storage.dart    # token/用户缓存持久化（重启恢复会话）
│   └── theme/
│       ├── app_colors.dart           # 颜色令牌（深湖蓝 #254E90 等，取自 UI 原型）
│       └── app_theme.dart            # 全局 ThemeData
│
├── models/               # 跨模块基础模型
│   ├── user.dart                     # User / UserType(user,creator,client,admin)
│   └── paged_result.dart             # PagedResult {total,list}
│
├── shared/widgets/       # 通用组件
│   ├── common_views.dart             # LoadingView / EmptyView / ErrorView 三态
│   └── placeholder_page.dart         # 占位页（未实现模块用）
│
└── features/             # 【业务层·各负责人只改自己的子目录】
    ├── splash/splash_page.dart       # 启动页（会话恢复中）
    ├── auth/pages/login_page.dart    # 登录参考实现（真实调 /auth/login）；登录按钮下含“测试进入”免登录入口，直达书城
    ├── auth/pages/register_page.dart # 注册占位（待分任务）
    ├── home/home_shell.dart          # ★ 底部五格导航容器（书城/漫剧/＋/分类/我的）
    ├── bookstore/bookstore_page.dart # 占位
    ├── comic/comic_page.dart         # 占位
    ├── create/create_page.dart       # 占位（中间＋）
    ├── category/category_page.dart   # 占位
    └── profile/profile_page.dart     # 示例页（读登录态 + 退出登录），非真实"我的"
```

---

## 4. 当前完成度（对照排期）

已完成（"APP端框架搭建"范围内）：底部五格导航（可切换、各 tab 保留导航栈、中间圆形凸起＋）；登录参考页跑通登录→存 token→进导航；401 自动登出；会话重启恢复；统一网络/异常/分页/主题/存储地基；自定义图标与桌面名；`flutter analyze` 无问题、`flutter test` 通过。

占位未做（后续分任务）：书城/漫剧/创作/分类四个内容页（纯占位）；"我的"为示例页而非真实业务页；注册/验证码登录/找回密码；创作者与甲方角色分流。

---

## 5. 运行与预览

1. 开启 Windows 开发人员模式（插件构建需要 symlink）：`start ms-settings:developers`。
2. 拉依赖：`flutter pub get`。
3. 两种启动方式：
   - 正常流程（进登录页）：`flutter run`
   - **演示导航（免后端直接进底部导航）**：`flutter run --dart-define=DEMO_SESSION=true`
     该开关在 `auth_providers.dart`，仅调试用；不带参数时行为不变。给负责人看导航效果用带参数的方式。
4. 后端地址：模拟器必须用 `10.0.2.2`（已默认），真机/远程改局域网 IP 或 `--dart-define=BASE_URL=...`。
5. 校验：`flutter analyze`、`flutter test`。
6. 换图标/改桌面名后需**重新构建安装**才生效：`flutter build apk --debug` 后 `adb install -r`。

---

## 6. 目录使用约定（协作硬规矩）

- 新增页面三步：① 在 `core/router/route_paths.dart` 登记 path/name；② 在 `features/<模块>/` 建页面文件；③ 在 `core/router/app_router.dart` 注册 GoRoute。路由改动只发生在这两个文件、且为追加，合并冲突最小。
- 各人只改自己 `features/<模块>/` 子目录；`core/`、`models/`、`shared/` 属公共层，改动先与框架负责人对齐。
- 禁止：自己 new Dio、自己存 token、硬编码 URL（一律走 `ApiEndpoints`）、硬编码颜色（一律走 `AppColors`）。
- `RoutePath.home` 必须指向**真实注册过的路由**（现为 `/bookstore`），不要改回未注册的 `/`，否则登录后会报 `GoException: no routes for location: /`。
- 提交前本地 `flutter analyze` 必须 No issues。

---

## 7. 关键文件速查（想改什么→改哪个文件）

- 后端地址/超时 → `core/config/app_config.dart`
- 新增接口路径 → `core/constants/api_endpoints.dart`
- 改主题色/圆角 → `core/theme/app_colors.dart` / `app_theme.dart`
- 加/改底部 tab 或页面路由 → `core/router/route_paths.dart` + `app_router.dart`
- 登录态/演示开关 → `core/providers/auth_providers.dart`
- 发请求/上传 → 页面里 `ref.watch(apiClientProvider)`，见 `core/network/api_client.dart`
- 图标/桌面名 → `android/.../mipmap-*/ic_launcher.png`、`AndroidManifest.xml`

---

## 8. 常见问题（FAQ）

- **一点登录就"网络连接失败"**：后端未启动或地址不对；模拟器必须 `10.0.2.2`。只想看导航请用 `DEMO_SESSION=true`。
- **登录后白屏/报 no routes for location: /**：`RoutePath.home` 被改成了未注册路由，改回 `/bookstore`。
- **图标还是 Flutter 默认**：改图标后没重新构建安装；执行第 5 节第 6 条。
- **桌面找不到 App**：Pixel 系 launcher 新装 App 进应用抽屉（桌面上滑），长按可拖到首屏。
- **页面拿不到 ref**：改用 `ConsumerWidget` / `ConsumerStatefulWidget`。
- **`pub get`/`run` 报 symlink**：开 Windows 开发人员模式后重试。

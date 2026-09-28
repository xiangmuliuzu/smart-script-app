# smart-script-app

智能剧本创作平台 Flutter App。当前 `main` 已包含 A3/G3、A4/G4、A5 用户中心与 A6 统一身份的阶段交付。

## 权威文档

| 文档 | 路径 | 状态 |
| --- | --- | --- |
| 开发规格 | [`../shared/A用户与认证开发规格.md`](../shared/A用户与认证开发规格.md) | v1.7 |
| 评审标准 | [`../shared/A用户与认证评审验收标准.md`](../shared/A用户与认证评审验收标准.md) | v1.6 |
| A3 认证契约与验收 | [`../shared/A3-认证接口契约.md`](../shared/A3-认证接口契约.md)、[`../shared/A3-G3-评审验收记录.md`](../shared/A3-G3-评审验收记录.md) | G3 已关闭 |
| A4 管理契约与验收 | [`../shared/A4-管理接口契约.md`](../shared/A4-管理接口契约.md)、[`../shared/A4-G4-评审验收记录.md`](../shared/A4-G4-评审验收记录.md) | G4 已关闭 |
| A5 / A6 阶段方案和记录 | [`../shared/A5-App用户中心实施方案与接口契约.md`](../shared/A5-App用户中心实施方案与接口契约.md)、[`../shared/A5-G5-快速阶段交付与冒烟记录.md`](../shared/A5-G5-快速阶段交付与冒烟记录.md)、[`../shared/A6-G6G7-交付与校验记录.md`](../shared/A6-G6G7-交付与校验记录.md) | 快速阶段通过；后续加固见 [`../shared/A5-A7-后续加固清单.md`](../shared/A5-A7-后续加固清单.md) |
| A7 发布准备 | [`../shared/A7-G8-交付与发布准备记录.md`](../shared/A7-G8-交付与发布准备记录.md)、[`../shared/A7-最小部署说明.md`](../shared/A7-最小部署说明.md)、[`../shared/A7-PR-App.md`](../shared/A7-PR-App.md) | A7 快速阶段通过；release 由项目经理决定，尚未合并 |

共享区是跨仓语义的唯一来源。本仓不复制或自行修改 API 语义。上表的 `../shared/` 是本地 `D:\build` 工作区相对约定。

## 后端与数据库初始化

App 依赖的后端、数据库结构与菜单数据全部来自 `smart-script-backend`：

| 内容 | 位置 |
| --- | --- |
| 环境准备、环境变量、**数据库初始化命令**、启动命令 | [smart-script-backend/README.md](https://github.com/xiangmuliuzu/smart-script-backend/blob/main/README.md) |
| 初始化步骤清单（A2 → A1 → A4 → PC，每步校验 `SUMMARY=PASS`） | [scripts/db/init-steps.txt](https://github.com/xiangmuliuzu/smart-script-backend/blob/main/scripts/db/init-steps.txt) |
| 已有数据库的升级与回滚说明 | [sql/migrations/README.md](https://github.com/xiangmuliuzu/smart-script-backend/blob/main/sql/migrations/README.md) |

要点：初始化**只允许**写入不存在或完全为空的库，检测到已有表会安全拒绝；
已有数据的库走迁移路径，不要导入 `ry_20260320.sql`。数据库就绪后按后端 README
设置 `DB_URL` / `REDIS_*` / `TOKEN_SECRET` / `APP_*` 等环境变量再启动后端，然后
指向该后端地址运行本仓：

```bash
flutter run --dart-define=BASE_URL=http://10.0.2.2:8080/api/v1
```

（`BASE_URL` 默认值见 `lib/core/config/app_config.dart`；Android 模拟器访问宿主机用
`10.0.2.2`，真机或桌面端改用后端实际地址。）

## 当前基线与边界

- 当前基线（2026-09-23）：`main@541e05b`
- A5 `8344d15` 与 A6 `fd6e892` 均已合入 `main`
- 工具链：Flutter 3.19.6 / Dart 3.3.4
- A3/G3、A4/G4 已关闭；A5/A6 当前结论为快速阶段通过。
- A7 已在 `main@541e05b` 上完成静态分析、debug APK 构建与模拟器主流程冒烟（`flutter analyze` 退出码 0；`flutter test` 43 项通过；构建与冒烟证据见共享区 A7 记录）。
- 构建 App 时 Flutter 若取用 Android Studio 自带的高版本 JBR，Gradle 7.6.3 会失败；按 `rules.md` 固定 JDK 17：`flutter config --jdk-dir="<JDK17 路径>"`。
- A5–A7 后续测试与安全加固仍按共享区加固清单跟踪；快速阶段通过不等于发布门禁完成。
- Token 使用平台安全存储，`SharedPreferences` 不保存凭证。

## 校验命令

```powershell
cd D:\build\smart-script-app
flutter pub get
flutter analyze
flutter test
```

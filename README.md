# smart-script-app

智能剧本创作平台 Flutter App。当前进入 A3 App 认证迁移阶段。

## 权威文档

| 文档 | 路径 | 状态 |
| --- | --- | --- |
| 开发规格 | `D:\build\shared\A用户与认证开发规格.md` | v1.5 |
| 评审标准 | `D:\build\shared\A用户与认证评审验收标准.md` | v1.4 |
| A3 实施方案 | `D:\build\shared\A3-App认证迁移实施方案.md` | 允许开发，待 G3 |
| A3 API 契约 | `D:\build\shared\A3-认证接口契约.md` | `A3-AUTH-CONTRACT-v1` |
| A3 测试矩阵 | `D:\build\shared\A3-G3-测试矩阵.md` | AUTH/DB/APP 矩阵 |
| A3 验收记录 | `D:\build\shared\A3-G3-评审验收记录.md` | 不通过，待开发与评审 |

共享区是跨仓语义的唯一来源。本仓不复制或自行修改 API 语义。

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

## A3 基线与边界

- 基线：`main@96a497e4a9dce9ad6949cff22c5f7317f188ee11`
- 分支：`a3/app-auth-migration`
- 工具链：Flutter 3.19.6 / Dart 3.3.4
- 保留现有路由、主题、Dio 和 Riverpod 结构。
- Token 必须迁移到平台安全存储；`SharedPreferences` 不保存凭证。
- 删除免登录测试入口和 production 可达的演示会话。
- A3 通过 G3 前不得合入 `release`。

## 校验命令

```powershell
cd D:\build\smart-script-app
flutter pub get
flutter analyze
flutter test
```

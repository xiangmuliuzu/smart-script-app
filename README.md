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

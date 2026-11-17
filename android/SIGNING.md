# Android release 签名

应用内更新要求**所有版本同签名**，否则已安装用户无法覆盖升级（系统提示「应用未安装」）。
本文件说明 keystore 放在哪、换机器怎么接、丢了怎么办。

## 当前配置

- keystore：`release.keystore`（PKCS12，别名 `smartscript`，RSA 2048，有效期 10000 天，2026-11-17 生成）
- 构建读取：`key.properties`（`storeFile / storePassword / keyAlias / keyPassword`）
- 两者都被 `.gitignore` 忽略，**不会进仓库**
- 仓库外备份：`C:\Users\cimu\smartscript-signing\`（含 key.properties，明文密码，自行妥善保管）

证书指纹（核对用）：

```
SHA-1:   18:D6:BC:24:8C:9E:7A:AD:2E:11:5F:89:1C:18:BA:57:F6:E1:65:90
SHA-256: 97:97:51:98:49:E1:E9:4B:50:00:93:51:EA:A0:2E:D3:31:1E:3A:88:82:5B:E1:98:B0:91:A2:C0:89:8C:56:02
```

## 换一台机器打包

1. 把 keystore 与 key.properties 拷到新机器（**不要**通过 git）。
2. 打印的 `storeFile` 必须指向新机器上 keystore 的真实位置：绝对路径或相对 `android/` 的路径都行，
   正斜杠最稳，例如 `storeFile=C:/Users/xxx/smartscript-signing/release.keystore`。
3. 或者完全不拷 key.properties，用环境变量指定它的位置：

   ```bash
   SMARTSCRIPT_KEY_PROPERTIES=C:/Users/xxx/smartscript-signing/key.properties flutter build apk --release
   ```

## 保护机制

- `android/app/build.gradle` 里有任务图检查：**没有 key.properties 时 release 构建直接失败**，
  不会静默用一个 debug 签名的包去发版（debug / `flutter run` 不受影响）。
- 确实想本地试跑 release：`SMARTSCRIPT_ALLOW_DEBUG_SIGNING=1 flutter build apk --release`，
  这种包**不能发给用户**。
- `scripts/publish_apk.sh` 在发布前用 apksigner 打印证书 SHA-256，和上面的指纹对一下即可确认。

## 丢了会怎样

- 已安装用户：只能卸载重装（数据丢失），或者你换应用 ID 重新发一个 App。
- 找回率：几乎为零。keystore 与密码必须离线备份，至少两份，放在不同地方。
- 建议把 `release.keystore` + 密码存进密码管理器，并把 `smartscript-signing` 目录拷到 U 盘。

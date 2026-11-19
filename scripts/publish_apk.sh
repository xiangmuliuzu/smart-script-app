#!/usr/bin/env bash
# 应用内更新（不上架）发布脚本。
#
# 做法：
#   1) 打 release APK，build 号 = 第 2 个参数（必须比上一版大，App 靠它判断新旧）；
#   2) 上传到后端静态资源目录 uploadPath/app/，可经 https://域名/profile/app/<文件> 直接下载；
#   3) 打印需要写进管理端「参数设置」的 sys_config 值。
#
# 用法（在 smart-script-app 目录执行）：
#   scripts/publish_apk.sh 1.0.1 2
#
# 前提：android/key.properties + keystore 已配好（release 包必须用同一把钥匙签名，
# 否则已安装的旧版本拒绝覆盖安装）。
set -euo pipefail

VERSION_NAME="${1:?用法: scripts/publish_apk.sh <versionName> <buildNumber>}"
BUILD_NUMBER="${2:?用法: scripts/publish_apk.sh <versionName> <buildNumber>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UPLOAD_DIR="${UPLOAD_DIR:-$APP_DIR/../smart-script-backend/uploadPath/app}"
# 服务器地址：换成实际地址即可（App 会从这里下载 APK）
SERVER_ORIGIN="${SERVER_ORIGIN:-http://192.168.100.3:1100}"
FILE_NAME="script-app-${VERSION_NAME}-${BUILD_NUMBER}.apk"

cd "$APP_DIR"
flutter build apk --release --build-name "$VERSION_NAME" --build-number "$BUILD_NUMBER"

APK="build/app/outputs/flutter-apk/app-release.apk"

# 1) 签名自检：发布包必须用 keystore 签名（不是 debug 签名），否则已安装用户无法覆盖升级。
APKSIGNER=""
for candidate in $(ls -d "${ANDROID_HOME:-/nonexistent}"/build-tools/*/apksigner.bat                         "${ANDROID_HOME:-/nonexistent}"/build-tools/*/apksigner                         D:/java/android-sdk/build-tools/*/apksigner.bat                         D:/java/android-sdk/build-tools/*/apksigner 2>/dev/null | sort -r); do
  if [ -f "$candidate" ]; then APKSIGNER="$candidate"; break; fi
done
if [ -n "$APKSIGNER" ]; then
  CERT=$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | grep -i "certificate SHA-256 digest" | head -1 || true)
  echo "签名证书: ${CERT:-未取到（请人工确认）}"
else
  echo "未找到 apksigner（设置 ANDROID_HOME 可自动核对签名指纹）"
fi

mkdir -p "$UPLOAD_DIR"
cp "$APK" "$UPLOAD_DIR/$FILE_NAME"
SIZE=$(wc -c < "$UPLOAD_DIR/$FILE_NAME" | tr -d ' ')
SHA=$(sha256sum "$UPLOAD_DIR/$FILE_NAME" | cut -d' ' -f1)

# 2) 旧包清理：只保留最近 3 个，避免服务器磁盘被历史 APK 占满（已发布链接仍可下载时再手动留着）
ls -1t "$UPLOAD_DIR"/script-app-*.apk 2>/dev/null | tail -n +4 | while read -r old; do
  echo "清理旧包: $(basename "$old")"
  rm -f "$old"
done

cat <<EOF

已上传: $UPLOAD_DIR/$FILE_NAME ($SIZE 字节, sha256=$SHA)
下载地址: $SERVER_ORIGIN/profile/app/$FILE_NAME

在管理端「系统管理 → 参数设置」新增/修改（改完立即生效，不用重启）：
  app.version.android.versionName     = $VERSION_NAME
  app.version.android.versionCode     = $BUILD_NUMBER
  app.version.android.url             = $SERVER_ORIGIN/profile/app/$FILE_NAME
  app.version.android.size            = $SIZE
  app.version.android.notes           = 本次更新修复了若干问题
  # 可选：低于该 build 的手机不可跳过（强制更新），一般比 versionCode 小 1~2
  app.version.android.minVersionCode  = $BUILD_NUMBER
  # 可选：临时关闭更新提示
  app.version.android.enabled         = true
EOF

# 3) 服务器开着 MinIO 时必须同步到公开桶，否则 /profile/** 回源拿不到文件（404）：
#   mc cp "$UPLOAD_DIR/$FILE_NAME" smartscript/smartscript-profile/app/
echo
echo "提示：服务器若启用 MinIO（MINIO_ENABLED=true），请把上面的 APK 同步到公开桶："
echo "  mc cp '$UPLOAD_DIR/$FILE_NAME' smartscript/smartscript-profile/app/"

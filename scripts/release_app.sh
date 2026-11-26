#!/usr/bin/env bash
# 一键发版：检测代码变化 → build 号自增 → 打包 → 上传服务器 → 同步 MinIO
#          → 更新 sys_config 版本参数（含 Redis 缓存清理）→ 线上验证。
#
# 用法（在 smart-script-app 目录）：
#   bash scripts/release_app.sh                    # 有代码变化才发版
#   bash scripts/release_app.sh --force            # 忽略「无变化」检查
#   bash scripts/release_app.sh --dry-run          # 只打印步骤，不打包不上传
#   bash scripts/release_app.sh --notes "更新内容"  # 自定义更新说明
#
# 状态记录：.release-state（build 号 + 上次发布的 commit），已在 .gitignore。
# 依赖：flutter、ssh/scp（密钥已配好）、mysql 客户端、curl。
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

# ===== 可覆盖配置（需要换环境时用环境变量改）=====
# P06 内网部署（192.168.100.3）的 SSH 入口尚未提供，必须显式传入，避免误发到旧公网服务器：
#   SERVER_HOST=user@host bash scripts/release_app.sh
SERVER_HOST="${SERVER_HOST:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
# 下面三项按旧公网服务器的目录/属主写死，部署到 P06 时请用环境变量覆盖成实际值
SERVER_APK_DIR="${SERVER_APK_DIR:-/home/ma_jiajia/uploadPath/app}"
SERVER_APK_OWNER="${SERVER_APK_OWNER:-ma_jiajia:ma_jiajia}"
# 容器名同理：按旧服务器默认，P06 部署请按实际容器名覆盖
MINIO_CONTAINER="${MINIO_CONTAINER:-smart-script-minio}"
MINIO_BUCKET="${MINIO_BUCKET:-smartscript-profile}"
REDIS_CONTAINER="${REDIS_CONTAINER:-redis-container}"
SERVER_ORIGIN="${SERVER_ORIGIN:-http://192.168.100.3:1100}"
STATE_FILE="$APP_DIR/.release-state"
ENV_FILE="${ENV_FILE:-$APP_DIR/../smart-script-backend/.env.local}"
MYSQL_BIN="${MYSQL_BIN:-$(command -v mysql || echo /d/java/bin/mysql)}"

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new)

FORCE=0
DRY=0
NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --dry-run) DRY=1 ;;
    --notes) shift; NOTES="${1:-}" ;;
    *) echo "未知参数: $1"; exit 2 ;;
  esac
  shift
done

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
run() { if [ "$DRY" = "1" ]; then echo "[dry-run] $*"; else "$@"; fi; }

if [ "$DRY" = "0" ] && [ -z "$SERVER_HOST" ]; then
  echo "缺少 SERVER_HOST：请指定 P06 内网部署的 SSH 目标（例：SERVER_HOST=user@192.168.100.3 bash scripts/release_app.sh）" >&2
  exit 2
fi

# ===== 1. 检测代码变化 =====
say "1/7 检测代码变化"
HEAD_SHA="$(git rev-parse --short HEAD)"
# 只把真正影响 App 产物的路径算作「代码变化」：docs/、scripts/、.gitignore 等不影响安装包，
# 改它们不应触发重新发版。提交号仍覆盖 lib/ 与 android/ 的历史变更。
APP_CODE_PATHS=(lib android assets pubspec.yaml pubspec.lock)
DIRTY="$(git status --porcelain -- "${APP_CODE_PATHS[@]}" | wc -l | tr -d ' ')"
LAST_SHA=""
LAST_BUILD=""
if [ -f "$STATE_FILE" ]; then
  LAST_SHA="$(sed -n 's/^commit=//p' "$STATE_FILE")"
  LAST_BUILD="$(sed -n 's/^build=//p' "$STATE_FILE")"
fi
if [ -z "$LAST_BUILD" ]; then
  # 首次使用：以线上 versionCode 为基线，避免与已发布版本撞号
  LAST_BUILD="$(curl -s -m 10 "$SERVER_ORIGIN/api/v1/app/version" \
    | sed -n 's/.*"versionCode":\([0-9]*\).*/\1/p')"
  LAST_BUILD="${LAST_BUILD:-1}"
  echo "首次使用：以线上 versionCode=$LAST_BUILD 为基线"
fi

echo "当前 commit: $HEAD_SHA（未提交改动 $DIRTY 个文件）"
echo "上次发布:   ${LAST_SHA:-无}，build=$LAST_BUILD"

if [ "$FORCE" = "0" ] && [ "$HEAD_SHA" = "$LAST_SHA" ] && [ "$DIRTY" = "0" ]; then
  echo "代码与上次发布一致，无需发版（强制发版加 --force）"
  exit 0
fi
[ "$DIRTY" != "0" ] && echo "提醒：App 代码有 $DIRTY 个未提交改动，也会被打进包里"
git status --porcelain -- "${APP_CODE_PATHS[@]}" | sed 's/^/  /' | head -10

# ===== 2. build 号自增 =====
BUILD_NUMBER=$((LAST_BUILD + 1))
VERSION_NAME="${VERSION_NAME:-1.0.$BUILD_NUMBER}"
FILE_NAME="script-app-${VERSION_NAME}-${BUILD_NUMBER}.apk"
NOTES="${NOTES:-本次更新修复了若干问题}"
say "2/7 新版本 $VERSION_NAME (build $BUILD_NUMBER) → $FILE_NAME"

# ===== 3. 打包 =====
say "3/7 打包 release APK"
run flutter build apk --release --build-name "$VERSION_NAME" --build-number "$BUILD_NUMBER"
APK="build/app/outputs/flutter-apk/app-release.apk"
if [ "$DRY" = "0" ]; then
  APKSIGNER="$(ls -d "${ANDROID_HOME:-/nonexistent}"/build-tools/*/apksigner.bat \
                    D:/java/android-sdk/build-tools/*/apksigner.bat 2>/dev/null | sort -r | head -1 || true)"
  if [ -n "$APKSIGNER" ]; then
    "$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | grep -i 'SHA-256 digest' || true
  fi
  SIZE=$(wc -c < "$APK" | tr -d ' ')
  echo "APK 大小: $SIZE 字节"
fi

# ===== 4. 上传到服务器 =====
say "4/7 上传到服务器 $SERVER_HOST:$SERVER_APK_DIR"
run scp "${SSH_OPTS[@]}" "$APK" "$SERVER_HOST:/tmp/$FILE_NAME"
run ssh "${SSH_OPTS[@]}" "$SERVER_HOST" \
  "sudo cp '/tmp/$FILE_NAME' '$SERVER_APK_DIR/$FILE_NAME' && sudo chown $SERVER_APK_OWNER '$SERVER_APK_DIR/$FILE_NAME' && rm -f '/tmp/$FILE_NAME' && ls -l '$SERVER_APK_DIR/$FILE_NAME'"

# ===== 5. 同步 MinIO =====
say "5/7 同步 MinIO（$MINIO_BUCKET）"
if [ "$DRY" = "1" ]; then
  echo "[dry-run] ssh $SERVER_HOST <同步 $FILE_NAME 到 MinIO>"
else
  # 远端脚本用占位符生成，避免本地 shell 的嵌套引号问题
  REMOTE_SCRIPT="$(mktemp)"
  cat > "$REMOTE_SCRIPT" <<'REMOTE_EOF'
set -e
MINIO_CONTAINER="@MINIO_CONTAINER@"
MINIO_BUCKET="@MINIO_BUCKET@"
APK_DIR="@APK_DIR@"
FILE_NAME="@FILE_NAME@"
ENVS=$(sudo docker inspect "$MINIO_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}')
RU=$(printf '%s\n' "$ENVS" | sed -n 's/^MINIO_ROOT_USER=//p')
RP=$(printf '%s\n' "$ENVS" | sed -n 's/^MINIO_ROOT_PASSWORD=//p')
if [ -z "$RU" ] || [ -z "$RP" ]; then
  echo "MinIO root 凭据缺失，跳过同步" >&2
  exit 1
fi
sudo docker run --rm --network host --entrypoint /bin/sh \
  -v "$APK_DIR:/apk:ro" minio/mc:latest -c \
  "mc alias set adm http://127.0.0.1:9000 '$RU' '$RP' >/dev/null && mc cp /apk/$FILE_NAME adm/$MINIO_BUCKET/app/ >/dev/null && echo MINIO_OK"
REMOTE_EOF
  sed -i \
    -e "s|@MINIO_CONTAINER@|$MINIO_CONTAINER|g" \
    -e "s|@MINIO_BUCKET@|$MINIO_BUCKET|g" \
    -e "s|@APK_DIR@|$SERVER_APK_DIR|g" \
    -e "s|@FILE_NAME@|$FILE_NAME|g" \
    "$REMOTE_SCRIPT"
  ssh "${SSH_OPTS[@]}" "$SERVER_HOST" 'bash -s' < "$REMOTE_SCRIPT"
  rm -f "$REMOTE_SCRIPT"
fi

# ===== 6. 更新 sys_config + 清 Redis 缓存 =====
say "6/7 更新版本参数"
if [ "$DRY" = "1" ]; then
  echo "[dry-run] 更新 sys_config: versionCode=$BUILD_NUMBER, versionName=$VERSION_NAME,"
  echo "          url=$SERVER_ORIGIN/profile/app/$FILE_NAME, notes=$NOTES"
else
  if [ ! -f "$ENV_FILE" ]; then
    echo "缺少 $ENV_FILE（需要 DB_URL / DB_USERNAME / DB_PASSWORD）"; exit 1
  fi
  DB_URL_V="$(sed -n 's/^DB_URL=//p' "$ENV_FILE")"
  DB_USER_V="$(sed -n 's/^DB_USERNAME=//p' "$ENV_FILE")"
  DB_PASS_V="$(sed -n 's/^DB_PASSWORD=//p' "$ENV_FILE")"
  DB_HOST_V="$(printf '%s' "$DB_URL_V" | sed -E 's#jdbc:mysql://([^:/]+).*#\1#')"
  DB_NAME_V="$(printf '%s' "$DB_URL_V" | sed -E 's#.*/([^?]+)\?.*#\1#')"
  # 更新说明里的单引号需要转义成 SQL 的 ''
  NOTES_SQL="${NOTES//\'/\'\'}"
  SQL="UPDATE sys_config SET config_value='$BUILD_NUMBER' WHERE config_key='app.version.android.versionCode';
UPDATE sys_config SET config_value='$VERSION_NAME' WHERE config_key='app.version.android.versionName';
UPDATE sys_config SET config_value='$SERVER_ORIGIN/profile/app/$FILE_NAME' WHERE config_key='app.version.android.url';
UPDATE sys_config SET config_value='$SIZE' WHERE config_key='app.version.android.size';
UPDATE sys_config SET config_value='$NOTES_SQL' WHERE config_key='app.version.android.notes';"
  # 中文更新说明不能走 -e 参数：Windows 上 mysql.exe 会按系统代码页（GBK）解释命令行，
  # 把 UTF-8 的 notes 写成乱码。SQL 从标准输入喂进去，并显式声明 utf8mb4 连接字符集。
  printf '%s\n' "$SQL" | "$MYSQL_BIN" --default-character-set=utf8mb4 -h "$DB_HOST_V" -u "$DB_USER_V" -p"$DB_PASS_V" -D "$DB_NAME_V" 2>&1 \
    | grep -v 'Using a password' || true
  echo "sys_config 已更新"

  REMOTE_REDIS="$(mktemp)"
  cat > "$REMOTE_REDIS" <<'REDIS_EOF'
REDIS_CONTAINER="@REDIS_CONTAINER@"
RP=$(sudo docker inspect "$REDIS_CONTAINER" --format '{{json .Config.Cmd}}' | sed -n 's/.*"--requirepass","\([^"]*\)".*/\1/p')
if [ -z "$RP" ]; then echo "未取到 Redis 密码，请手动清理 sys_config:app.version*" >&2; exit 1; fi
KEYS=$(sudo docker exec "$REDIS_CONTAINER" redis-cli -a "$RP" --no-auth-warning --scan --pattern 'sys_config:app.version*')
if [ -z "$KEYS" ]; then echo "CACHE_EMPTY"; exit 0; fi
printf '%s\n' "$KEYS" | while read -r k; do
  sudo docker exec "$REDIS_CONTAINER" redis-cli -a "$RP" --no-auth-warning DEL "$k" >/dev/null
done
echo "CACHE_CLEARED"
REDIS_EOF
  sed -i -e "s|@REDIS_CONTAINER@|$REDIS_CONTAINER|g" "$REMOTE_REDIS"
  ssh "${SSH_OPTS[@]}" "$SERVER_HOST" 'bash -s' < "$REMOTE_REDIS"
  rm -f "$REMOTE_REDIS"

  printf 'commit=%s\nbuild=%s\nversion=%s\nfile=%s\n' \
    "$HEAD_SHA" "$BUILD_NUMBER" "$VERSION_NAME" "$FILE_NAME" > "$STATE_FILE"
fi

# ===== 7. 验证 =====
say "7/7 线上验证"
if [ "$DRY" = "1" ]; then
  echo "[dry-run] curl $SERVER_ORIGIN/api/v1/app/version"
else
  API_JSON="$(curl -s -m 15 "$SERVER_ORIGIN/api/v1/app/version")"
  echo "$API_JSON"
  case "$API_JSON" in
    *"\"versionCode\":$BUILD_NUMBER"*) echo "版本接口 OK" ;;
    *) echo "警告：接口未返回 build=$BUILD_NUMBER" ;;
  esac
  curl -s -m 120 -o /dev/null -w "APK 下载: http=%{http_code} size=%{size_download}\n" \
    "$SERVER_ORIGIN/profile/app/$FILE_NAME"
  echo "完成。已安装旧版本的用户下次打开 App 会收到更新提示。"
fi

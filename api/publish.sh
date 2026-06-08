#!/usr/bin/env bash
# NexusHub 新版本发布脚本（拆仓库版：hub_apk + apk_api）
#
# 用法：
#   export GITHUB_PAT="github_pat_xxx"
#   bash /workspace/nexushub-pages/api/publish.sh <version> <apk_path> [changelog line 1] [changelog line 2] ...
#
# 例子：
#   bash publish.sh 1.26.6.7.1200 /workspace/dist/NexusHub-1.26.6.7.1200-debug.apk \
#       "新功能 A" "修复 B" "优化 C"
#
# 它会做：
#   1. 算 SHA256 + size
#   2. 复制 APK 到 hub_apk/apks/
#   3. 更新 hub_apk/manifest.json（添加新版本 + 设为 latest）
#   4. git commit + push hub_apk
#   5. 同步 manifest.json 到 apk_api（baseUrl 指向 jsDelivr）
#   6. git commit + push apk_api
#   7. Vercel 检测到 apk_api 推送 → 30-60 秒后自动重新部署

set -e

# ─────── 校验 ───────
: "${GITHUB_PAT:?需要 export GITHUB_PAT=... （GitHub 私人令牌）}"
GITHUB_USER="${GITHUB_USER:-cgw666666}"
GITHUB_REPO="${GITHUB_REPO:-apk_api}"      # 网页代码仓库
APK_REPO="${APK_REPO:-hub_apk}"             # APK 存储仓库
BRANCH="${BRANCH:-main}"
SITE_URL="${SITE_URL:-https://cgw-lime.vercel.app}"
BASE_URL="https://cdn.jsdelivr.net/gh/${GITHUB_USER}/${APK_REPO}@${BRANCH}/apks"

# 本地两个仓库的路径
API_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APK_PROJECT_DIR="${APK_PROJECT_DIR:-/workspace/hub_apk}"

VERSION="${1:-}"
APK_PATH="${2:-}"
shift 2 2>/dev/null || true
CHANGELOG_LINES=("$@")

if [ -z "$VERSION" ] || [ -z "$APK_PATH" ]; then
    echo "用法: $0 <version> <apk_path> [changelog line 1] [changelog line 2] ..."
    echo ""
    echo "环境变量（默认值通常不用改）："
    echo "  GITHUB_PAT     GitHub 私人令牌（必填）"
    echo "  GITHUB_USER    默认 cgw666666"
    echo "  GITHUB_REPO    网页代码仓库，默认 apk_api"
    echo "  APK_REPO       APK 存储仓库，默认 hub_apk"
    echo "  BRANCH         默认 main"
    echo "  SITE_URL       默认 https://cgw-lime.vercel.app"
    echo "  APK_PROJECT_DIR  本地 hub_apk 仓库路径，默认 /workspace/hub_apk"
    exit 1
fi

if [ ! -f "$APK_PATH" ]; then
    echo "ERROR: APK 文件不存在: $APK_PATH"
    exit 1
fi

# 颜色
G="\033[32m"; Y="\033[33m"; R="\033[31m"; N="\033[0m"
log() { echo -e "${G}[$(date +%H:%M:%S)]${N} $1"; }
warn() { echo -e "${Y}[$(date +%H:%M:%S)]${N} $1"; }
err() { echo -e "${R}[$(date +%H:%M:%S)] ERROR:${N} $1"; }

APK_FILE=$(basename "$APK_PATH")
APK_SIZE=$(stat -c%s "$APK_PATH")
APK_SHA=$(sha256sum "$APK_PATH" | cut -d' ' -f1)
APK_DATE=$(date +%Y-%m-%d)

log "version:    $VERSION"
log "file:       $APK_FILE"
log "size:       $APK_SIZE bytes ($(echo "scale=1; $APK_SIZE/1024/1024" | bc) MB)"
log "sha256:     $APK_SHA"
log "date:       $APK_DATE"
log "changelog:  ${#CHANGELOG_LINES[@]} lines"

# ─────── 1. 复制 APK 到 hub_apk/apks/ ───────
log "[1/6] 复制 APK 到 $APK_PROJECT_DIR/apks/$APK_FILE..."
cp -f "$APK_PATH" "$APK_PROJECT_DIR/apks/$APK_FILE"

# ─────── 2. 更新 hub_apk 的 manifest.json ───────
log "[2/6] 更新 hub_apk/manifest.json..."
MANIFEST_FILE="$APK_PROJECT_DIR/manifest.json"

# 如果 manifest.json 不存在则初始化
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "{\"latest\":\"\",\"baseUrl\":\"$BASE_URL\",\"minAndroid\":\"7.0\",\"versions\":[]}" > "$MANIFEST_FILE"
fi

python3 << PYEOF
import json
mf_path = '$MANIFEST_FILE'
with open(mf_path) as f:
    m = json.load(f)

# 确保 baseUrl 是新的
m['baseUrl'] = '$BASE_URL'
m['latest'] = '$VERSION'

# 找现有版本
existing_idx = -1
for i, v in enumerate(m['versions']):
    if v['version'] == '$VERSION':
        existing_idx = i
        break

new_entry = {
    'version': '$VERSION',
    'file': '$APK_FILE',
    'size': $APK_SIZE,
    'sha256': '$APK_SHA',
    'date': '$APK_DATE',
    'changelog': [$(printf '"%s",' "${CHANGELOG_LINES[@]}" | sed 's/,$//' || echo '')]
}

if existing_idx >= 0:
    m['versions'][existing_idx] = new_entry
    print(f'  更新现有版本（位置 {existing_idx}）')
else:
    m['versions'].insert(0, new_entry)
    print(f'  添加新版本（位置 0）')

print(f'  当前共 {len(m["versions"])} 个版本，latest = {m["latest"]}')

with open(mf_path, 'w', encoding='utf-8') as f:
    json.dump(m, f, indent=2, ensure_ascii=False)
print('  manifest.json 已写入')
PYEOF

# ─────── 3. git commit + push hub_apk ───────
log "[3/6] git commit + push hub_apk..."
cd "$APK_PROJECT_DIR"
git add "apks/$APK_FILE" manifest.json 2>&1 | tail -2
git commit -m "release: v$VERSION

$(printf -- '- %s\n' "${CHANGELOG_LINES[@]}")" 2>&1 | tail -3

PUSH_URL="https://${GITHUB_USER}:${GITHUB_PAT}@github.com/${GITHUB_USER}/${APK_REPO}.git"
timeout 90 git -c credential.helper= push "$PUSH_URL" "$BRANCH" 2>&1 | tail -3
git remote set-url origin "https://github.com/${GITHUB_USER}/${APK_REPO}.git"

# ─────── 4. 同步 manifest.json 到 apk_api ───────
log "[4/6] 同步 manifest.json 到 apk_api..."
cp -f "$MANIFEST_FILE" "$API_PROJECT_DIR/manifest.json"

# ─────── 5. git commit + push apk_api ───────
log "[5/6] git commit + push apk_api..."
cd "$API_PROJECT_DIR"
git add manifest.json
# 只有有变化时才 commit
if git diff --cached --quiet; then
    warn "apk_api manifest.json 无变化，跳过 commit/push"
else
    git commit -m "manifest: bump to v$VERSION" 2>&1 | tail -3
    PUSH_URL_API="https://${GITHUB_USER}:${GITHUB_PAT}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
    timeout 90 git -c credential.helper= push "$PUSH_URL_API" "$BRANCH" 2>&1 | tail -3
    git remote set-url origin "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
fi

# ─────── 6. 触发 Vercel 重新部署（如果没 push 的话） ───────
log "[6/6] 触发 Vercel 重新部署（empty commit 强制 rebuild）..."
cd "$API_PROJECT_DIR"
git commit --allow-empty -m "trigger: redeploy for v$VERSION" 2>&1 | tail -2
PUSH_URL_API="https://${GITHUB_USER}:${GITHUB_PAT}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
timeout 90 git -c credential.helper= push "$PUSH_URL_API" "$BRANCH" 2>&1 | tail -3
git remote set-url origin "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

# ─────── 7. 总结 ───────
APK_URL="${BASE_URL}/${APK_FILE}"
log ""
log "==== 完成 ===="
log "  网页:    ${G}${SITE_URL}/${N}"
log "  APK:     ${G}${APK_URL}${N}"
log "  Vercel 会在 30-60 秒内自动重新部署"
log "  jsDelivr 会在 5-15 分钟内同步新 APK"
log ""
log "  提示：等 Vercel 重新部署完后，访问 ${SITE_URL}/ 应该看到 v$VERSION"
log "  提示：等 jsDelivr 同步完后，点下载按钮才能下到 ${APK_FILE}"

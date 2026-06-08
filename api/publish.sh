#!/usr/bin/env bash
# NexusHub 新版本发布脚本（用 git push 触发 Vercel 自动部署）
#
# 用法：
#   export GITHUB_PAT="github_pat_xxx"  # GitHub 私人令牌
#   bash /workspace/nexushub-pages/api/publish.sh <version> <apk_path> [changelog line 1] [changelog line 2] ...
#
# 例子：
#   bash publish.sh 1.26.6.7.1200 /workspace/dist/NexusHub-1.26.6.7.1200-debug.apk \
#       "新功能 A" "修复 B" "优化 C"
#
# 它会做：
#   1. 算 SHA256 + size
#   2. 复制 APK 到 apks/ 目录
#   3. 更新 manifest.json（添加新版本 + 设为 latest）
#   4. git commit + push 到 GitHub
#   5. Vercel 检测到推送 → 30-60 秒后自动重新部署
#   6. 用户访问 https://cgw-lime.vercel.app/ 看到新版本

set -e

# ─────── 校验 ───────
: "${GITHUB_PAT:?需要 export GITHUB_PAT=... （GitHub 私人令牌）}"
GITHUB_USER="${GITHUB_USER:-cgw666666}"
GITHUB_REPO="${GITHUB_REPO:-apk_api}"
BRANCH="${BRANCH:-main}"
SITE_URL="${SITE_URL:-https://cgw-lime.vercel.app}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

VERSION="${1:-}"
APK_PATH="${2:-}"
shift 2 2>/dev/null || true
CHANGELOG_LINES=("$@")

if [ -z "$VERSION" ] || [ -z "$APK_PATH" ]; then
    echo "用法: $0 <version> <apk_path> [changelog line 1] [changelog line 2] ..."
    echo ""
    echo "环境变量："
    echo "  GITHUB_PAT    GitHub 私人令牌（必填）"
    echo "  GITHUB_USER   默认 cgw666666"
    echo "  GITHUB_REPO   默认 apk_api"
    echo "  BRANCH        默认 main"
    echo "  SITE_URL      默认 https://cgw-lime.vercel.app"
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

# ─────── 1. 复制 APK 到 apks/ 目录 ───────
log "复制 APK 到 $PROJECT_DIR/apks/$APK_FILE..."
cp -f "$APK_PATH" "$PROJECT_DIR/apks/$APK_FILE"

# ─────── 2. 更新 manifest.json ───────
log "更新 manifest.json..."
python3 << PYEOF
import json, os
mf_path = '$PROJECT_DIR/manifest.json'
with open(mf_path) as f:
    m = json.load(f)

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

# ─────── 3. git commit + push ───────
cd "$PROJECT_DIR"
log "git add..."
git add apks/"$APK_FILE" manifest.json

log "git commit..."
git commit -m "release: v$VERSION

$(printf -- '- %s\n' "${CHANGELOG_LINES[@]}")" 2>&1 | tail -3

log "git push to GitHub..."
PUSH_URL="https://${GITHUB_USER}:${GITHUB_PAT}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
timeout 90 git -c credential.helper= push "$PUSH_URL" "$BRANCH" 2>&1 | tail -5

# 清理 remote URL（不保存凭证到 .git/config）
git remote set-url origin "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

# ─────── 4. 总结 ───────
log ""
log "==== 完成 ===="
log "  访问: ${G}${SITE_URL}/${N}"
log "  APK  : ${G}${SITE_URL}/apks/${APK_FILE}${N}"
log "  Vercel 会在 30-90 秒内自动重新部署"
log "  部署完成后用户刷新就能看到新版本"

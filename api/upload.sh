#!/usr/bin/env bash
# NexusHub APK 一键上传脚本（通过 Gitee Contents API）
#
# 用法：
#   export GITEE_TOKEN="xxx"   # Gitee 私人令牌（在 https://gitee.com/profile/personal_access_tokens 创建）
#   export GITEE_USER="cgw0822"
#   export GITEE_REPO="nexushub-pages"
#   bash /workspace/nexushub-pages/api/upload.sh <version> <apk_path> [changelog...]
#
# 例子（上传 v1.26.6.7.0944 + 3 条 changelog）：
#   bash upload.sh 1.26.6.7.0944 /workspace/dist/NexusHub-1.26.6.7.0944-debug.apk \
#       "用户主页功能" "评论长按操作菜单" "APK 版本号格式修复"
#
# 它会做：
#   1. 算 SHA256 + size
#   2. 拉取现有 manifest.json
#   3. 添加/更新这一版本（同时设为 latest）
#   4. PUT APK 到 apks/ 目录
#   5. PUT 更新后的 manifest.json
#   6. Gitee Pages 几分钟后自动重新部署

set -e

# ─────── 校验 ───────
: "${GITEE_TOKEN:?需要 export GITEE_TOKEN=... （Gitee 私人令牌）}"
: "${GITEE_USER:?需要 export GITEE_USER=... （Gitee 用户名）}"
GITEE_REPO="${GITEE_REPO:-nexushub-pages}"
API="https://gitee.com/api/v5"

VERSION="${1:-}"
APK_PATH="${2:-}"
shift 2 2>/dev/null || true
CHANGELOG_LINES=("$@")

if [ -z "$VERSION" ] || [ -z "$APK_PATH" ]; then
    echo "用法: $0 <version> <apk_path> [changelog line 1] [changelog line 2] ..."
    echo "  version:   e.g. 1.26.6.7.0944"
    echo "  apk_path:  本地 APK 文件路径"
    echo "  changelog: 每行一个 changelog 描述（可选）"
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

# ─────── 1. 拉取现有 manifest.json（如果有） ───────
log "拉取现有 manifest.json..."
EXISTING=$(curl -s -X GET \
    "${API}/repos/${GITEE_USER}/${GITEE_REPO}/contents/manifest.json" \
    -H "Authorization: token ${GITEE_TOKEN}")

EXISTING_SHA=$(echo "$EXISTING" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    if d.get('sha'): print(d['sha']); sys.exit(0)
    print('NONE'); sys.exit(0)
except: print('NONE')
")

if [ "$EXISTING_SHA" != "NONE" ]; then
    # 拉取并解码现有内容
    EXISTING_CONTENT=$(echo "$EXISTING" | python3 -c "
import json, sys, base64
d = json.load(sys.stdin)
content = d.get('content', '')
# Gitee 返回的 content 已经是 base64 编码的字符串
padding = 4 - len(content) % 4
if padding != 4: content += '=' * padding
print(base64.b64decode(content).decode('utf-8'))
")
    echo "$EXISTING_CONTENT" > /tmp/manifest_old.json
    log "现有 manifest.json 已保存（sha: ${EXISTING_SHA:0:10}...）"
else
    echo '{"latest":"","baseUrl":"","minAndroid":"7.0","versions":[]}' > /tmp/manifest_old.json
    log "manifest.json 不存在，将创建新的"
fi

# ─────── 2. 更新 manifest.json ───────
log "更新 manifest.json..."
python3 << PYEOF
import json, sys
with open('/tmp/manifest_old.json') as f:
    m = json.load(f)

m['latest'] = '$VERSION'
m['baseUrl'] = 'https://${GITEE_USER}.gitee.io/${GITEE_REPO}/apks'

# 找到现有版本的位置
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
    'changelog': [$(printf '"%s",' "${CHANGELOG_LINES[@]}" | sed 's/,$//')]
}

if existing_idx >= 0:
    # 更新现有版本
    m['versions'][existing_idx] = new_entry
    print(f'  updated version {existing_idx}')
else:
    # 添加到最前面
    m['versions'].insert(0, new_entry)
    print(f'  added new version')

# 写回
with open('/tmp/manifest_new.json', 'w') as f:
    json.dump(m, f, indent=2, ensure_ascii=False)
print(f'  total versions: {len(m["versions"])}')
PYEOF

# ─────── 3. 上传 APK ───────
log "上传 APK 到 apks/$APK_FILE..."
APK_B64=$(base64 -w0 "$APK_PATH")
APK_UPLOAD=$(curl -s -X POST \
    "${API}/repos/${GITEE_USER}/${GITEE_REPO}/contents/apks/${APK_FILE}" \
    -H "Authorization: token ${GITEE_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
print(json.dumps({
    'content': open('/tmp/apk_b64.txt').read().strip(),
    'message': 'release: $VERSION'
}))
")" 2>/dev/null) || true

# 上面 base64 太大可能有问题，分两步做
APK_B64_FILE=/tmp/apk_b64.txt
base64 -w0 "$APK_PATH" > "$APK_B64_FILE"
APK_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'content': open('$APK_B64_FILE').read().strip(),
    'message': 'release: $VERSION'
}))
")
APK_RESP=$(echo "$APK_PAYLOAD" | curl -s -X POST \
    "${API}/repos/${GITEE_USER}/${GITEE_REPO}/contents/apks/${APK_FILE}" \
    -H "Authorization: token ${GITEE_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @-)

if echo "$APK_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('content') else 1)" 2>/dev/null; then
    log "✓ APK 上传成功"
else
    # 可能是文件已存在，需要先 GET 拿 SHA 再更新
    if echo "$APK_RESP" | grep -q "exists"; then
        warn "APK 文件已存在，尝试更新..."
        EXIST_APK_SHA=$(curl -s "${API}/repos/${GITEE_USER}/${GITEE_REPO}/contents/apks/${APK_FILE}" \
            -H "Authorization: token ${GITEE_TOKEN}" | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")
        APK_RESP=$(echo "$APK_PAYLOAD" | python3 -c "
import json, sys
p = json.load(sys.stdin)
p['sha'] = '$EXIST_APK_SHA'
print(json.dumps(p))
" | curl -s -X PUT \
    "${API}/repos/${GITEE_USER}/${GITEE_REPO}/contents/apks/${APK_FILE}" \
    -H "Authorization: token ${GITEE_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @-)
        if echo "$APK_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('content') else 1)" 2>/dev/null; then
            log "✓ APK 更新成功"
        else
            err "APK 更新失败: $APK_RESP"
            exit 1
        fi
    else
        err "APK 上传失败: $APK_RESP"
        exit 1
    fi
fi

# ─────── 4. 上传 manifest.json ───────
log "上传 manifest.json..."
M_B64_FILE=/tmp/manifest_b64.txt
base64 -w0 /tmp/manifest_new.json > "$M_B64_FILE"
M_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'content': open('$M_B64_FILE').read().strip(),
    'message': 'manifest: bump to $VERSION'
}))
")

if [ "$EXISTING_SHA" != "NONE" ]; then
    M_PAYLOAD=$(echo "$M_PAYLOAD" | python3 -c "
import json, sys
p = json.load(sys.stdin)
p['sha'] = '$EXISTING_SHA'
print(json.dumps(p))
")
    M_RESP=$(echo "$M_PAYLOAD" | curl -s -X PUT \
        "${API}/repos/${GITEE_USER}/${GITEE_REPO}/contents/manifest.json" \
        -H "Authorization: token ${GITEE_TOKEN}" \
        -H "Content-Type: application/json" \
        -d @-)
else
    M_RESP=$(echo "$M_PAYLOAD" | curl -s -X POST \
        "${API}/repos/${GITEE_USER}/${GITEE_REPO}/contents/manifest.json" \
        -H "Authorization: token ${GITEE_TOKEN}" \
        -H "Content-Type: application/json" \
        -d @-)
fi

if echo "$M_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('content') else 1)" 2>/dev/null; then
    log "✓ manifest.json 上传成功"
else
    err "manifest.json 上传失败: $M_RESP"
    exit 1
fi

# ─────── 5. 清理 + 总结 ───────
rm -f /tmp/manifest_old.json /tmp/manifest_new.json /tmp/apk_b64.txt /tmp/manifest_b64.txt
log ""
log "==== 完成 ===="
log "  访问: ${G}https://${GITEE_USER}.gitee.io/${GITEE_REPO}/${N}"
log "  APK  : ${G}https://${GITEE_USER}.gitee.io/${GITEE_REPO}/apks/${APK_FILE}${N}"
log "  Gitee Pages 会在 1-3 分钟内自动重新部署"

# NexusHub 发布 API

新版本发布流程（agent 用的）。

## 概述

整个系统由两个仓库组成：

| 仓库 | 内容 | 托管 |
|---|---|---|
| [cgw666666/apk_api](https://github.com/cgw666666/apk_api) | 网页代码 (index.html + manifest.json) | Vercel → https://cgw-lime.vercel.app/ |
| [cgw666666/hub_apk](https://github.com/cgw666666/hub_apk) | APK 文件 (apks/*.apk) | jsDelivr CDN |

`publish.sh` 一次跑完所有发布动作。

## 调用

### 第一次：设置环境变量

```bash
export GITHUB_PAT="github_pat_xxx"   # GitHub 私人令牌
# 可选（默认值就是下面这些）
export GITHUB_USER="cgw666666"
export GITHUB_REPO="apk_api"          # 网页代码仓库
export APK_REPO="hub_apk"             # APK 存储仓库
export BRANCH="main"
export SITE_URL="https://cgw-lime.vercel.app"
```

**GITHUB_PAT 从哪来**（不是密码，是个人访问令牌）：
1. 打开 https://github.com/settings/tokens
2. 右上角 "Generate new token" → "Generate new token (classic)"
3. Note: `apk_api_deploy`
4. Expiration: `No expiration`
5. Select scopes: **只勾选 `repo`**
6. 点 "Generate token" → **立刻复制**那串 `ghp_...` 或 `github_pat_...`

### 发布新版本

```bash
bash api/publish.sh <version> <apk_path> [changelog line 1] [changelog line 2] ...
```

**例子**：
```bash
bash publish.sh 1.26.6.7.1200 /workspace/dist/NexusHub-1.26.6.7.1200-debug.apk \
    "用户主页功能" \
    "评论长按操作菜单" \
    "APK 版本号格式修复"
```

**自动完成**：
1. 算 SHA256 + size
2. 复制 APK 到 hub_apk/apks/
3. 拉取 hub_apk 最新 manifest.json（如有），加新版本（设为 latest）
4. git commit + push 到 **两个仓库**（hub_apk + apk_api）
5. Vercel 检测到 apk_api 推送 → 30-60 秒自动重新部署
6. jsDelivr 5-15 分钟内同步新 APK（用户可能需要等一会儿才能下到新版本）

**输出**：
```
[14:30:01] version:    1.26.6.7.1200
[14:30:01] file:       NexusHub-1.26.6.7.1200-debug.apk
[14:30:01] size:       18191274 bytes (17.3 MB)
[14:30:01] sha256:     abc123...
[14:30:02]   复制 APK 到 hub_apk
[14:30:03]   更新 hub_apk 的 manifest.json
[14:30:04]   git push hub_apk
[14:30:06]   git push apk_api
==== 完成 ====
  访问: https://cgw-lime.vercel.app/
  APK  : https://cdn.jsdelivr.net/gh/cgw666666/hub_apk@main/apks/NexusHub-1.26.6.7.1200-debug.apk
  Vercel 会在 30-60 秒内自动重新部署
  jsDelivr 会在 5-15 分钟内同步新 APK
```

## manifest.json 格式

在 `hub_apk` 仓库根目录：

```json
{
  "latest": "1.26.6.7.0944",
  "baseUrl": "https://cdn.jsdelivr.net/gh/cgw666666/hub_apk@main/apks",
  "minAndroid": "7.0",
  "versions": [
    {
      "version": "1.26.6.7.0944",
      "file": "NexusHub-1.26.6.7.0944-debug.apk",
      "size": 18191274,
      "sha256": "74c84adfa...",
      "date": "2026-06-07",
      "changelog": ["...", "..."]
    }
  ]
}
```

## 常见问题

**Q: 网页更新了但 APK 还没同步？**
A: Vercel 30-60 秒自动重新部署。jsDelivr 5-15 分钟同步新 APK。强制刷新浏览器（Ctrl+Shift+R 或 Cmd+Shift+R）绕过缓存。

**Q: 401 Unauthorized？**
A: GITHUB_PAT 错了或过期。重新去 https://github.com/settings/tokens 生成。

**Q: 怎么把旧版本删了？**
A: 直接在 hub_apk 仓库里手动删除对应 APK 文件 + 编辑 manifest.json 移除该版本。

## 仓库地址

- 网页代码：https://github.com/cgw666666/apk_api
- APK 存储：https://github.com/cgw666666/hub_apk
- 在线网站：https://cgw-lime.vercel.app/

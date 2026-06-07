# NexusHub Pages 上传 API

接口说明 + 调用方法（agent 用的）。

## 概述

静态网页托管在 **Gitee Pages**（`https://cgw0822.gitee.io/nexushub-pages/`）。
- `index.html` — 下载页，**前端 JS 自动从 `manifest.json` 读所有版本信息**
- `manifest.json` — 版本清单（latest / baseUrl / versions[]）
- `apks/*.apk` — APK 文件

agent 每次发新版本只需要调一次 `api/upload.sh` 脚本，自动完成：
1. 算 SHA256 + size
2. 拉取并更新 `manifest.json`（添加新版本 + 设为 latest）
3. 上传 APK 到 `apks/`
4. 上传 `manifest.json`
5. Gitee Pages 1-3 分钟自动重新部署

## 调用

### 第一次：设置环境变量

```bash
export GITEE_TOKEN="xxxxxxxxxxxx"   # Gitee 私人令牌
export GITEE_USER="cgw0822"
export GITEE_REPO="nexushub-pages"
```

**GITEE_TOKEN 从哪来**（不是密码，是**私人令牌**）：
1. 打开 https://gitee.com/profile/personal_access_tokens
2. 点击 "生成新令牌"
3. 权限勾选：`projects`（读写项目）
4. 提交后会显示一长串 token（**只显示一次**，立即复制保存）

### 上传新版本

```bash
bash api/upload.sh <version> <apk_path> [changelog line 1] [changelog line 2] ...
```

**例子**：
```bash
bash api/upload.sh 1.26.6.7.0944 /workspace/dist/NexusHub-1.26.6.7.0944-debug.apk \
    "用户主页功能：点击作者头像/昵称可跳转个人主页" \
    "评论长按弹出操作菜单" \
    "APK 版本号格式修复"
```

**输出**：
```
[14:30:01] version:    1.26.6.7.0944
[14:30:01] file:       NexusHub-1.26.6.7.0944-debug.apk
[14:30:01] size:       18191274 bytes (17.3 MB)
[14:30:01] sha256:     74c84adfab36f5087260d9aaa53af475fe1c19f5d8b1c4749cb4fae15fd3da98
[14:30:02] ✓ APK 上传成功
[14:30:03] ✓ manifest.json 上传成功
==== 完成 ====
  访问: https://cgw0822.gitee.io/nexushub-pages/
  APK  : https://cgw0822.gitee.io/nexushub-pages/apks/NexusHub-1.26.6.7.0944-debug.apk
  Gitee Pages 会在 1-3 分钟内自动重新部署
```

## 底层 Gitee API

如果不想用脚本，可以直接调 Gitee API：

| 用途 | Method | Endpoint |
|---|---|---|
| 读 manifest.json | GET | `/repos/{user}/{repo}/contents/manifest.json` |
| 写 manifest.json | POST / PUT | `/repos/{user}/{repo}/contents/manifest.json` |
| 上传 APK | POST | `/repos/{user}/{repo}/contents/apks/{filename}` |
| 更新 APK | PUT | `/repos/{user}/{repo}/contents/apks/{filename}` |

所有请求需 header：`Authorization: token {GITEE_TOKEN}`

**请求体**：
```json
{
  "content": "<base64 编码的文件内容>",
  "message": "release: v1.26.6.7.0944"
}
```

更新已有文件时需要额外带 `"sha": "<现有文件的 sha>"`（先 GET 拿）。

## manifest.json 格式

```json
{
  "latest": "1.26.6.7.0944",
  "baseUrl": "https://cgw0822.gitee.io/nexushub-pages/apks",
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

**Q: 上传后网页没更新？**
A: Gitee Pages 重新部署需要 1-3 分钟。等一下再刷新，**强制刷新**（Ctrl+Shift+R 或 Cmd+Shift+R）绕过浏览器缓存。

**Q: Gitee 提示 401 错误？**
A: GITEE_TOKEN 错了或过期了。重新去 https://gitee.com/profile/personal_access_tokens 生成新的。

**Q: 怎么删除某个旧版本？**
A: 调用 `DELETE /repos/{user}/{repo}/contents/apks/{filename}`，需要 `sha` 参数。

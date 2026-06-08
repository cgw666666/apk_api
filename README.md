# Nexus Hub · 下载页

静态下载页 + Vercel 自动部署 + APK 走 jsDelivr CDN。

## 在线地址

**https://cgw-lime.vercel.app/**

## 文件结构

```
apk_api/                       ← 本仓库（网页代码）
├── .gitignore
├── README.md
├── download.html              ← 重定向到 index.html
├── index.html                 ← 下载页（动态从 manifest.json 读取）
├── manifest.json              ← 版本清单（latest/baseUrl/versions[]）
└── api/
    ├── publish.sh             # 我（agent）用的发布脚本
    └── README.md              # 接口文档

hub_apk/                       ← 独立仓库（仅放 APK 文件）
└── apks/
    ├── NexusHub-1.0.1-debug.apk
    ├── ...
    └── NexusHub-1.26.6.7.0944-debug.apk
```

## 工作流

```
[agent 构建新 APK]
       ↓
[publish.sh 算 SHA + 更新 manifest.json + 推到 GitHub]
       ↓
[Vercel 检测到 GitHub 推送 → 30-60 秒自动重新部署]
       ↓
[用户访问 https://cgw-lime.vercel.app/ 看到新版本]
       ↓
[点下载 → 从 jsDelivr CDN 下载 APK（cdn.jsdelivr.net/gh/cgw666666/hub_apk@main/apks/...）]
```

## 部署

仓库已经推送到 https://github.com/cgw666666/apk_api ，并已通过 Vercel 部署。

## 发布新版本

只需要调一次 `api/publish.sh` 脚本（详见 [api/README.md](api/README.md)）：

```bash
export GITHUB_PAT="你的 GitHub 私人令牌"
bash api/publish.sh <version> <apk_path> [changelog line 1] [changelog line 2] ...
```

会自动完成：算 SHA → 更新 manifest.json → 复制 APK 到 hub_apk 仓库 → commit + push → Vercel 自动重新部署。

## 技术栈

- **前端**：原生 HTML + CSS + JS（无构建工具）
- **下载**：4 路 Range 分块 + SHA256 校验 + 自动重试
- **网页托管**：Vercel（自动从 GitHub 部署）
- **APK 托管**：GitHub + jsDelivr CDN

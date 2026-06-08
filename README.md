# Nexus Hub · 下载页

静态下载页 + Gitee Pages 自动部署。

## 在线地址

**https://cgw0822.gitee.io/apk_api/**

## 文件结构

```
apk_api/
├── index.html       # 下载页（动态从 manifest.json 读取所有版本）
├── manifest.json    # 版本清单（latest/baseUrl/versions[]）
├── apks/            # 所有 APK 文件
│   ├── NexusHub-1.0.1-debug.apk
│   ├── NexusHub-1.1.6-debug.apk
│   ├── ...
│   └── NexusHub-1.26.6.7.0944-debug.apk
├── api/
│   ├── upload.sh    # agent 用的上传脚本（调 Gitee API）
│   └── README.md    # 接口文档
└── README.md
```

## 部署流程

1. **仓库推送**：
   ```bash
   cd /workspace/apk_api
   git init
   git remote add origin https://gitee.com/cgw0822/apk_api.git
   git add .
   git commit -m "initial commit"
   git push -u origin master
   ```

2. **开启 Gitee Pages**：
   - 打开 https://gitee.com/cgw0822/apk_api
   - 顶部菜单 **服务** → **Gitee Pages** → **启动**
   - 部署分支选 `master`，启动即可

3. **访问**：`https://cgw0822.gitee.io/apk_api/`

## 发布新版本

只需要调一次 `api/upload.sh` 脚本（详见 [api/README.md](api/README.md)）：

```bash
export GITEE_TOKEN="你的 Gitee 私人令牌"
bash api/upload.sh <version> <apk_path> [changelog line 1] [changelog line 2] ...
```

会自动完成：算 SHA → 更新 manifest → 上传 APK → 上传 manifest，**Gitee Pages 1-3 分钟自动重新部署**。

## 技术栈

- **前端**：原生 HTML + CSS + JS（无构建工具）
- **下载**：4 路 Range 分块 + SHA256 校验 + 自动重试
- **托管**：Gitee Pages（国内访问快）
- **API**：Gitee Contents API（上传/更新文件）

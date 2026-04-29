# One Build 一键配置

用于安装和配置 Codex 应用、Obsidian 与 LLM Wiki 的一键脚本。

脚本已经发布到 GitHub Raw。用户只需要复制对应系统的一条命令执行。

## Windows

用户在 PowerShell 中执行这一条命令：

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p
```

可选：跳过最后自动打开应用。

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -SkipOpenApps
```

可选：强制升级已安装的软件和工具。默认会跳过已安装项目，避免每次运行都很慢。

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -UpgradeTools
```

不要使用 `Invoke-RestMethod ... | Invoke-Expression` 直接管道执行主脚本。Windows 脚本需要真实文件路径来完成 UAC 提权重启，所以必须先下载到临时文件再执行。

脚本会请求管理员权限；必要时自动安装或修复 `winget`，安装 `uv`，升级或安装 Codex 应用和 Obsidian，然后要求用户选择 Obsidian 仓库目录。

## macOS

用户在终端中执行这一条命令：

```bash
u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.sh"; f="$(mktemp)"; curl -fsSL "$u" -o "$f"; bash "$f"
```

可选：跳过最后自动打开应用。

```bash
u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.sh"; f="$(mktemp)"; curl -fsSL "$u" -o "$f"; bash "$f" --skip-open-apps
```

脚本会在需要时安装 `uv`，要求用户选择 Obsidian 仓库目录，安装或升级 Codex 应用和 Obsidian，然后配置 `llmwiki`。

## 发布要求

- 云端地址必须是 HTTPS。
- `setup.ps1` 和 `setup.sh` 必须作为原始文本返回，不能返回 HTML 预览页。
- Windows 用户命令必须下载到临时文件后执行，不能直接管道执行。
- 如果使用 GitHub，使用 Raw 地址，例如 `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/setup.ps1`。

## 说明

- Codex 登录不会自动化；脚本只负责安装并打开官方应用。
- 脚本不会删除已有的 Obsidian 仓库内容。
- LLM Wiki 会创建或复用所选仓库中的 `llmwiki` 目录。
- PyPI 包名是 `llmwiki`，安装后的命令名是 `llmbase`。
- Obsidian CLI 需要 Obsidian 1.12.7+，并且 Obsidian 应用需要运行。脚本会尽量自动注册 CLI 到 PATH、启动 Obsidian 并执行 `obsidian version` 验证；如果验证失败，请在 Obsidian 的设置 -> 通用 中开启 `Command line interface`。

## 安装后怎么用

### 1. 普通用户使用 Obsidian

脚本完成后，打开 Obsidian，选择你安装时选的仓库目录。里面会有一个 `llmwiki` 目录：

```text
你的 Obsidian 仓库
└── llmwiki
    ├── raw
    └── wiki
        ├── _meta
        ├── concepts
        └── outputs
```

- `raw`：放原始资料或由 `llmbase ingest` 导入后的资料。
- `wiki/concepts`：编译出来的知识页。
- `wiki/outputs`：查询或生成的输出。
- `_meta`：LLM Wiki 的元数据。

### 2. Codex 或终端直接操作 Obsidian

Obsidian CLI 的命令名是 `obsidian`。它要求 Obsidian 应用正在运行。

常用命令：

```powershell
obsidian version
obsidian vaults
obsidian search query="关键词"
obsidian search:context query="关键词"
obsidian files folder="llmwiki"
obsidian read path="llmwiki/wiki/concepts/某个文件.md"
obsidian create path="llmwiki/outputs/计划.md" content="# 计划\n\n内容" open
obsidian append path="llmwiki/outputs/计划.md" content="\n- 新增事项"
```

如果终端当前目录就在 Obsidian 仓库根目录，CLI 会优先使用这个仓库。否则可以用 `vault=<仓库名>` 指定：

```powershell
obsidian vault="Obsidian_wiki" search query="Codex"
```

### 3. 使用 LLM Wiki 导入和查询资料

LLM Wiki 的命令名是 `llmbase`。下面示例假设你的 LLM Wiki 目录是 `E:\Obsidian_wiki\llmwiki`。

查看状态：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" stats
```

导入本地文件：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" ingest file "D:\资料\文档.md"
```

导入整个目录：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" ingest dir "D:\资料"
```

导入网页：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" ingest url "https://example.com/article"
```

把新导入的资料编译成 wiki：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" compile new
```

搜索知识库：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" search query "关键词"
```

向知识库提问：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" query "这些资料的核心结论是什么？"
```

把回答写回 wiki：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" query "总结这些资料" --file-back
```

启动网页界面：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" web
```

启动 MCP 服务，给支持 MCP 的 AI 客户端集成：

```powershell
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" mcp
```

### 4. 给 Codex 的推荐工作方式

你可以在 Codex 里直接这样要求：

```text
请使用 obsidian CLI 搜索我的 Obsidian 仓库中关于“项目计划”的笔记，并把总结写入 llmwiki/outputs/项目计划总结.md。
```

或者：

```text
请把 D:\资料 里的文档导入 llmbase，编译新资料，然后基于知识库回答“这些资料里有哪些行动项”。
```

Codex 可用的底层命令就是：

```powershell
obsidian search query="项目计划"
obsidian create path="llmwiki/outputs/项目计划总结.md" content="..."
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" ingest dir "D:\资料"
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" compile new
llmbase --base-dir "E:\Obsidian_wiki\llmwiki" query "这些资料里有哪些行动项"
```

### 5. 重要限制

- Obsidian CLI 不是后台数据库，它连接的是正在运行的 Obsidian 应用。
- `llmbase query` 需要可用的 LLM 配置；如果本机没有相应 API key 或模型配置，查询/编译类命令可能失败。
- 当前脚本只完成安装、CLI 注册和目录准备；不会自动把 Codex 的所有聊天记录同步进 Obsidian。

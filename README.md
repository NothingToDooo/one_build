# One Build 一键配置

用于给少量用户一键部署 Codex 应用、Obsidian、Obsidian CLI、`llmwiki` 命令，以及一套 Codex 可直接读取的 LLM Wiki 工作流模板。

脚本发布在 GitHub Raw。用户只需要复制对应系统的一条命令执行。

## Windows

在 PowerShell 中执行：

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p
```

不自动打开应用：

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -SkipOpenApps
```

强制尝试升级已有工具：

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -UpgradeTools
```

不要使用 `Invoke-RestMethod ... | Invoke-Expression` 直接管道执行主脚本。Windows 脚本需要真实文件路径来完成 UAC 提权重启，所以必须先下载到临时文件再执行。

## macOS

在终端中执行：

```bash
u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.sh"; f="$(mktemp)"; curl -fsSL "$u" -o "$f"; bash "$f"
```

不自动打开应用：

```bash
u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.sh"; f="$(mktemp)"; curl -fsSL "$u" -o "$f"; bash "$f" --skip-open-apps
```

## 脚本会做什么

- Windows 自动请求管理员权限。
- Windows 检查并补齐 `winget` 和 `uv`。
- macOS 检查并补齐 `uv`。
- 安装或复用 Codex 应用和 Obsidian。
- 配置并验证 Obsidian CLI。
- 安装或复用 `llmwiki`，实际可执行命令是 `llmbase`。
- 要求用户通过 GUI 选择 Obsidian 仓库目录。
- 在用户选择的仓库中创建或复用 `llmwiki/`。
- 部署 Codex LLM Wiki 工作流模板。
- 同步常用 Obsidian/Codex skills 到用户全局目录 `~/.agents/skills`。
- 创建或补充仓库根目录 `AGENTS.md`，让 Codex 打开整个 vault 时也能发现 `llmwiki/AGENTS.md`。

## 部署后的结构

```text
你的 Obsidian 仓库
├── AGENTS.md
└── llmwiki
    ├── AGENTS.md
    ├── SCHEMA.md
    ├── index.md
    ├── log.md
    ├── raw
    │   ├── articles
    │   ├── papers
    │   ├── transcripts
    │   └── assets
    ├── entities
    ├── concepts
    ├── comparisons
    ├── queries
    └── _archive
```

`raw/` 放原始资料；`entities/`、`concepts/`、`comparisons/`、`queries/` 是 Codex 维护的 wiki 页面。脚本不会覆盖已有模板文件，也不会删除用户已有 Markdown。

## 给 Codex 的使用方式

在 Codex 中打开用户选择的 Obsidian 仓库目录，然后直接提出任务，例如：

```text
请按 llmwiki/AGENTS.md 的规则，把 D:\资料 里的文档导入这个知识库，抽取实体和概念，更新 index.md 和 log.md。
```

```text
请基于 llmwiki 回答“这些资料里反复出现的核心主张是什么”，答案要链接到相关 wiki 页面和原始资料。
```

Codex 会先读取根目录 `AGENTS.md`，再进入 `llmwiki/AGENTS.md`、`SCHEMA.md`、`index.md` 和 `log.md` 执行工作流。

## 同步的全局 skills

脚本会安装或更新这些 skill 到 `~/.agents/skills`：

- `llm-wiki`：本仓库提供的中文 Codex LLM Wiki 工作流 skill。
- `defuddle`：来自 [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills/tree/main/skills/defuddle)。
- `obsidian-bases`：来自 [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills/tree/main/skills/obsidian-bases)。
- `obsidian-cli`：来自 [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills/tree/main/skills/obsidian-cli)。
- `obsidian-markdown`：来自 [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills/tree/main/skills/obsidian-markdown)。
- `excalidraw-diagram`：来自 [axtonliu/axton-obsidian-visual-skills](https://github.com/axtonliu/axton-obsidian-visual-skills/tree/main/excalidraw-diagram)。
- `mermaid-visualizer`：来自 [axtonliu/axton-obsidian-visual-skills](https://github.com/axtonliu/axton-obsidian-visual-skills/tree/main/mermaid-visualizer)。
- `obsidian-canvas-creator`：来自 [axtonliu/axton-obsidian-visual-skills](https://github.com/axtonliu/axton-obsidian-visual-skills/tree/main/obsidian-canvas-creator)。

如果目标目录里已经有同名 skill，且不是 one_build 之前安装的版本，脚本会先备份到 `~/.agents/skills/_one_build_backups`，再安装新版。

## 边界

- Codex 登录不会自动化。
- Obsidian CLI 需要 Obsidian 应用正在运行。
- `llmbase query` 需要用户本机已有可用的 LLM 配置。
- 这不是 MCP 项目；主要入口是 Codex 读取 `AGENTS.md` 后按本地文件工作流操作。

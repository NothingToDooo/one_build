# One Build 一键配置

用于给少量用户一键部署 Codex 应用、Obsidian、`defuddle`，并尝试配置 Obsidian CLI，以及一套 agent 可直接读取的 LLM Wiki 工作流模板。

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
- Windows 检查并补齐 `winget`。
- Windows 检查并补齐 `bun`，然后用 `bun install -g defuddle` 安装 `defuddle`。
- macOS 检查并补齐 `bun`，然后用 `bun install -g defuddle` 安装 `defuddle`。
- 安装或复用 Codex 应用和 Obsidian。
- 尝试配置并验证 Obsidian CLI；不可用时安装继续，后续 agent 优先直接编辑文件。
- 要求用户通过 GUI 选择 Obsidian 仓库目录。
- 在用户选择的仓库中创建或复用 `llmwiki/`。
- 部署 Codex LLM Wiki 工作流模板。
- 在用户选择的 vault 内安装并启用 Excalidraw 社区插件，供 `excalidraw-diagram` skill 使用。
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
    │   ├── tables
    │   ├── documents
    │   ├── slides
    │   ├── images
    │   └── assets
    ├── entities
    ├── concepts
    ├── comparisons
    ├── queries
    ├── summaries
    └── _archive
```

`raw/` 放原始资料和提取 sidecar；`entities/`、`concepts/`、`comparisons/`、`queries/`、`summaries/` 是 Codex 维护的 wiki 页面。`AGENTS.md` 和 `SCHEMA.md` 包含导入、重新导入、批量处理、审计、归档和日志轮转规则。脚本不会覆盖已有模板文件，也不会删除用户已有 Markdown。

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

- `llm-wiki`：安装时生成的入口 skill，只记录用户选择的 vault 路径，并指引 Codex 读取 `llmwiki/AGENTS.md`。
- `defuddle`：来自 [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills/tree/main/skills/defuddle)，脚本会把安装提示改为 `bun install -g defuddle`。
- `obsidian-bases`：来自 [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills/tree/main/skills/obsidian-bases)。
- `obsidian-cli`：来自 [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills/tree/main/skills/obsidian-cli)。
- `obsidian-markdown`：来自 [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills/tree/main/skills/obsidian-markdown)。
- `excalidraw-diagram`：来自 [axtonliu/axton-obsidian-visual-skills](https://github.com/axtonliu/axton-obsidian-visual-skills/tree/main/excalidraw-diagram)。
- `mermaid-visualizer`：来自 [axtonliu/axton-obsidian-visual-skills](https://github.com/axtonliu/axton-obsidian-visual-skills/tree/main/mermaid-visualizer)。
- `obsidian-canvas-creator`：来自 [axtonliu/axton-obsidian-visual-skills](https://github.com/axtonliu/axton-obsidian-visual-skills/tree/main/obsidian-canvas-creator)。

这些固定名单内的 skill 会在安装时直接替换同名目录，确保用户拿到当前脚本定义的版本。

`obsidian-bases`、`obsidian-canvas-creator`、`mermaid-visualizer` 使用 Obsidian 核心能力或 Markdown 渲染能力，不需要额外社区插件。`excalidraw-diagram` 需要社区插件 `obsidian-excalidraw-plugin`，脚本会自动下载到所选 vault 的 `.obsidian/plugins/obsidian-excalidraw-plugin/` 并写入 `.obsidian/community-plugins.json`。

## 边界

- Codex 登录不会自动化。
- Obsidian CLI 是 best-effort 配置；如果不可用，agent 仍可直接编辑 vault 内文件。
- 这不是 MCP 项目；主要入口是 Codex 读取 `AGENTS.md` 后按本地文件工作流操作。
- 默认不安装 `llmwiki/llmbase` Python 包，也不安装 `llm-wiki-compiler`，因为它们都需要单独配置 LLM API 才能发挥主要能力。

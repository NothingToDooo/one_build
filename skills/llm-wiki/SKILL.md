---
name: llm-wiki
description: 在 Obsidian vault 中创建、维护和查询 Codex LLM Wiki。适用于用户要求导入资料、整理知识库、基于本地 wiki 回答问题、维护 index/log/schema，或提到 llmwiki、LLM Wiki、知识库、Obsidian wiki 时。
---

# Codex LLM Wiki

这个 skill 用于操作本地 Obsidian vault 中的 `llmwiki/` 目录。它和项目安装脚本部署的 `llmwiki/AGENTS.md`、`SCHEMA.md`、`index.md`、`log.md` 配合使用。

## 触发场景

当用户提出以下请求时使用：

- 创建或初始化 LLM Wiki
- 导入 URL、文件、文件夹、论文、文章、会议记录或粘贴文本
- 基于已有 wiki 回答问题
- 整理、审计、lint、去重或维护知识库
- 更新 `index.md`、`log.md`、`SCHEMA.md`
- 在 Obsidian vault 中维护结构化知识页面

## 定位 Wiki

优先使用当前工作目录中的 `llmwiki/`。

如果当前目录不是 Obsidian vault：

1. 询问用户 vault 路径，或根据用户给出的路径进入 vault。
2. 确认 `llmwiki/AGENTS.md` 存在。
3. 如果不存在，说明需要先运行 one_build 安装脚本或让用户明确允许初始化。

## 每次开始前

在导入、查询或整理前：

1. 阅读 `llmwiki/AGENTS.md`。
2. 阅读 `llmwiki/SCHEMA.md`。
3. 阅读 `llmwiki/index.md`。
4. 阅读 `llmwiki/log.md` 的最新记录。
5. 搜索已有页面，避免重复创建。

## 目录结构

```text
llmwiki
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

`raw/` 是原始资料层，默认不可变。`entities/`、`concepts/`、`comparisons/`、`queries/` 是 Codex 维护的 wiki 层。

## 导入工作流

当用户要求导入资料：

1. 把资料保存或定位到合适的 `raw/` 子目录。
2. 新建原始 Markdown 时添加 `source_url`、`ingested`、`sha256` frontmatter。
3. 搜索 `index.md` 和现有页面。
4. 对重要实体、概念、对比或复杂问题创建或更新页面。
5. 新页面尽量加入至少两个有用的 `[[wikilinks]]`。
6. 更新 `index.md`。
7. 在 `log.md` 追加操作记录。

## 查询工作流

当用户要求基于知识库回答：

1. 先用 `index.md` 找候选页面。
2. 搜索 wiki 文件中的精确关键词和相关词。
3. 阅读相关页面和原始资料。
4. 回答时给出 wiki 页面和原始资料路径。
5. 复杂答案保存到 `llmwiki/queries/`。
6. 在 `log.md` 追加查询记录。

## 维护工作流

当用户要求整理、审计或 lint：

- 检查断开的 `[[wikilinks]]`
- 检查孤立页面
- 检查缺失 frontmatter 的页面
- 检查未登记标签
- 检查过时或冲突结论
- 检查未加入 `index.md` 的页面
- 检查过长页面并建议拆分

## 工具使用

- 优先直接读写 Markdown 文件。
- 如果 Obsidian 正在运行且 CLI 可用，可以使用 `obsidian` 搜索、读取、创建或追加笔记。
- 如果 `llmbase` 可用，可以用它做底层资料导入、状态检查或查询，但不要把它当成唯一入口。

## 安全边界

- 不要删除或重写 `raw/` 资料，除非用户明确要求。
- 不要编造引用；无法追溯来源的结论要标记为低置信度。
- 不要修改 `llmwiki/` 外的用户笔记，除非用户明确要求。
- 不要把路过式提及扩展成 wiki 页面。

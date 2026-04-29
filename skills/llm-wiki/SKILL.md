---
name: llm-wiki
description: 定位并进入用户的 Codex LLM Wiki。适用于用户提到 llmwiki、LLM Wiki、知识库、Obsidian wiki，或要求导入资料、查询知识库、整理 wiki 时。
---

# Codex LLM Wiki 入口

这个全局 skill 只负责定位 wiki 和加载本地规则，不定义具体维护规则。

## 使用方式

1. 优先查找当前工作目录下的 `llmwiki/AGENTS.md`。
2. 如果当前目录没有 `llmwiki/AGENTS.md`，请用户提供 Obsidian vault 路径。
3. 进入 vault 后，先读取：
   - `llmwiki/AGENTS.md`
   - `llmwiki/SCHEMA.md`
   - `llmwiki/index.md`
   - `llmwiki/log.md`
4. 后续全部按照 `llmwiki/AGENTS.md` 和 `llmwiki/SCHEMA.md` 执行。

如果这是通过 one_build 安装脚本安装的全局 skill，脚本会在用户机器上把这里替换成包含具体 vault 路径的版本。

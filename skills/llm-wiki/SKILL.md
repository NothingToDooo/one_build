---
name: llm-wiki
description: 定位并进入用户的 LLM Wiki 或 Obsidian 知识库。适用于用户询问项目记忆、资料来源、已有笔记、研究结论、知识库内容、wiki 内容，或要求导入、查询、整理、总结、更新本地知识资料时。
---

# LLM Wiki 入口

这个全局 skill 只负责定位 wiki 和加载本地规则，不定义具体维护规则。

## 使用方式

1. 优先查找当前工作目录下的 `llmwiki/raw/AGENTS.md`。
2. 如果当前目录没有 `llmwiki/raw/AGENTS.md`，请用户提供 Obsidian vault 路径。
3. 进入 vault 后，先读取：
   - `llmwiki/raw/AGENTS.md`
   - `llmwiki/raw/SCHEMA.md`
   - `llmwiki/raw/index.md`
   - `llmwiki/raw/log.md`
4. 如果存在 `llmwiki/raw/tools/llmwiki_tool.py`，优先用它执行 hash、lint、断链检查、index 检查、表格 profile、plan 校验和 plan 应用。
5. 后续全部按照 `llmwiki/raw/AGENTS.md` 和 `llmwiki/raw/SCHEMA.md` 执行。

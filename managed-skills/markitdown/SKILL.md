---
name: markitdown
description: 使用 Microsoft MarkItDown 将 PDF、Word、PowerPoint、Excel、CSV、HTML、JSON、XML、ZIP、图片等资料转换为 Markdown，适用于导入本地文件、整理附件、把非 Markdown 文档沉淀进 LLM Wiki 或 Obsidian 知识库时。
---

# MarkItDown

MarkItDown 是本地文件到 Markdown 的转换工具。处理 LLM Wiki 导入任务时，遇到 PDF、Word、PPT、Excel、CSV、HTML、JSON、XML、ZIP、图片或其它附件，优先用它生成可审阅的 Markdown sidecar，再按 wiki 规则整理。

如果未安装，请使用：

```bash
uv tool install --upgrade "markitdown[all]"
```

## 基本用法

把单个文件转换成 Markdown：

```bash
markitdown "source.pdf" > "source.extracted.md"
```

如果文件名、目录名或 vault 路径包含中文、空格或特殊字符，始终给路径加引号。

## LLM Wiki 导入流程

1. 先读取 `llmwiki/raw/AGENTS.md`、`SCHEMA.md`、`index.md`、`log.md`。
2. 保留原始文件，把它放入合适的 `raw/` 子目录：
   - PDF、报告：`raw/papers/`
   - Word、富文本文档：`raw/documents/`
   - PPT、演示材料：`raw/slides/`
   - CSV、Excel、表格型数据：`raw/tables/`
   - 图片、截图、扫描件：`raw/images/`
   - 无法归类附件：`raw/assets/`
3. 用 MarkItDown 生成 sidecar：
   - PDF：`文件名.extracted.md`
   - Word：`文件名.extracted.md`
   - PPT：`文件名.extracted.md`
   - 表格：先生成 `文件名.extracted.md`，再按 wiki 规则补充 `文件名.profile.md`
   - 图片：能提取文字时生成 `文件名.ocr.md`，否则生成 `文件名.description.md` 并标记 `needs-ocr`
4. 在 sidecar 顶部写入 `raw/SCHEMA.md` 要求的原始资料 frontmatter，保留 `source_path`、`original_file`、`extracted_from`、`sha256` 和 `status`。
5. 从 sidecar 中提取候选实体、概念、对比、问答或总结，只把有长期价值的内容写入用户可读 wiki 页面。
6. 更新 `raw/index.md` 和 `raw/log.md`。

## 批量文件

处理大量文件时，先盘点文件清单并按类型或文件夹分组。能使用子代理时，把 PDF、Word、表格、幻灯片、图片等分给不同子代理；主代理负责合并、去重、建页和更新索引。

不要把大表、长 PDF 或整份 PPT 原文全部塞进用户可读页面。原文留在 `raw/` sidecar，wiki 页面只保存摘要、关键事实、来源和链接。

## 失败处理

- MarkItDown 输出为空或明显乱码：保留原文件，sidecar 标记 `status: failed`，在 `raw/log.md` 记录失败原因。
- 扫描 PDF 或图片无法 OCR：标记 `status: needs-ocr`，不要编造内容。
- 表格太大：只生成 profile、字段说明、样例行、关键指标和数据质量问题。
- 转换结果有敏感信息：不要擅自删除原文，先提醒用户确认处理方式。

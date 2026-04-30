---
name: markitdown
description: 使用 Microsoft MarkItDown 将 PDF、Word、PowerPoint、Excel、CSV、HTML、JSON、XML、ZIP、图片、音频等文件转换为 Markdown。适用于用户要求读取、提取、转换、预览或分析非 Markdown 文件内容时。
---

# MarkItDown

MarkItDown 是 Microsoft 的本地文件转 Markdown 工具。它负责把不同格式的文件转成适合阅读、检索和后续分析的 Markdown；不负责总结、分类、建知识库或写业务结论。

## 什么时候使用

- 用户要求读取、转换、提取、查看或分析 PDF、Word、PowerPoint、Excel、CSV、HTML、JSON、XML、ZIP、图片、音频等文件内容。
- 用户要求“转 Markdown”“提取正文”“把附件变成可读文本”。
- 后续工作流需要先得到 Markdown 中间产物，再进行摘要、整理、对比、导入或问答。

如果用户给的是普通网页 URL，优先使用网页正文提取工具；MarkItDown 更适合本地文件和明确的文件型输入。

## 安装检查

先检查命令是否可用：

```bash
markitdown --version
```

如果未安装，使用 `uv` 安装：

```bash
uv tool install --upgrade "markitdown[all]"
```

不要用 `pip`、`npm`、`pnpm` 或 `yarn` 安装。

## 基本用法

转换单个文件并保存：

```bash
markitdown "input.pdf" -o "output.md"
```

也可以输出到 stdout：

```bash
markitdown "input.pdf"
```

从 stdin 读取时，给扩展名提示：

```bash
markitdown -x pdf < "input.pdf" > "output.md"
```

路径包含中文、空格或特殊字符时，必须加引号。

## 常用格式

MarkItDown 适合转换：

- PDF：合同、报告、论文、说明书。
- Office：`.docx`、`.pptx`、`.xlsx`。
- 表格和结构化文件：`.csv`、`.json`、`.xml`。
- 网页和电子书：`.html`、`.htm`、`.epub`。
- 压缩包：`.zip`。
- 图片：可提取元信息；是否能识别文字取决于文件和本地能力。
- 音频：可在依赖可用时尝试转写。

输出是 Markdown 文本，目标是方便 LLM 和人阅读，不保证保留原文件的精确排版。

## 批量文件

批量处理前先列出文件清单，按扩展名或目录分组。输出文件名应和原文件保持可追溯关系，例如：

```bash
markitdown "report.pdf" -o "report.md"
markitdown "slides.pptx" -o "slides.md"
markitdown "table.xlsx" -o "table.md"
```

处理大量文件时，优先让每个子任务负责一类文件或一个目录；最后再由主任务汇总转换结果和失败清单。

## 失败处理

- 输出为空、明显乱码或命令失败时，报告具体文件和错误，不要编造内容。
- 扫描 PDF 或图片无法识别文字时，说明需要 OCR 或其它工具。
- 表格很大时，不要把完整转换结果直接塞进最终回答；先抽样、列字段、说明行列规模和主要 sheet。
- 转换结果可能包含隐私、合同、邮箱、手机号或内部数据时，后续展示前先考虑脱敏。
- 不要默认启用第三方插件；只有用户明确需要时才使用 `--use-plugins`。
- `--use-docintel` 需要 Azure Document Intelligence endpoint；除非用户已经提供并明确要求，否则不要使用。

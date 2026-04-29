# Codex LLM Wiki 工作流

这个目录是一套由 Codex 维护的 Markdown 知识库工作流，参考 Karpathy 的 LLM Wiki 思路：人负责提供资料和提出问题，Codex 负责整理、链接、查询和维护。

## 首要规则

把 `raw/` 视为不可变原始资料，把 `entities/`、`concepts/`、`comparisons/`、`queries/` 视为 Codex 维护的 wiki 页面。除非用户明确要求，不要删除或重写原始资料。

## 每次开始前

在导入、查询、整理或审计前，先做这四件事：

1. 阅读 `SCHEMA.md`。
2. 阅读 `index.md`。
3. 阅读 `log.md` 的最新记录。
4. 搜索已有页面，避免重复创建同义页面。

## 目录约定

- `raw/articles/`：网页文章、剪藏、博客。
- `raw/papers/`：论文、PDF、长文档。
- `raw/transcripts/`：访谈、会议记录、逐字稿、用户粘贴的长文本。
- `raw/assets/`：图片和其他被资料引用的文件。
- `entities/`：人物、组织、产品、项目、模型、工具。
- `concepts/`：概念、方法、原则、主张、主题。
- `comparisons/`：对比分析。
- `queries/`：值得保留的复杂问答。
- `_archive/`：过时但需要保留的页面。
- `index.md`：所有 wiki 页面的目录。
- `log.md`：追加式操作记录。
- `SCHEMA.md`：结构、字段、标签和维护规则。

## 导入资料

当用户要求导入 URL、文件、文件夹或粘贴文本时：

1. 把原始资料保存或定位到合适的 `raw/` 子目录。
2. 如果新建原始 Markdown，添加原始资料 frontmatter：
   - `source_url`
   - `ingested`
   - `sha256`
3. 先查 `index.md` 和已有 wiki 页面，确认是否已有相关实体或概念。
4. 只有资料对当前知识库主题足够重要时，才创建或更新 wiki 页面。
5. 新建 wiki 页面时，尽量加入至少两个有用的 `[[wikilinks]]`。
6. 更新 `index.md`。
7. 在 `log.md` 追加记录，列出创建或修改过的文件。

## 批量资料处理

当用户要求处理大量文件、整个目录、多个资料包，或资料类型明显混杂时：

1. 先盘点文件清单，按目录或类型分组，例如网页、PDF、Word、表格、幻灯片、会议记录、图片和其他附件。
2. 设计子代理分工，每个子代理只负责一个清晰边界：一个目录、一类文件，或一批相同格式资料。
3. 子代理只做提取、摘要、候选实体/概念、来源记录和风险标记，不直接改写彼此负责的文件。
4. 主代理负责合并子代理结果，去重同义实体和概念，决定是否创建或更新 wiki 页面。
5. 合并时保留每批资料的来源路径、处理状态和未解决问题。
6. 最后由主代理统一更新 `index.md` 和 `log.md`。

如果当前运行环境没有子代理能力，就先完成分组和处理计划，再按分组顺序逐批处理；不要在没有盘点的情况下直接把大量文件混在一起总结。

## 查询知识库

当用户要求基于知识库回答问题时：

1. 先用 `index.md` 选择候选页面。
2. 搜索 wiki 文件中的精确关键词和相关词。
3. 阅读相关页面和原始资料。
4. 回答时链接到 wiki 页面和原始资料路径。
5. 如果答案复杂、以后可能复用，把答案保存到 `queries/`。
6. 在 `log.md` 追加查询记录。

## 审计与整理

当用户要求审计、整理、lint 或 health-check 时，检查：

- 断开的 `[[wikilinks]]`
- 没有被索引的页面
- 孤立页面
- 缺失 frontmatter 的页面
- 未登记的标签
- 过时内容
- 有冲突但未标记的结论
- 过长页面

报告时给出具体文件路径，并在 `log.md` 追加记录。

## Obsidian CLI

如果本机已启用 Obsidian CLI，命令名通常是 `obsidian`。它要求 Obsidian 应用正在运行。

常用命令：

```powershell
obsidian version
obsidian search query="关键词"
obsidian search:context query="关键词"
obsidian create path="llmwiki/queries/example.md" content="# Example\n\nContent" open
obsidian append path="llmwiki/queries/example.md" content="\nMore content"
```

大规模结构化修改优先直接编辑文件；需要搜索、打开、创建或追加到正在运行的 Obsidian 仓库时，再使用 Obsidian CLI。

## 安全边界

- 不要删除或重写 `raw/` 中的资料，除非用户明确要求。
- 不要编造引用。无法追溯来源的结论要标记为低置信度，或要求用户补充来源。
- 不要为一闪而过的提及创建页面。
- 标签必须先登记在 `SCHEMA.md`，再使用。
- 除非用户明确要求，不要修改 `llmwiki/` 外的用户笔记。

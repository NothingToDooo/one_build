# Wiki 结构规则

## 知识库主题

第一次正式使用时，先询问用户这个知识库服务于什么主题或工作流，然后把本节更新成具体描述。

可选方向示例：

- AI/ML 研究
- 项目记忆
- 产品情报
- 个人知识管理
- 阅读笔记
- 商业研究

## 通用约定

- 面向用户阅读的 wiki 页面使用中文文件名，例如 `注意力机制.md`、`项目阶段总结.md`。
- `raw/` 原始资料、提取 sidecar 和工具产物可以保留来源文件名，或使用稳定的英文 slug。
- wiki 页面使用 YAML frontmatter。
- 相关页面之间使用 `[[wikilinks]]`。
- 每个新增 wiki 页面必须登记到 `raw/index.md`。
- 每次导入、查询、整理、创建、归档或重要更新，都必须追加到 `raw/log.md`。
- 优先写有来源支撑的结论，不要把无来源猜测写成事实。
- 综合多个来源时，可以在段落后使用来源标记，例如 `^[raw/articles/source.md]`。
- 更新页面时必须更新 `updated` 日期。
- 页面超过大约 200 行时，优先拆分成子主题，并保留双向链接。
- `raw/` 中的原始文件不可变；纠错、解释和综合写在 wiki 页面或 sidecar 文件中。

## Wiki 页面 frontmatter

```yaml
---
title: Page Title
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: entity | concept | comparison | query | summary
tags: []
sources: []
confidence: high | medium | low
contested: false
contradictions: []
---
```

字段说明：

- `title`：页面标题。
- `created`：首次创建日期。
- `updated`：最后实质更新日期。
- `type`：页面类型。
- `tags`：必须来自本文件“标签体系”。
- `sources`：支撑页面的 raw 路径列表。
- `confidence`：结论置信度。单一来源、观点性强、变化快的内容不要标为 `high`。
- `contested`：存在未解决冲突时设为 `true`。
- `contradictions`：与本页存在冲突的页面 slug。

## 原始资料 frontmatter

agent 新建原始 Markdown、提取文本、OCR 文本或 profile 时使用：

```yaml
---
title:
source_type: article | paper | transcript | table | document | slide | image | pasted | asset
source_url:
source_path:
original_file:
extracted_from:
ingested: YYYY-MM-DD
sha256:
status: raw | extracted | profiled | needs-ocr | failed
---
```

字段说明：

- `source_url`：原始 URL，没有则留空。
- `source_path`：本地原始路径或导入前路径。
- `original_file`：vault 内保留的原始文件路径。
- `extracted_from`：sidecar 来源文件。
- `sha256`：对 frontmatter 之后的正文计算，不包含 frontmatter 自身。
- `status`：处理状态。无法提取或需要 OCR 时必须明确标记。

## 文件命名

- 用户会直接阅读的 `实体/`、`概念/`、`对比/`、`问答/`、`总结/` 页面优先使用中文文件名。
- 网页：`raw/articles/title-or-domain-YYYY.md`
- PDF：`raw/papers/title-or-report-name.pdf` 和 `raw/papers/title-or-report-name.extracted.md`
- Word：`raw/documents/title.docx` 和 `raw/documents/title.extracted.md`
- 表格：`raw/tables/title.xlsx` 和 `raw/tables/title.profile.md`
- 幻灯片：`raw/slides/title.pptx` 和 `raw/slides/title.extracted.md`
- 图片：`raw/images/title.png` 和 `raw/images/title.ocr.md`
- 实体：`实体/实体名称.md`
- 概念：`概念/概念名称.md`
- 对比：`对比/比较主题.md`
- 查询：`问答/用户问题摘要.md`
- 综合总结：`总结/主题或阶段总结.md`

重名时添加短日期或序号，不要覆盖已有文件。

## 标签体系

使用新的领域标签前，先把标签登记到这里。

- source
- entity
- concept
- comparison
- query
- project
- decision
- open-question
- contested
- low-confidence
- dataset
- table
- document
- paper
- transcript
- visual

## 建页阈值

- 同一实体或概念出现在两个及以上来源中，可以建页。
- 某一实体或概念虽然只出现在一个来源，但对知识库主题很关键，也可以建页。
- 能更新既有页面时，不要创建重复页面。
- 不要为路过式提及、脚注式名字、无关背景信息创建页面。
- 只有复杂、以后可能复用、重新推导成本较高的回答才保存到 `问答/`。
- 横向比较、选型、差异分析优先放到 `对比/`。
- 跨多个来源、多个主题或一段时间的综合结论优先放到 `总结/`。

## Entity 页面

Entity 页面用于人物、组织、产品、项目、模型、工具或地点。

建议包含：

- 概述
- 关键事实和日期
- 与其他页面的关系
- 来源引用
- 未解决问题

## Concept 页面

Concept 页面用于概念、方法、主张、原则和主题。

建议包含：

- 定义
- 当前综合结论
- 相关概念
- 冲突或未解决问题
- 来源引用

## Comparison 页面

Comparison 页面说明比较对象、为什么要比较、比较维度和当前结论。适合时使用表格。

建议包含：

- 比较对象
- 比较背景
- 维度表格
- 当前结论
- 适用条件
- 来源引用

## Query 页面

Query 页面保存值得复用的复杂回答。

建议包含：

- 问题
- 回答
- 使用过的 wiki 页面
- 使用过的原始资料
- 置信度
- 后续问题

## Summary 页面

Summary 页面保存跨来源、跨主题或阶段性的综合总结。

建议包含：

- 总结范围
- 核心结论
- 支撑来源
- 涉及的实体和概念
- 争议和低置信度内容
- 下次更新条件

## 表格资料规则

表格资料先 profile，再综合。profile 至少包含：

- 文件和 sheet 列表
- 每个 sheet 的行列数
- 字段名和字段类型
- 缺失值和异常值
- 枚举字段的主要取值
- 时间字段范围
- 可能的主键和外键
- 关键指标和聚合口径
- 样例行
- 数据质量问题

只有当表格中的实体、指标、口径或结论对知识库主题重要时，才创建或更新 wiki 页面。

## 更新策略

当新资料与已有内容冲突时：

1. 比较日期、来源质量和上下文。
2. 如果新资料明显修正旧事实，保留旧事实的来源，并注明已被新来源更新。
3. 如果冲突真实存在，保留双方观点。
4. 把页面 frontmatter 中的 `contested` 改为 `true`。
5. 必要时在 `contradictions` 中登记相关页面。
6. 在正文中说明冲突点、各自来源和待确认问题。
7. 在 `raw/log.md` 追加更新记录。

## raw/index.md 规则

`raw/index.md` 按页面类型分区。每个条目一行，包含 wikilink 和一句摘要。

当某个分区超过 50 条时，按首字母、主题或子领域拆分小节。

当总页面超过 200 条时，创建 `raw/_meta/topic-map.md`，按主题组织入口。

## raw/log.md 规则

`raw/log.md` 是追加式记录，格式：

```markdown
## [YYYY-MM-DD] action | subject
```

常用 action：

- `ingest`
- `update`
- `query`
- `lint`
- `create`
- `archive`
- `delete`
- `skip`
- `error`

每条记录列出本次创建、修改、跳过、失败和需要用户判断的文件。

超过 500 条记录时，把旧日志轮转为 `raw/log-YYYY.md`，再新建 `raw/log.md`。

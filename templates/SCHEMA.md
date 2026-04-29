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

- 文件名使用小写 slug，例如 `transformer-architecture.md`。
- wiki 页面使用 YAML frontmatter。
- 相关页面之间使用 `[[wikilinks]]`。
- 每个新增 wiki 页面必须登记到 `index.md`。
- 每次导入、查询、整理、创建、归档或重要更新，都必须追加到 `log.md`。
- 优先写有来源支撑的结论，不要把无来源猜测写成事实。
- 综合多个来源时，可以在段落后使用来源标记，例如 `^[raw/articles/source.md]`。

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
---
```

## 原始资料 frontmatter

Codex 新建原始 Markdown 资料时使用：

```yaml
---
source_url:
ingested: YYYY-MM-DD
sha256:
---
```

条件允许时，`sha256` 对 frontmatter 后的正文计算。

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

## 建页阈值

- 同一实体或概念出现在两个及以上来源中，可以建页。
- 某一实体或概念虽然只出现在一个来源，但对知识库主题很关键，也可以建页。
- 能更新既有页面时，不要创建重复页面。
- 不要为路过式提及创建页面。
- 页面超过大约 200 行时，优先拆分。

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

## Query 页面

只有复杂、以后可能复用、重新推导成本较高的回答才保存到 `queries/`。

建议包含：

- 问题
- 回答
- 引用的 wiki 页面
- 引用的原始资料
- 后续问题

## 更新策略

当新资料与已有内容冲突时：

1. 比较日期和来源质量。
2. 如果冲突真实存在，保留双方观点。
3. 把页面 frontmatter 中的 `contested` 改为 `true`。
4. 在正文中说明冲突。
5. 在 `log.md` 追加更新记录。

#!/usr/bin/env python3
# ruff: noqa: C901, D400, D415, PLR0911, PLR0912, PLR0915, RUF002, T201
"""one_build LLM Wiki 工作流的确定性辅助工具。"""

import argparse
import csv
import hashlib
import importlib
import json
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

MARKDOWN_TABLE_MIN_LINES = 2
MAX_PROFILE_SAMPLES = 5
COMMAND_ERROR = 2
USER_DIRS = ["实体", "概念", "对比", "问答", "总结"]
RAW_REQUIRED = {
    "title",
    "source_type",
    "source_path",
    "original_file",
    "extracted_from",
    "ingested",
    "sha256",
    "status",
}
PAGE_REQUIRED = {
    "title",
    "created",
    "updated",
    "type",
    "tags",
    "sources",
    "confidence",
    "contested",
    "contradictions",
}
TYPE_BY_DIR = {
    "实体": "entity",
    "概念": "concept",
    "对比": "comparison",
    "问答": "query",
    "总结": "summary",
}
ALLOWED_PAGE_TYPES = set(TYPE_BY_DIR.values())
ALLOWED_RAW_STATUS = {"raw", "extracted", "profiled", "needs-ocr", "failed"}
AUDIT_REQUIRED = {
    "id",
    "target",
    "target_lines",
    "anchor_before",
    "anchor_text",
    "anchor_after",
    "severity",
    "author",
    "source",
    "created",
    "status",
}
ALLOWED_AUDIT_SEVERITY = {"info", "suggest", "warn", "error"}
ALLOWED_AUDIT_SOURCE = {"manual", "chat", "agent"}
ALLOWED_AUDIT_STATUS = {"open", "resolved"}
TEXT_EXTENSIONS = {".md", ".txt", ".csv", ".json", ".xml", ".html", ".htm"}
DOCUMENT_EXTENSIONS = {".pdf", ".doc", ".docx", ".rtf"}
SLIDE_EXTENSIONS = {".ppt", ".pptx", ".key"}
TABLE_EXTENSIONS = {".xls", ".xlsx", ".csv", ".tsv"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff"}
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".aac", ".flac", ".ogg"}
ARCHIVE_EXTENSIONS = {".zip", ".7z", ".rar", ".tar", ".gz"}
CLASSIFIED_EXTENSION_GROUPS = [
    (DOCUMENT_EXTENSIONS, "document"),
    (SLIDE_EXTENSIONS, "slide"),
    (TABLE_EXTENSIONS, "table"),
    (IMAGE_EXTENSIONS, "image"),
    (AUDIO_EXTENSIONS, "audio"),
    (ARCHIVE_EXTENSIONS, "archive"),
    (TEXT_EXTENSIONS, "text"),
]


class ToolError(Exception):
    """面向 agent 的工具可恢复错误。"""


@dataclass
class MarkdownDoc:
    """Markdown 文档的 frontmatter 与正文拆分结果。"""

    frontmatter: dict[str, Any]
    body: str
    has_frontmatter: bool


def read_text(path: Path) -> str:
    """按 UTF-8 读取文本，并兼容 UTF-8 BOM。

    Returns:
        文件文本内容。

    """
    return path.read_text(encoding="utf-8-sig")


def write_text(path: Path, text: str) -> None:
    """按 UTF-8 写入文本，并统一换行。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def normalize_newlines(text: str) -> str:
    """把文本换行归一化为 LF。

    Returns:
        归一化后的文本。

    """
    return text.replace("\r\n", "\n").replace("\r", "\n")


def parse_scalar(value: str) -> object:
    """解析最小 YAML 标量子集。

    Returns:
        字符串、布尔值、数字或列表。

    """
    value = value.strip()
    if not value:
        return ""
    if value in {"true", "True"}:
        return True
    if value in {"false", "False"}:
        return False
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(part.strip()) for part in inner.split(",")]
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    try:
        if "." in value:
            return float(value)
        return int(value)
    except ValueError:
        return value


def parse_simple_frontmatter(raw: str) -> dict[str, Any]:
    """解析本工具支持的简单 frontmatter。

    Returns:
        frontmatter 字段字典。

    """
    result: dict[str, Any] = {}
    current_key: str | None = None
    for line in raw.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("  - ") and current_key:
            current = result.setdefault(current_key, [])
            if isinstance(current, list):
                current.append(parse_scalar(line[4:]))
            continue
        match = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$", line)
        if not match:
            current_key = None
            continue
        key, value = match.group(1), match.group(2) or ""
        if not value:
            result[key] = ""
        else:
            result[key] = parse_scalar(value)
        current_key = key
    return result


def parse_markdown(text: str) -> MarkdownDoc:
    """拆分 Markdown frontmatter 和正文。

    Returns:
        拆分后的 MarkdownDoc。

    """
    text = normalize_newlines(text)
    match = re.match(r"^---\n(.*?)\n---\n?", text, flags=re.DOTALL)
    if not match:
        return MarkdownDoc({}, text, has_frontmatter=False)
    frontmatter = parse_simple_frontmatter(match.group(1))
    return MarkdownDoc(frontmatter, text[match.end() :], has_frontmatter=True)


def yaml_value(value: object) -> str:
    """把简单 Python 值渲染成 YAML 单行值。

    Returns:
        YAML 单行值字符串。

    """
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        if not value:
            return "[]"
        return "[" + ", ".join(yaml_value(item) for item in value) + "]"
    if value is None:
        return ""
    text = str(value)
    if not text or any(ch in text for ch in [":", "#", "[", "]", "{", "}", ","]):
        return json.dumps(text, ensure_ascii=False)
    return text


def render_frontmatter(frontmatter: dict[str, Any], body: str) -> str:
    """用 frontmatter 和正文重新生成 Markdown。

    Returns:
        完整 Markdown 文本。

    """
    lines = ["---"]
    for key, value in frontmatter.items():
        lines.append(f"{key}: {yaml_value(value)}")
    lines.extend(["---", ""])
    return "\n".join(lines) + body.lstrip("\n")


def body_sha256(text: str) -> str:
    """计算 Markdown 正文部分的 sha256。

    Returns:
        十六进制 sha256 摘要。

    """
    doc = parse_markdown(text)
    body = normalize_newlines(doc.body)
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def find_llmwiki(path: Path) -> Path:
    """从路径向上查找 llmwiki 根目录。

    Returns:
        llmwiki 根目录路径。

    Raises:
        ToolError: 找不到 llmwiki 根目录时抛出。

    """
    current = path.resolve()
    if current.is_file():
        current = current.parent
    for candidate in [current, *current.parents]:
        if candidate.name == "llmwiki" and (candidate / "raw").is_dir():
            return candidate
        nested = candidate / "llmwiki"
        if (nested / "raw").is_dir():
            return nested
    message = "无法定位 llmwiki 目录; 请传入 llmwiki 路径或其内部文件路径。"
    raise ToolError(message)


def relpath(path: Path, root: Path) -> str:
    """计算相对 wiki 根目录的 POSIX 风格路径。

    Returns:
        POSIX 风格相对路径。

    """
    return path.resolve().relative_to(root.resolve()).as_posix()


def safe_path(root: Path, value: str) -> Path:
    """解析并校验 plan 中的目标路径。

    Returns:
        解析后的绝对路径。

    Raises:
        ToolError: 路径越界或试图修改工具脚本时抛出。

    """
    candidate = (root / value).resolve()
    root_resolved = root.resolve()
    if candidate != root_resolved and root_resolved not in candidate.parents:
        message = f"路径越界: {value}"
        raise ToolError(message)
    if candidate.as_posix().endswith("/raw/tools/llmwiki_tool.py"):
        message = "禁止通过 plan 修改 llmwiki_tool.py"
        raise ToolError(message)
    return candidate


def print_result(data: object, *, as_json: bool) -> None:
    """输出命令结果。"""
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return
    if isinstance(data, str):
        print(data)
    else:
        print(json.dumps(data, ensure_ascii=False, indent=2))


def command_hash(args: argparse.Namespace) -> int:
    """执行正文 sha256 计算命令。

    Returns:
        进程退出码。

    """
    path = Path(args.file)
    digest = body_sha256(read_text(path))
    print_result({"file": str(path), "sha256": digest}, as_json=args.json)
    return 0


def iter_markdown(root: Path) -> list[Path]:
    """列出目录下所有 Markdown 文件。

    Returns:
        Markdown 文件路径列表。

    """
    return sorted(path for path in root.rglob("*.md") if path.is_file())


def command_verify_hash(args: argparse.Namespace) -> int:
    """执行 raw 文件 sha256 校验命令。

    Returns:
        进程退出码。

    """
    wiki = find_llmwiki(Path(args.llmwiki))
    raw = wiki / "raw"
    results = []
    for path in iter_markdown(raw):
        if "/tools/" in path.as_posix():
            continue
        doc = parse_markdown(read_text(path))
        expected = doc.frontmatter.get("sha256")
        if not expected:
            continue
        actual = body_sha256(read_text(path))
        status = "ok" if expected == actual else "mismatch"
        results.append(
            {
                "path": relpath(path, wiki),
                "status": status,
                "expected": expected,
                "actual": actual,
            },
        )
    summary = {
        "checked": len(results),
        "mismatches": [item for item in results if item["status"] != "ok"],
        "results": results,
    }
    print_result(summary, as_json=args.json)
    return 1 if summary["mismatches"] else 0


def classify_file(path: Path) -> str:
    """按扩展名粗略判断文件类型。

    Returns:
        文件类型名称。

    """
    ext = path.suffix.lower()
    for extensions, kind in CLASSIFIED_EXTENSION_GROUPS:
        if ext in extensions:
            return kind
    return "asset"


def command_inventory(args: argparse.Namespace) -> int:
    """执行资料目录盘点命令。

    Returns:
        进程退出码。

    Raises:
        ToolError: 目标目录不存在时抛出。

    """
    root = Path(args.folder)
    if not root.exists():
        message = f"目录不存在: {root}"
        raise ToolError(message)
    groups: dict[str, list[dict[str, Any]]] = {}
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        kind = classify_file(path)
        groups.setdefault(kind, []).append(
            {
                "path": str(path),
                "name": path.name,
                "extension": path.suffix.lower(),
                "bytes": path.stat().st_size,
            },
        )
    summary = {
        "root": str(root),
        "total": sum(len(items) for items in groups.values()),
        "groups": groups,
    }
    print_result(summary, as_json=args.json)
    return 0


def schema_tags(wiki: Path) -> set[str]:
    """从 SCHEMA.md 中读取已登记标签。

    Returns:
        标签集合。

    """
    schema = wiki / "raw" / "SCHEMA.md"
    if not schema.exists():
        return set()
    text = read_text(schema)
    tags = set()
    in_section = False
    for line in text.splitlines():
        if line.startswith("## 标签体系"):
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            match = re.match(r"^-\s+`?([^`\s]+)`?", line.strip())
            if match:
                tags.add(match.group(1))
    return tags


def is_meta_markdown(path: Path, wiki: Path) -> bool:
    """判断 raw 下不需要 raw frontmatter 的元数据 Markdown。"""
    raw = wiki / "raw"
    rel = relpath(path, raw)
    if rel in {"AGENTS.md", "SCHEMA.md", "index.md"}:
        return True
    return rel.startswith(("tools/", "log/", "audit/", "plans/", "_archive/"))


def audit_files(wiki: Path, mode: str) -> list[Path]:
    """按状态列出 audit 文件。"""
    audit = wiki / "raw" / "audit"
    files: list[Path] = []
    if mode in {"open", "all"} and audit.exists():
        files.extend(sorted(p for p in audit.glob("*.md") if p.name != ".gitkeep"))
    resolved = audit / "resolved"
    if mode in {"resolved", "all"} and resolved.exists():
        files.extend(sorted(p for p in resolved.glob("*.md") if p.name != ".gitkeep"))
    return files


def audit_expected_status(path: Path) -> str:
    """根据 audit 文件所在目录推断状态。"""
    return "resolved" if path.parent.name == "resolved" else "open"


def resolve_audit_target(wiki: Path, target: str) -> Path | None:
    """解析 audit target 到 wiki 内文件。"""
    candidates = [wiki / target]
    if not target.startswith("raw/"):
        candidates.extend(wiki / dirname / target for dirname in USER_DIRS)
    for candidate in candidates:
        if candidate.exists() and candidate.resolve().is_relative_to(wiki.resolve()):
            return candidate
    return None


def audit_comment_one_line(text: str) -> str:
    """提取 audit comment 第一行。"""
    in_comment = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.lower().startswith("# comment") or stripped.startswith("# 纠错"):
            in_comment = True
            continue
        if not in_comment:
            continue
        if not stripped:
            continue
        if stripped.startswith("#"):
            break
        return stripped[:120]
    return "(no comment body)"


def find_all(text: str, needle: str) -> list[int]:
    """查找所有子串位置。"""
    if not needle:
        return []
    starts = []
    offset = 0
    while True:
        index = text.find(needle, offset)
        if index < 0:
            break
        starts.append(index)
        offset = index + 1
    return starts


def offsets_to_lines(text: str, start: int, end: int) -> tuple[int, int]:
    """把字符偏移转为 1-based 行号。"""
    line = 1
    line_start = 1
    line_end = 1
    seen_start = False
    seen_end = False
    for index, char in enumerate(text):
        if not seen_start and index >= start:
            line_start = line
            seen_start = True
        if not seen_end and index >= end:
            line_end = line
            seen_end = True
            break
        if char == "\n":
            line += 1
    if not seen_start:
        line_start = line
    if not seen_end:
        line_end = line
    return line_start, max(line_start, line_end)


def resolve_audit_anchor(target_text: str, frontmatter: dict[str, Any]) -> dict[str, Any] | None:
    """用行号、唯一文本、前后文窗口解析 audit 锚点。"""
    anchor_text = str(frontmatter.get("anchor_text", ""))
    target_lines = frontmatter.get("target_lines", [])
    if (
        isinstance(target_lines, list)
        and len(target_lines) == 2
        and all(isinstance(item, int) for item in target_lines)
    ):
        line_start, line_end = target_lines
        lines = target_text.split("\n")
        if 1 <= line_start <= line_end <= len(lines):
            range_text = "\n".join(lines[line_start - 1 : line_end])
            range_index = range_text.find(anchor_text)
            if range_index >= 0:
                prefix = "\n".join(lines[: line_start - 1])
                char_start = len(prefix) + (1 if prefix else 0) + range_index
                char_end = char_start + len(anchor_text)
                resolved_start, resolved_end = offsets_to_lines(
                    target_text,
                    char_start,
                    char_end,
                )
                return {
                    "resolved": True,
                    "via": "line",
                    "char_start": char_start,
                    "char_end": char_end,
                    "line_start": resolved_start,
                    "line_end": resolved_end,
                }
    occurrences = find_all(target_text, anchor_text)
    if len(occurrences) == 1:
        char_start = occurrences[0]
        char_end = char_start + len(anchor_text)
        line_start, line_end = offsets_to_lines(target_text, char_start, char_end)
        return {
            "resolved": True,
            "via": "unique-text",
            "char_start": char_start,
            "char_end": char_end,
            "line_start": line_start,
            "line_end": line_end,
        }
    combined = (
        str(frontmatter.get("anchor_before", ""))
        + anchor_text
        + str(frontmatter.get("anchor_after", ""))
    )
    combined_index = target_text.find(combined)
    if combined and combined_index >= 0 and target_text.find(combined, combined_index + 1) < 0:
        char_start = combined_index + len(str(frontmatter.get("anchor_before", "")))
        char_end = char_start + len(anchor_text)
        line_start, line_end = offsets_to_lines(target_text, char_start, char_end)
        return {
            "resolved": True,
            "via": "context-window",
            "char_start": char_start,
            "char_end": char_end,
            "line_start": line_start,
            "line_end": line_end,
        }
    return None


def audit_lint_issues(wiki: Path) -> list[dict[str, Any]]:
    """检查 raw/audit 文件形状和目标。"""
    issues: list[dict[str, Any]] = []
    for path in audit_files(wiki, "all"):
        path_rel = relpath(path, wiki)
        doc = parse_markdown(read_text(path))
        if not doc.has_frontmatter:
            issues.append(
                {"severity": "error", "code": "audit-missing-frontmatter", "path": path_rel},
            )
            continue
        missing = sorted(AUDIT_REQUIRED - set(doc.frontmatter))
        issues.extend(
            {
                "severity": "error",
                "code": "audit-missing-field",
                "path": path_rel,
                "field": key,
            }
            for key in missing
        )
        severity = doc.frontmatter.get("severity")
        if severity and severity not in ALLOWED_AUDIT_SEVERITY:
            issues.append(
                {
                    "severity": "error",
                    "code": "audit-invalid-severity",
                    "path": path_rel,
                    "value": severity,
                },
            )
        source = doc.frontmatter.get("source")
        if source and source not in ALLOWED_AUDIT_SOURCE:
            issues.append(
                {
                    "severity": "error",
                    "code": "audit-invalid-source",
                    "path": path_rel,
                    "value": source,
                },
            )
        status = doc.frontmatter.get("status")
        expected = audit_expected_status(path)
        if status and status != expected:
            issues.append(
                {
                    "severity": "error",
                    "code": "audit-status-directory-mismatch",
                    "path": path_rel,
                    "expected": expected,
                    "actual": status,
                },
            )
        target = doc.frontmatter.get("target")
        if isinstance(target, str) and not resolve_audit_target(wiki, target):
            issues.append(
                {
                    "severity": "error",
                    "code": "audit-target-missing",
                    "path": path_rel,
                    "target": target,
                },
            )
    return issues


def command_lint(args: argparse.Namespace) -> int:
    """执行 Wiki 结构 lint 命令。

    Returns:
        进程退出码。

    """
    wiki = find_llmwiki(Path(args.llmwiki))
    allowed_tags = schema_tags(wiki)
    issues = []
    for dirname in USER_DIRS:
        for path in iter_markdown(wiki / dirname):
            doc = parse_markdown(read_text(path))
            path_rel = relpath(path, wiki)
            if not doc.has_frontmatter:
                issues.extend(
                    [
                        {
                            "severity": "error",
                            "code": "missing-frontmatter",
                            "path": path_rel,
                        },
                    ],
                )
                continue
            missing = sorted(PAGE_REQUIRED - set(doc.frontmatter))
            issues.extend(
                {
                    "severity": "error",
                    "code": "missing-field",
                    "path": path_rel,
                    "field": key,
                }
                for key in missing
            )
            expected_type = TYPE_BY_DIR[dirname]
            actual_type = doc.frontmatter.get("type")
            if actual_type and actual_type != expected_type:
                issues.extend(
                    [
                        {
                            "severity": "warning",
                            "code": "type-mismatch",
                            "path": path_rel,
                            "expected": expected_type,
                            "actual": actual_type,
                        },
                    ],
                )
            tags = doc.frontmatter.get("tags", [])
            if isinstance(tags, str):
                tags = [tags]
            for tag in tags if isinstance(tags, list) else []:
                if allowed_tags and tag not in allowed_tags:
                    issues.extend(
                        [
                            {
                                "severity": "warning",
                                "code": "unknown-tag",
                                "path": path_rel,
                                "tag": tag,
                            },
                        ],
                    )
    for path in iter_markdown(wiki / "raw"):
        if is_meta_markdown(path, wiki):
            continue
        doc = parse_markdown(read_text(path))
        path_rel = relpath(path, wiki)
        if not doc.has_frontmatter:
            issues.extend(
                [
                    {
                        "severity": "warning",
                        "code": "raw-missing-frontmatter",
                        "path": path_rel,
                    },
                ],
            )
            continue
        missing = sorted(RAW_REQUIRED - set(doc.frontmatter))
        issues.extend(
            {
                "severity": "warning",
                "code": "raw-missing-field",
                "path": path_rel,
                "field": key,
            }
            for key in missing
        )
        status = doc.frontmatter.get("status")
        if status and status not in ALLOWED_RAW_STATUS:
            issues.extend(
                [
                    {
                        "severity": "warning",
                        "code": "raw-invalid-status",
                        "path": path_rel,
                        "status": status,
                    },
                    ],
                )
    issues.extend(audit_lint_issues(wiki))
    result = {
        "issues": issues,
        "error_count": sum(1 for i in issues if i["severity"] == "error"),
        "warning_count": sum(1 for i in issues if i["severity"] == "warning"),
    }
    print_result(result, as_json=args.json)
    return 1 if result["error_count"] else 0


def extract_links(text: str) -> list[str]:
    """提取 Markdown wikilink 目标。

    Returns:
        wikilink 目标列表。

    """
    links = []
    for match in re.finditer(r"\[\[([^\]]+)\]\]", text):
        target = match.group(1).split("|", 1)[0].split("#", 1)[0].strip()
        if target:
            links.append(target)
    return links


def target_keys(path: Path, wiki: Path) -> set[str]:
    """生成页面可匹配的 wikilink key。

    Returns:
        可匹配 key 集合。

    """
    relative = relpath(path, wiki)
    no_ext = relative.removesuffix(".md")
    return {path.stem, no_ext, no_ext.replace("\\", "/")}


def command_links(args: argparse.Namespace) -> int:
    """执行断链检查命令。

    Returns:
        进程退出码。

    """
    wiki = find_llmwiki(Path(args.llmwiki))
    pages = [p for d in USER_DIRS for p in iter_markdown(wiki / d)]
    known = set()
    for page in pages:
        known.update(target_keys(page, wiki))
    broken = []
    for page in pages:
        broken.extend(
            {"path": relpath(page, wiki), "target": link}
            for link in extract_links(read_text(page))
            if link not in known
        )
    print_result({"broken": broken, "count": len(broken)}, as_json=args.json)
    return 1 if broken else 0


def command_index_check(args: argparse.Namespace) -> int:
    """执行 raw/index.md 完整性检查命令。

    Returns:
        进程退出码。

    """
    wiki = find_llmwiki(Path(args.llmwiki))
    index = wiki / "raw" / "index.md"
    index_text = read_text(index) if index.exists() else ""
    missing = []
    pages = [p for d in USER_DIRS for p in iter_markdown(wiki / d)]
    for page in pages:
        stem = page.stem
        relative = relpath(page, wiki).removesuffix(".md")
        if f"[[{stem}]]" not in index_text and f"[[{relative}]]" not in index_text:
            missing.append(relpath(page, wiki))
    stale = [
        link
        for link in extract_links(index_text)
        if not any(link in target_keys(page, wiki) for page in pages)
    ]
    result = {"missing_entries": missing, "stale_entries": stale}
    print_result(result, as_json=args.json)
    return 1 if missing or stale else 0


def log_headings(log_text: str) -> list[str]:
    """提取日志二级标题。

    Returns:
        日志二级标题列表。

    """
    return re.findall(r"^##\s+\[", log_text, flags=re.MULTILINE)


def daily_log_path(wiki: Path, day: str | None = None) -> Path:
    """返回某日 raw/log 日志路径。"""
    if day is None:
        day = datetime.now().strftime("%Y%m%d")
    return wiki / "raw" / "log" / f"{day}.md"


def ensure_daily_log(wiki: Path, day: str | None = None) -> Path:
    """确保某日 raw/log/YYYYMMDD.md 存在。"""
    path = daily_log_path(wiki, day)
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    compact = path.stem
    iso = f"{compact[:4]}-{compact[4:6]}-{compact[6:8]}"
    write_text(path, f"# {iso}\n\n")
    return path


def append_log_entry(wiki: Path, action: str, subject: str, body_lines: list[str]) -> Path:
    """追加一条今日操作日志。"""
    path = ensure_daily_log(wiki)
    now_hm = datetime.now().strftime("%H:%M")
    lines = ["", f"## [{now_hm}] {action} | {subject}", ""]
    lines.extend(body_lines)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines).rstrip() + "\n")
    return path


def iter_log_files(wiki: Path) -> list[Path]:
    """列出 raw/log 下的日志文件。"""
    log_dir = wiki / "raw" / "log"
    if not log_dir.exists():
        return []
    return sorted(p for p in log_dir.glob("*.md") if p.is_file())


def command_log_status(args: argparse.Namespace) -> int:
    """执行日志状态检查命令。

    Returns:
        进程退出码。

    """
    wiki = find_llmwiki(Path(args.llmwiki))
    legacy_log = wiki / "raw" / "log.md"
    files = iter_log_files(wiki)
    entries_by_file = []
    invalid_files = []
    count = 0
    for path in files:
        text = read_text(path)
        entries = len(log_headings(text))
        count += entries
        expected_h1 = f"# {path.stem[:4]}-{path.stem[4:6]}-{path.stem[6:8]}"
        first_line = text.splitlines()[0].strip() if text.splitlines() else ""
        if not re.fullmatch(r"\d{8}\.md", path.name) or first_line != expected_h1:
            invalid_files.append(relpath(path, wiki))
        entries_by_file.append({"path": relpath(path, wiki), "entries": entries})
    result = {
        "path": "raw/log/",
        "entries": count,
        "files": entries_by_file,
        "invalid_files": invalid_files,
        "legacy_log": relpath(legacy_log, wiki) if legacy_log.exists() else None,
        "needs_migrate": legacy_log.exists(),
    }
    print_result(result, as_json=args.json)
    return 1 if invalid_files else 0


def split_legacy_log(text: str) -> dict[str, list[str]]:
    """把旧 raw/log.md 按日期分组。"""
    grouped: dict[str, list[str]] = {}
    current_date: str | None = None
    current_lines: list[str] = []
    for line in normalize_newlines(text).splitlines():
        match = re.match(r"^##\s+\[(\d{4}-\d{2}-\d{2}|YYYY-MM-DD)\]\s*(.*)$", line)
        if match:
            if current_date and current_lines:
                grouped.setdefault(current_date, []).extend(current_lines)
            current_date = match.group(1)
            suffix = match.group(2).strip()
            if current_date == "YYYY-MM-DD":
                current_date = datetime.now().date().isoformat()
            current_lines = [f"## [00:00] {suffix}" if suffix else "## [00:00] update | legacy"]
            continue
        if current_date:
            current_lines.append(line)
    if current_date and current_lines:
        grouped.setdefault(current_date, []).extend(current_lines)
    return grouped


def command_log_migrate(args: argparse.Namespace) -> int:
    """把旧 raw/log.md 迁移到 raw/log/YYYYMMDD.md。

    Returns:
        进程退出码。

    """
    wiki = find_llmwiki(Path(args.llmwiki))
    legacy_log = wiki / "raw" / "log.md"
    if not legacy_log.exists():
        print_result(
            {"migrated": False, "reason": "legacy-log-missing"},
            as_json=args.json,
        )
        return 0
    grouped = split_legacy_log(read_text(legacy_log))
    if not grouped:
        today = datetime.now().date().isoformat()
        grouped[today] = [
            "## [00:00] update | legacy-log",
            "",
            "- 旧日志没有可识别条目，保留原文件归档。",
        ]
    written = []
    for iso_date, lines in grouped.items():
        compact = iso_date.replace("-", "")
        path = ensure_daily_log(wiki, compact)
        existing = read_text(path)
        content = "\n".join(line.rstrip() for line in lines).strip() + "\n"
        if content.strip() not in existing:
            with path.open("a", encoding="utf-8", newline="\n") as handle:
                if not existing.endswith("\n\n"):
                    handle.write("\n")
                handle.write(content)
        written.append(relpath(path, wiki))
    archive = wiki / "raw" / "_archive" / "log.md"
    if archive.exists():
        suffix = datetime.now().strftime("%Y%m%d%H%M%S")
        archive = wiki / "raw" / "_archive" / f"log-{suffix}.md"
    if not args.keep_legacy:
        archive.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(legacy_log), str(archive))
    append_log_entry(
        wiki,
        "update",
        "日志迁移",
        [
            "- 已将旧 `raw/log.md` 迁移到 `raw/log/YYYYMMDD.md`。",
            f"- 迁移文件数: {len(set(written))}",
            f"- 旧日志归档: `{relpath(archive, wiki)}`" if not args.keep_legacy else "- 保留旧 `raw/log.md`。",
        ],
    )
    print_result(
        {
            "migrated": True,
            "files": sorted(set(written)),
            "archive": relpath(archive, wiki) if not args.keep_legacy else None,
        },
        as_json=args.json,
    )
    return 0


def parse_markdown_table(text: str) -> tuple[list[str], list[list[str]]]:
    """解析简单 Markdown 表格。

    Returns:
        表头和数据行。

    """
    lines = [line.strip() for line in text.splitlines() if line.strip().startswith("|")]
    if len(lines) < MARKDOWN_TABLE_MIN_LINES:
        return [], []
    header = [cell.strip() for cell in lines[0].strip("|").split("|")]
    rows = []
    for line in lines[2:]:
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) == len(header):
            rows.append(cells)
    return header, rows


def profile_rows(header: list[str], rows: list[list[str]]) -> dict[str, Any]:
    """生成表格字段 profile。

    Returns:
        表格 profile 字典。

    """
    fields = []
    for index, name in enumerate(header):
        values = [row[index] for row in rows if index < len(row)]
        non_empty = [
            value
            for value in values
            if value and value.lower() not in {"nan", "null", "none"}
        ]
        samples = []
        for value in non_empty:
            if value not in samples:
                samples.append(value)
            if len(samples) >= MAX_PROFILE_SAMPLES:
                break
        fields.append(
            {
                "name": name,
                "non_empty": len(non_empty),
                "missing": len(values) - len(non_empty),
                "unique_sample_count": len(set(non_empty[:100])),
                "samples": samples,
            },
        )
    return {"columns": len(header), "rows": len(rows), "fields": fields}


def render_profile(profile: dict[str, Any], source: str) -> str:
    """把表格 profile 渲染成 Markdown。

    Returns:
        Markdown profile 文本。

    """
    lines = [
        f"# 表格 Profile: {Path(source).name}",
        "",
        f"- 来源: `{source}`",
        f"- 行数: {profile['rows']}",
        f"- 列数: {profile['columns']}",
        "",
        "## 字段",
    ]
    for field in profile["fields"]:
        samples = "; ".join(field["samples"])
        lines.append(
            (
                f"- `{field['name']}`: 非空 {field['non_empty']}, "
                f"缺失 {field['missing']}, 样例: {samples}"
            ),
        )
    return "\n".join(lines) + "\n"


def command_table_profile(args: argparse.Namespace) -> int:
    """执行表格 profile 命令。

    Returns:
        进程退出码。

    Raises:
        ToolError: 表格格式不支持或缺少可选依赖时抛出。

    """
    path = Path(args.file)
    ext = path.suffix.lower()
    if ext == ".csv":
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.reader(handle))
        header, body = rows[0] if rows else [], rows[1:] if len(rows) > 1 else []
    elif ext == ".tsv":
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.reader(handle, delimiter="\t"))
        header, body = rows[0] if rows else [], rows[1:] if len(rows) > 1 else []
    elif ext in {".md", ".markdown"}:
        header, body = parse_markdown_table(read_text(path))
    elif ext in {".xls", ".xlsx"}:
        try:
            pandas_module = importlib.import_module("pandas")
        except ImportError as exc:
            msg = (
                "当前环境没有 pandas/openpyxl。请先用 markitdown 转成 Markdown, "
                "或用 `uv run --with pandas --with openpyxl ... "
                "table-profile file.xlsx`。"
            )
            raise ToolError(
                msg,
            ) from exc
        frame = pandas_module.read_excel(path)
        header = [str(item) for item in frame.columns]
        body = [
            [str(value) for value in row]
            for row in frame.head(args.max_rows).to_numpy().tolist()
        ]
    else:
        msg = f"暂不支持的表格格式: {ext}"
        raise ToolError(msg)
    if args.max_rows and len(body) > args.max_rows:
        body = body[: args.max_rows]
    profile = profile_rows(header, body)
    profile["source"] = str(path)
    if args.output:
        write_text(Path(args.output), render_profile(profile, str(path)))
    print_result(
        profile if args.json else render_profile(profile, str(path)),
        as_json=args.json,
    )
    return 0


def load_plan(path: Path) -> dict[str, Any]:
    """读取并校验 plan JSON。

    Returns:
        plan 字典。

    Raises:
        ToolError: plan JSON 无效时抛出。

    """
    try:
        data = json.loads(read_text(path))
    except json.JSONDecodeError as exc:
        msg = f"plan JSON 无效: {exc}"
        raise ToolError(msg) from exc
    if not isinstance(data, dict) or not isinstance(data.get("operations"), list):
        msg = "plan 必须是对象, 并包含 operations 数组。"
        raise ToolError(msg)
    return data


def validate_operation(root: Path, op: dict[str, Any]) -> dict[str, Any]:
    """校验并补全单个 plan operation。

    Returns:
        规范化后的 operation。

    Raises:
        ToolError: operation 无效时抛出。

    """
    if not isinstance(op, dict) or "op" not in op:
        msg = "operation 必须是对象并包含 op。"
        raise ToolError(msg)
    kind = op["op"]
    normalized = dict(op)
    if kind in {"write_file", "append_file", "replace_text", "update_frontmatter"}:
        path_value = op.get("path")
        if not isinstance(path_value, str):
            msg = f"{kind} 缺少 path。"
            raise ToolError(msg)
        safe_path(root, path_value)
    if kind in {"append_index_entry", "remove_index_entry"}:
        path_value = op.get("path", "raw/index.md")
        if not isinstance(path_value, str):
            msg = f"{kind} 的 path 必须是字符串。"
            raise ToolError(msg)
        normalized["path"] = path_value
        safe_path(root, path_value)
    if kind == "move":
        for key in ["from", "to"]:
            if not isinstance(op.get(key), str):
                msg = "move 缺少 from/to。"
                raise ToolError(msg)
            safe_path(root, op[key])
    if kind == "archive":
        if not isinstance(op.get("path"), str):
            msg = "archive 缺少 path。"
            raise ToolError(msg)
        safe_path(root, op["path"])
    if kind == "replace_text" and (
        not isinstance(op.get("find"), str) or not isinstance(op.get("replace"), str)
    ):
        msg_0 = "replace_text 需要 find 和 replace。"
        raise ToolError(msg_0)
    if kind == "update_frontmatter" and not isinstance(op.get("set"), dict):
        msg_0 = "update_frontmatter 需要 set 对象。"
        raise ToolError(msg_0)
    if kind not in {
        "write_file",
        "append_file",
        "replace_text",
        "update_frontmatter",
        "move",
        "archive",
        "append_index_entry",
        "remove_index_entry",
    }:
        msg = f"不支持的 op: {kind}"
        raise ToolError(msg)
    return normalized


def plan_root(plan_path: Path, explicit: str | None) -> Path:
    """定位 plan 对应的 llmwiki 根目录。

    Returns:
        llmwiki 根目录路径。

    """
    if explicit:
        return find_llmwiki(Path(explicit))
    return find_llmwiki(plan_path)


def command_plan_validate(args: argparse.Namespace) -> int:
    """执行 plan 校验命令。

    Returns:
        进程退出码。

    """
    plan_path = Path(args.plan)
    root = plan_root(plan_path, args.llmwiki)
    plan = load_plan(plan_path)
    operations = [validate_operation(root, op) for op in plan["operations"]]
    result = {"valid": True, "llmwiki": str(root), "operation_count": len(operations)}
    print_result(result, as_json=args.json)
    return 0


def apply_operation(
    root: Path,
    op: dict[str, Any],
    *,
    dry_run: bool,
) -> dict[str, Any]:
    """执行单个 plan operation。

    Returns:
        操作结果摘要。

    Raises:
        ToolError: 操作无法安全执行时抛出。

    """
    kind = op["op"]
    if kind == "write_file":
        path = safe_path(root, op["path"])
        content = str(op.get("content", ""))
        if not dry_run:
            write_text(path, content)
        return {
            "op": kind,
            "path": relpath(path, root),
            "bytes": len(content.encode("utf-8")),
        }
    if kind == "append_file":
        path = safe_path(root, op["path"])
        content = str(op.get("content", ""))
        if not dry_run:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("a", encoding="utf-8", newline="\n") as handle:
                handle.write(content)
        return {
            "op": kind,
            "path": relpath(path, root),
            "bytes": len(content.encode("utf-8")),
        }
    if kind == "replace_text":
        path = safe_path(root, op["path"])
        text = read_text(path)
        count = text.count(op["find"])
        if count != 1:
            msg = f"replace_text 要求唯一命中, 实际 {count} 次: {op['path']}"
            raise ToolError(msg)
        if not dry_run:
            write_text(path, text.replace(op["find"], op["replace"], 1))
        return {"op": kind, "path": relpath(path, root), "matches": count}
    if kind == "update_frontmatter":
        path = safe_path(root, op["path"])
        doc = parse_markdown(read_text(path))
        frontmatter = dict(doc.frontmatter)
        frontmatter.update(op["set"])
        if not dry_run:
            write_text(path, render_frontmatter(frontmatter, doc.body))
        return {
            "op": kind,
            "path": relpath(path, root),
            "set": sorted(op["set"].keys()),
        }
    if kind == "move":
        src = safe_path(root, op["from"])
        dst = safe_path(root, op["to"])
        if not dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(src), str(dst))
        return {"op": kind, "from": relpath(src, root), "to": relpath(dst, root)}
    if kind == "archive":
        src = safe_path(root, op["path"])
        dst = root / "raw" / "_archive" / relpath(src, root)
        if not dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(src), str(dst))
        return {"op": kind, "from": relpath(src, root), "to": relpath(dst, root)}
    if kind == "append_index_entry":
        path = safe_path(root, op.get("path", "raw/index.md"))
        entry = str(op.get("entry", ""))
        if not entry.endswith("\n"):
            entry += "\n"
        if not dry_run:
            with path.open("a", encoding="utf-8", newline="\n") as handle:
                handle.write(entry)
        return {"op": kind, "path": relpath(path, root), "entry": entry.strip()}
    if kind == "remove_index_entry":
        path = safe_path(root, op.get("path", "raw/index.md"))
        text = read_text(path)
        entry = str(op.get("entry", ""))
        count = text.count(entry)
        if count != 1:
            msg = f"remove_index_entry 要求唯一命中, 实际 {count} 次。"
            raise ToolError(msg)
        if not dry_run:
            write_text(path, text.replace(entry, "", 1))
        return {"op": kind, "path": relpath(path, root), "matches": count}
    msg = f"不支持的 op: {kind}"
    raise ToolError(msg)


def append_apply_log(
    root: Path,
    plan_path: Path,
    applied: list[dict[str, Any]],
    *,
    dry_run: bool,
) -> None:
    """追加 apply-plan 日志。"""
    if dry_run:
        return
    plan_display = (
        relpath(plan_path, root)
        if root.resolve() in plan_path.resolve().parents
        else plan_path
    )
    append_log_entry(root, "update", "apply-plan", [
        f"- Plan: `{plan_display}`",
        f"- 操作数: {len(applied)}",
    ])


def command_apply_plan(args: argparse.Namespace) -> int:
    """执行 plan 应用命令。

    Returns:
        进程退出码。

    """
    plan_path = Path(args.plan).resolve()
    root = plan_root(plan_path, args.llmwiki)
    plan = load_plan(plan_path)
    operations = [validate_operation(root, op) for op in plan["operations"]]
    dry_run = not args.yes
    applied = [apply_operation(root, op, dry_run=dry_run) for op in operations]
    append_apply_log(root, plan_path, applied, dry_run=dry_run)
    if not dry_run and root in plan_path.parents:
        applied_dir = root / "raw" / "plans" / "applied"
        applied_dir.mkdir(parents=True, exist_ok=True)
        target = applied_dir / plan_path.name
        if target.exists():
            suffix = datetime.now(UTC).strftime("%Y%m%d%H%M%S")
            target = applied_dir / f"{plan_path.stem}-{suffix}{plan_path.suffix}"
        shutil.move(str(plan_path), str(target))
    print_result(
        {"dry_run": dry_run, "operation_count": len(applied), "operations": applied},
        as_json=args.json,
    )
    return 0


def command_audit_review(args: argparse.Namespace) -> int:
    """按目标文件分组列出 audit。"""
    wiki = find_llmwiki(Path(args.llmwiki))
    files = audit_files(wiki, args.mode)
    grouped: dict[str, list[dict[str, Any]]] = {}
    severity_order = {"error": 0, "warn": 1, "suggest": 2, "info": 3}
    for path in files:
        text = read_text(path)
        doc = parse_markdown(text)
        target = str(doc.frontmatter.get("target", "(no-target)"))
        grouped.setdefault(target, []).append(
            {
                "path": relpath(path, wiki),
                "id": doc.frontmatter.get("id", path.stem),
                "severity": doc.frontmatter.get("severity", "info"),
                "status": doc.frontmatter.get("status", audit_expected_status(path)),
                "author": doc.frontmatter.get("author", ""),
                "created": doc.frontmatter.get("created", ""),
                "comment": audit_comment_one_line(text),
            },
        )
    for entries in grouped.values():
        entries.sort(
            key=lambda item: (
                severity_order.get(str(item["severity"]), 99),
                str(item["created"]),
            ),
        )
    result = {
        "mode": args.mode,
        "total": sum(len(entries) for entries in grouped.values()),
        "targets": grouped,
    }
    print_result(result, as_json=args.json)
    return 0


def command_audit_anchor(args: argparse.Namespace) -> int:
    """解析 audit 锚点到当前目标文件位置。"""
    wiki = find_llmwiki(Path(args.llmwiki))
    audit_path = safe_path(wiki, args.audit_file)
    doc = parse_markdown(read_text(audit_path))
    target = doc.frontmatter.get("target")
    if not isinstance(target, str):
        raise ToolError("audit 文件缺少 target。")
    target_path = resolve_audit_target(wiki, target)
    if not target_path:
        raise ToolError(f"audit target 不存在: {target}")
    resolved = resolve_audit_anchor(read_text(target_path), doc.frontmatter)
    result = {
        "audit": relpath(audit_path, wiki),
        "target": relpath(target_path, wiki),
        "anchor": resolved or {"resolved": False},
    }
    print_result(result, as_json=args.json)
    return 0 if resolved else 1


def build_parser() -> argparse.ArgumentParser:
    """构建命令行解析器。

    Returns:
        argparse 解析器。

    """
    parser = argparse.ArgumentParser(description="LLM Wiki 确定性辅助工具")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("hash")
    p.add_argument("file")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_hash)

    p = sub.add_parser("verify-hash")
    p.add_argument("llmwiki")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_verify_hash)

    p = sub.add_parser("inventory")
    p.add_argument("folder")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_inventory)

    p = sub.add_parser("lint")
    p.add_argument("llmwiki")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_lint)

    p = sub.add_parser("links")
    p.add_argument("llmwiki")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_links)

    p = sub.add_parser("index-check")
    p.add_argument("llmwiki")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_index_check)

    p = sub.add_parser("log-status")
    p.add_argument("llmwiki")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_log_status)

    p = sub.add_parser("log-migrate")
    p.add_argument("llmwiki")
    p.add_argument("--keep-legacy", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_log_migrate)

    p = sub.add_parser("log-rotate", help="兼容旧命令; 等同于 log-migrate")
    p.add_argument("llmwiki")
    p.add_argument("--keep-legacy", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_log_migrate)

    p = sub.add_parser("table-profile")
    p.add_argument("file")
    p.add_argument("-o", "--output")
    p.add_argument("--max-rows", type=int, default=200)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_table_profile)

    p = sub.add_parser("plan-validate")
    p.add_argument("plan")
    p.add_argument("--llmwiki")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_plan_validate)

    p = sub.add_parser("apply-plan")
    p.add_argument("plan")
    p.add_argument("--llmwiki")
    p.add_argument("--yes", action="store_true", help="实际写入文件; 默认只 dry-run")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_apply_plan)

    p = sub.add_parser("audit-review")
    p.add_argument("llmwiki")
    p.add_argument("--mode", choices=["open", "resolved", "all"], default="open")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_audit_review)

    p = sub.add_parser("audit-anchor")
    p.add_argument("llmwiki")
    p.add_argument("audit_file")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_audit_anchor)
    return parser


def main(argv: list[str] | None = None) -> int:
    """命令行入口。

    Returns:
        进程退出码。

    """
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ToolError as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return COMMAND_ERROR


if __name__ == "__main__":
    raise SystemExit(main())

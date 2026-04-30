#!/usr/bin/env python3
"""one_build LLM Wiki 工作流的确定性辅助工具。"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Any

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
TEXT_EXTENSIONS = {".md", ".txt", ".csv", ".json", ".xml", ".html", ".htm"}
DOCUMENT_EXTENSIONS = {".pdf", ".doc", ".docx", ".rtf"}
SLIDE_EXTENSIONS = {".ppt", ".pptx", ".key"}
TABLE_EXTENSIONS = {".xls", ".xlsx", ".csv", ".tsv"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff"}
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".aac", ".flac", ".ogg"}
ARCHIVE_EXTENSIONS = {".zip", ".7z", ".rar", ".tar", ".gz"}


class ToolError(Exception):
    """面向命令行用户的可读错误。"""

    pass


@dataclass
class MarkdownDoc:
    frontmatter: dict[str, Any]
    body: str
    has_frontmatter: bool


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def parse_scalar(value: str) -> Any:
    value = value.strip()
    if value == "":
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
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    try:
        if "." in value:
            return float(value)
        return int(value)
    except ValueError:
        return value


def parse_simple_frontmatter(raw: str) -> dict[str, Any]:
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
        if value == "":
            result[key] = ""
        else:
            result[key] = parse_scalar(value)
        current_key = key
    return result


def parse_markdown(text: str) -> MarkdownDoc:
    text = normalize_newlines(text)
    match = re.match(r"^---\n(.*?)\n---\n?", text, flags=re.S)
    if not match:
        return MarkdownDoc({}, text, False)
    frontmatter = parse_simple_frontmatter(match.group(1))
    return MarkdownDoc(frontmatter, text[match.end() :], True)


def yaml_value(value: Any) -> str:
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
    if text == "" or any(ch in text for ch in [":", "#", "[", "]", "{", "}", ","]):
        return json.dumps(text, ensure_ascii=False)
    return text


def render_frontmatter(frontmatter: dict[str, Any], body: str) -> str:
    lines = ["---"]
    for key, value in frontmatter.items():
        lines.append(f"{key}: {yaml_value(value)}")
    lines.extend(["---", ""])
    return "\n".join(lines) + body.lstrip("\n")


def body_sha256(text: str) -> str:
    doc = parse_markdown(text)
    body = normalize_newlines(doc.body)
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def find_llmwiki(path: Path) -> Path:
    current = path.resolve()
    if current.is_file():
        current = current.parent
    for candidate in [current, *current.parents]:
        if candidate.name == "llmwiki" and (candidate / "raw").is_dir():
            return candidate
        nested = candidate / "llmwiki"
        if (nested / "raw").is_dir():
            return nested
    raise ToolError("无法定位 llmwiki 目录；请传入 llmwiki 路径或其内部文件路径。")


def relpath(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def safe_path(root: Path, value: str) -> Path:
    candidate = (root / value).resolve()
    root_resolved = root.resolve()
    if candidate != root_resolved and root_resolved not in candidate.parents:
        raise ToolError(f"路径越界：{value}")
    if candidate.as_posix().endswith("/raw/tools/llmwiki_tool.py"):
        raise ToolError("禁止通过 plan 修改 llmwiki_tool.py")
    return candidate


def print_result(data: Any, as_json: bool) -> None:
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return
    if isinstance(data, str):
        print(data)
    else:
        print(json.dumps(data, ensure_ascii=False, indent=2))


def command_hash(args: argparse.Namespace) -> int:
    path = Path(args.file)
    digest = body_sha256(read_text(path))
    print_result({"file": str(path), "sha256": digest}, args.json)
    return 0


def iter_markdown(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*.md") if path.is_file())


def command_verify_hash(args: argparse.Namespace) -> int:
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
        results.append({
            "path": relpath(path, wiki),
            "status": status,
            "expected": expected,
            "actual": actual,
        })
    summary = {
        "checked": len(results),
        "mismatches": [item for item in results if item["status"] != "ok"],
        "results": results,
    }
    print_result(summary, args.json)
    return 1 if summary["mismatches"] else 0


def classify_file(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in DOCUMENT_EXTENSIONS:
        return "document"
    if ext in SLIDE_EXTENSIONS:
        return "slide"
    if ext in TABLE_EXTENSIONS:
        return "table"
    if ext in IMAGE_EXTENSIONS:
        return "image"
    if ext in AUDIO_EXTENSIONS:
        return "audio"
    if ext in ARCHIVE_EXTENSIONS:
        return "archive"
    if ext in TEXT_EXTENSIONS:
        return "text"
    return "asset"


def command_inventory(args: argparse.Namespace) -> int:
    root = Path(args.folder)
    if not root.exists():
        raise ToolError(f"目录不存在：{root}")
    groups: dict[str, list[dict[str, Any]]] = {}
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        kind = classify_file(path)
        groups.setdefault(kind, []).append({
            "path": str(path),
            "name": path.name,
            "extension": path.suffix.lower(),
            "bytes": path.stat().st_size,
        })
    summary = {
        "root": str(root),
        "total": sum(len(items) for items in groups.values()),
        "groups": groups,
    }
    print_result(summary, args.json)
    return 0


def schema_tags(wiki: Path) -> set[str]:
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


def command_lint(args: argparse.Namespace) -> int:
    wiki = find_llmwiki(Path(args.llmwiki))
    allowed_tags = schema_tags(wiki)
    issues = []
    for dirname in USER_DIRS:
        for path in iter_markdown(wiki / dirname):
            doc = parse_markdown(read_text(path))
            path_rel = relpath(path, wiki)
            if not doc.has_frontmatter:
                issues.append({"severity": "error", "code": "missing-frontmatter", "path": path_rel})
                continue
            missing = sorted(PAGE_REQUIRED - set(doc.frontmatter))
            for key in missing:
                issues.append({"severity": "error", "code": "missing-field", "path": path_rel, "field": key})
            expected_type = TYPE_BY_DIR[dirname]
            actual_type = doc.frontmatter.get("type")
            if actual_type and actual_type != expected_type:
                issues.append({
                    "severity": "warning",
                    "code": "type-mismatch",
                    "path": path_rel,
                    "expected": expected_type,
                    "actual": actual_type,
                })
            tags = doc.frontmatter.get("tags", [])
            if isinstance(tags, str):
                tags = [tags]
            for tag in tags if isinstance(tags, list) else []:
                if allowed_tags and tag not in allowed_tags:
                    issues.append({"severity": "warning", "code": "unknown-tag", "path": path_rel, "tag": tag})
    for path in iter_markdown(wiki / "raw"):
        if "raw/tools" in relpath(path, wiki) or path.name in {"AGENTS.md", "SCHEMA.md", "index.md", "log.md"}:
            continue
        doc = parse_markdown(read_text(path))
        path_rel = relpath(path, wiki)
        if not doc.has_frontmatter:
            issues.append({"severity": "warning", "code": "raw-missing-frontmatter", "path": path_rel})
            continue
        missing = sorted(RAW_REQUIRED - set(doc.frontmatter))
        for key in missing:
            issues.append({"severity": "warning", "code": "raw-missing-field", "path": path_rel, "field": key})
        status = doc.frontmatter.get("status")
        if status and status not in ALLOWED_RAW_STATUS:
            issues.append({"severity": "warning", "code": "raw-invalid-status", "path": path_rel, "status": status})
    result = {
        "issues": issues,
        "error_count": sum(1 for i in issues if i["severity"] == "error"),
        "warning_count": sum(1 for i in issues if i["severity"] == "warning"),
    }
    print_result(result, args.json)
    return 1 if result["error_count"] else 0


def extract_links(text: str) -> list[str]:
    links = []
    for match in re.finditer(r"\[\[([^\]]+)\]\]", text):
        target = match.group(1).split("|", 1)[0].split("#", 1)[0].strip()
        if target:
            links.append(target)
    return links


def target_keys(path: Path, wiki: Path) -> set[str]:
    relative = relpath(path, wiki)
    no_ext = relative[:-3] if relative.endswith(".md") else relative
    return {path.stem, no_ext, no_ext.replace("\\", "/")}


def command_links(args: argparse.Namespace) -> int:
    wiki = find_llmwiki(Path(args.llmwiki))
    pages = [p for d in USER_DIRS for p in iter_markdown(wiki / d)]
    known = set()
    for page in pages:
        known.update(target_keys(page, wiki))
    broken = []
    for page in pages:
        for link in extract_links(read_text(page)):
            if link not in known:
                broken.append({"path": relpath(page, wiki), "target": link})
    print_result({"broken": broken, "count": len(broken)}, args.json)
    return 1 if broken else 0


def command_index_check(args: argparse.Namespace) -> int:
    wiki = find_llmwiki(Path(args.llmwiki))
    index = wiki / "raw" / "index.md"
    index_text = read_text(index) if index.exists() else ""
    missing = []
    stale = []
    pages = [p for d in USER_DIRS for p in iter_markdown(wiki / d)]
    for page in pages:
        stem = page.stem
        relative = relpath(page, wiki)[:-3]
        if f"[[{stem}]]" not in index_text and f"[[{relative}]]" not in index_text:
            missing.append(relpath(page, wiki))
    for link in extract_links(index_text):
        if not any(link in target_keys(page, wiki) for page in pages):
            stale.append(link)
    result = {"missing_entries": missing, "stale_entries": stale}
    print_result(result, args.json)
    return 1 if missing or stale else 0


def log_headings(log_text: str) -> list[str]:
    return re.findall(r"^##\s+\[", log_text, flags=re.M)


def command_log_status(args: argparse.Namespace) -> int:
    wiki = find_llmwiki(Path(args.llmwiki))
    log = wiki / "raw" / "log.md"
    text = read_text(log) if log.exists() else ""
    count = len(log_headings(text))
    result = {
        "path": relpath(log, wiki),
        "entries": count,
        "threshold": args.threshold,
        "needs_rotate": count > args.threshold,
    }
    print_result(result, args.json)
    return 0


def command_log_rotate(args: argparse.Namespace) -> int:
    wiki = find_llmwiki(Path(args.llmwiki))
    log = wiki / "raw" / "log.md"
    text = read_text(log)
    count = len(log_headings(text))
    if count <= args.threshold and not args.force:
        print_result({"rotated": False, "entries": count, "reason": "below-threshold"}, args.json)
        return 0
    year = str(date.today().year)
    archive = wiki / "raw" / f"log-{year}.md"
    if archive.exists():
        suffix = datetime.now().strftime("%Y%m%d%H%M%S")
        archive = wiki / "raw" / f"log-{year}-{suffix}.md"
    shutil.move(str(log), str(archive))
    write_text(
        log,
        "# Wiki 日志\n\n> 追加式记录知识库操作。\n> 旧日志：`"
        + relpath(archive, wiki)
        + "`\n\n## ["
        + date.today().isoformat()
        + "] archive | 日志轮转\n\n- 已轮转旧日志。\n",
    )
    print_result({"rotated": True, "archive": relpath(archive, wiki), "entries": count}, args.json)
    return 0


def parse_markdown_table(text: str) -> tuple[list[str], list[list[str]]]:
    lines = [line.strip() for line in text.splitlines() if line.strip().startswith("|")]
    if len(lines) < 2:
        return [], []
    header = [cell.strip() for cell in lines[0].strip("|").split("|")]
    rows = []
    for line in lines[2:]:
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) == len(header):
            rows.append(cells)
    return header, rows


def profile_rows(header: list[str], rows: list[list[str]]) -> dict[str, Any]:
    fields = []
    for index, name in enumerate(header):
        values = [row[index] for row in rows if index < len(row)]
        non_empty = [value for value in values if value and value.lower() not in {"nan", "null", "none"}]
        samples = []
        for value in non_empty:
            if value not in samples:
                samples.append(value)
            if len(samples) >= 5:
                break
        fields.append({
            "name": name,
            "non_empty": len(non_empty),
            "missing": len(values) - len(non_empty),
            "unique_sample_count": len(set(non_empty[:100])),
            "samples": samples,
        })
    return {"columns": len(header), "rows": len(rows), "fields": fields}


def render_profile(profile: dict[str, Any], source: str) -> str:
    lines = [
        f"# 表格 Profile：{Path(source).name}",
        "",
        f"- 来源：`{source}`",
        f"- 行数：{profile['rows']}",
        f"- 列数：{profile['columns']}",
        "",
        "## 字段",
    ]
    for field in profile["fields"]:
        samples = "；".join(field["samples"])
        lines.append(f"- `{field['name']}`：非空 {field['non_empty']}，缺失 {field['missing']}，样例：{samples}")
    return "\n".join(lines) + "\n"


def command_table_profile(args: argparse.Namespace) -> int:
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
            import pandas as pd  # type: ignore
        except ImportError as exc:
            raise ToolError(
                "当前环境没有 pandas/openpyxl。请先用 markitdown 转成 Markdown，或用 `uv run --with pandas --with openpyxl ... table-profile file.xlsx`。"
            ) from exc
        frame = pd.read_excel(path)
        header = [str(item) for item in frame.columns]
        body = [[str(value) for value in row] for row in frame.head(args.max_rows).values.tolist()]
    else:
        raise ToolError(f"暂不支持的表格格式：{ext}")
    if args.max_rows and len(body) > args.max_rows:
        body = body[: args.max_rows]
    profile = profile_rows(header, body)
    profile["source"] = str(path)
    if args.output:
        write_text(Path(args.output), render_profile(profile, str(path)))
    print_result(profile if args.json else render_profile(profile, str(path)), args.json)
    return 0


def load_plan(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(read_text(path))
    except json.JSONDecodeError as exc:
        raise ToolError(f"plan JSON 无效：{exc}") from exc
    if not isinstance(data, dict) or not isinstance(data.get("operations"), list):
        raise ToolError("plan 必须是对象，并包含 operations 数组。")
    return data


def validate_operation(root: Path, op: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(op, dict) or "op" not in op:
        raise ToolError("operation 必须是对象并包含 op。")
    kind = op["op"]
    normalized = dict(op)
    if kind in {"write_file", "append_file", "replace_text", "update_frontmatter"}:
        path_value = op.get("path")
        if not isinstance(path_value, str):
            raise ToolError(f"{kind} 缺少 path。")
        safe_path(root, path_value)
    if kind in {"append_index_entry", "remove_index_entry"}:
        path_value = op.get("path", "raw/index.md")
        if not isinstance(path_value, str):
            raise ToolError(f"{kind} 的 path 必须是字符串。")
        normalized["path"] = path_value
        safe_path(root, path_value)
    if kind in {"move"}:
        for key in ["from", "to"]:
            if not isinstance(op.get(key), str):
                raise ToolError("move 缺少 from/to。")
            safe_path(root, op[key])
    if kind == "archive":
        if not isinstance(op.get("path"), str):
            raise ToolError("archive 缺少 path。")
        safe_path(root, op["path"])
    if kind == "replace_text":
        if not isinstance(op.get("find"), str) or not isinstance(op.get("replace"), str):
            raise ToolError("replace_text 需要 find 和 replace。")
    if kind == "update_frontmatter":
        if not isinstance(op.get("set"), dict):
            raise ToolError("update_frontmatter 需要 set 对象。")
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
        raise ToolError(f"不支持的 op：{kind}")
    return normalized


def plan_root(plan_path: Path, explicit: str | None) -> Path:
    if explicit:
        return find_llmwiki(Path(explicit))
    return find_llmwiki(plan_path)


def command_plan_validate(args: argparse.Namespace) -> int:
    plan_path = Path(args.plan)
    root = plan_root(plan_path, args.llmwiki)
    plan = load_plan(plan_path)
    operations = [validate_operation(root, op) for op in plan["operations"]]
    result = {"valid": True, "llmwiki": str(root), "operation_count": len(operations)}
    print_result(result, args.json)
    return 0


def apply_operation(root: Path, op: dict[str, Any], dry_run: bool) -> dict[str, Any]:
    kind = op["op"]
    if kind == "write_file":
        path = safe_path(root, op["path"])
        content = str(op.get("content", ""))
        if not dry_run:
            write_text(path, content)
        return {"op": kind, "path": relpath(path, root), "bytes": len(content.encode("utf-8"))}
    if kind == "append_file":
        path = safe_path(root, op["path"])
        content = str(op.get("content", ""))
        if not dry_run:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("a", encoding="utf-8", newline="\n") as handle:
                handle.write(content)
        return {"op": kind, "path": relpath(path, root), "bytes": len(content.encode("utf-8"))}
    if kind == "replace_text":
        path = safe_path(root, op["path"])
        text = read_text(path)
        count = text.count(op["find"])
        if count != 1:
            raise ToolError(f"replace_text 要求唯一命中，实际 {count} 次：{op['path']}")
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
        return {"op": kind, "path": relpath(path, root), "set": sorted(op["set"].keys())}
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
            raise ToolError(f"remove_index_entry 要求唯一命中，实际 {count} 次。")
        if not dry_run:
            write_text(path, text.replace(entry, "", 1))
        return {"op": kind, "path": relpath(path, root), "matches": count}
    raise ToolError(f"不支持的 op：{kind}")


def append_apply_log(root: Path, plan_path: Path, applied: list[dict[str, Any]], dry_run: bool) -> None:
    if dry_run:
        return
    log = root / "raw" / "log.md"
    lines = [
        "",
        f"## [{date.today().isoformat()}] update | apply-plan",
        "",
        f"- Plan：`{relpath(plan_path, root) if root.resolve() in plan_path.resolve().parents else plan_path}`",
        f"- 操作数：{len(applied)}",
    ]
    with log.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def command_apply_plan(args: argparse.Namespace) -> int:
    plan_path = Path(args.plan).resolve()
    root = plan_root(plan_path, args.llmwiki)
    plan = load_plan(plan_path)
    operations = [validate_operation(root, op) for op in plan["operations"]]
    dry_run = not args.yes
    applied = [apply_operation(root, op, dry_run) for op in operations]
    append_apply_log(root, plan_path, applied, dry_run)
    if not dry_run and root in plan_path.parents:
        applied_dir = root / "raw" / "plans" / "applied"
        applied_dir.mkdir(parents=True, exist_ok=True)
        target = applied_dir / plan_path.name
        if target.exists():
            target = applied_dir / f"{plan_path.stem}-{datetime.now().strftime('%Y%m%d%H%M%S')}{plan_path.suffix}"
        shutil.move(str(plan_path), str(target))
    print_result({"dry_run": dry_run, "operation_count": len(applied), "operations": applied}, args.json)
    return 0


def build_parser() -> argparse.ArgumentParser:
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
    p.add_argument("--threshold", type=int, default=500)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_log_status)

    p = sub.add_parser("log-rotate")
    p.add_argument("llmwiki")
    p.add_argument("--threshold", type=int, default=500)
    p.add_argument("--force", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_log_rotate)

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
    p.add_argument("--yes", action="store_true", help="实际写入文件；默认只 dry-run")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=command_apply_plan)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ToolError as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env bash
set -euo pipefail

SKIP_OPEN_APPS=0
UPGRADE_TOOLS=0
REPO_ARCHIVE_URL="https://codeload.github.com/NothingToDooo/one_build/zip/refs/heads/main"
ONE_BUILD_REPO_ROOT=""

for arg in "$@"; do
  case "$arg" in
    --skip-open-apps)
      SKIP_OPEN_APPS=1
      ;;
    --upgrade-tools)
      UPGRADE_TOOLS=1
      ;;
    -h|--help)
      cat <<'EOF'
用法：bash ./setup.sh [--skip-open-apps] [--upgrade-tools]

安装或复用 Codex 应用、Obsidian、bun、uv、defuddle、MarkItDown 和 LLM Wiki 工作流模板。
Obsidian 仓库目录会通过 macOS 文件夹选择器指定。
EOF
      exit 0
      ;;
    *)
      echo "未知参数：$arg" >&2
      exit 2
      ;;
  esac
done

log() {
  printf '==> %s\n' "$1" >&2
}

warn() {
  printf '警告：%s\n' "$1" >&2
}

ensure_one_build_repo_root() {
  local archive_root
  local zip_path
  local repo_root

  if [[ -n "$ONE_BUILD_REPO_ROOT" && -d "$ONE_BUILD_REPO_ROOT" ]]; then
    return
  fi

  archive_root="$(mktemp -d "/tmp/one-build-repo.XXXXXX")"
  zip_path="$archive_root/one_build-main.zip"
  log "正在下载 one_build 安装资源包"
  curl -fL --connect-timeout 20 --max-time 180 --retry 2 --show-error -o "$zip_path" "$REPO_ARCHIVE_URL"
  ditto -x -k "$zip_path" "$archive_root"

  repo_root="$(find "$archive_root" -maxdepth 1 -type d -name 'one_build-*' | head -n 1)"
  if [[ -z "$repo_root" || ! -d "$repo_root" ]]; then
    echo "one_build 安装资源包解压后未找到仓库目录。" >&2
    exit 1
  fi

  ONE_BUILD_REPO_ROOT="$repo_root"
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "此脚本仅支持 macOS。Windows 请使用 setup.ps1。" >&2
    exit 1
  fi
}

refresh_path() {
  export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
}

ensure_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "缺少必需命令：$name" >&2
    exit 1
  fi
}

run_with_timeout() {
  local seconds="$1"
  shift
  local pid
  local watcher
  local status

  "$@" &
  pid="$!"
  (
    sleep "$seconds"
    if kill -0 "$pid" >/dev/null 2>&1; then
      warn "命令超过 ${seconds} 秒仍未完成，正在停止：$*"
      kill "$pid" >/dev/null 2>&1 || true
      sleep 2
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  ) &
  watcher="$!"

  if wait "$pid"; then
    status=0
  else
    status="$?"
  fi
  kill "$watcher" >/dev/null 2>&1 || true
  wait "$watcher" >/dev/null 2>&1 || true
  return "$status"
}

ensure_bun() {
  refresh_path
  if command -v bun >/dev/null 2>&1; then
    log "bun 已可用"
    return
  fi

  local installer
  installer="$(mktemp "/tmp/one-build-bun-install.XXXXXX.sh")"
  log "正在使用 Bun 官方安装器安装 bun"
  if ! curl -fL --connect-timeout 20 --max-time 180 --retry 2 --show-error -o "$installer" https://bun.sh/install; then
    echo "bun 安装器下载失败。请检查网络，稍后重试。" >&2
    exit 1
  fi
  if ! run_with_timeout 600 bash "$installer"; then
    echo "bun 安装超时或失败。请检查网络后重试，或先手动安装 bun 再重新运行脚本。" >&2
    exit 1
  fi
  refresh_path
  if ! command -v bun >/dev/null 2>&1; then
    echo "bun 安装已完成，但当前 PATH 中仍找不到 bun。" >&2
    exit 1
  fi
}

ensure_uv() {
  refresh_path
  if command -v uv >/dev/null 2>&1; then
    log "uv 已可用"
    return
  fi

  local installer
  installer="$(mktemp "/tmp/one-build-uv-install.XXXXXX.sh")"
  log "正在使用 Astral 官方安装器安装 uv"
  if ! curl -fL --connect-timeout 20 --max-time 180 --retry 2 --show-error -o "$installer" https://astral.sh/uv/install.sh; then
    echo "uv 安装器下载失败。请检查网络，稍后重试。" >&2
    exit 1
  fi
  if ! run_with_timeout 600 sh "$installer"; then
    echo "uv 安装超时或失败。请检查网络后重试。" >&2
    exit 1
  fi
  refresh_path
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv 安装已完成，但当前 PATH 中仍找不到 uv。" >&2
    exit 1
  fi
}

ensure_uv_python() {
  log "正在确认 uv Python 3.14"
  if ! run_with_timeout 600 uv python install 3.14; then
    echo "uv Python 3.14 安装超时或失败。请检查网络后重试。" >&2
    exit 1
  fi
}

install_defuddle() {
  refresh_path
  if command -v defuddle >/dev/null 2>&1 && [[ "$UPGRADE_TOOLS" -eq 0 ]]; then
    log "defuddle 已安装，跳过升级"
    return
  fi

  if command -v defuddle >/dev/null 2>&1; then
    log "defuddle 已安装，正在通过 bun 升级"
  else
    log "正在通过 bun 安装 defuddle"
  fi
  if ! run_with_timeout 600 bun install -g defuddle; then
    warn "defuddle 安装失败，将使用临时 cache 重试。"
    local retry_cache
    retry_cache="$(mktemp -d "/tmp/one-build-bun-cache.XXXXXX")"
    if ! BUN_INSTALL_CACHE_DIR="$retry_cache" run_with_timeout 600 bun install -g defuddle --cache-dir "$retry_cache"; then
      echo "defuddle 安装超时或失败。请检查网络后重试。" >&2
      exit 1
    fi
  fi
  refresh_path
  if ! command -v defuddle >/dev/null 2>&1; then
    echo "defuddle 安装已完成，但当前 PATH 中仍找不到 defuddle。" >&2
    exit 1
  fi
}

install_markitdown() {
  refresh_path
  if command -v markitdown >/dev/null 2>&1 && [[ "$UPGRADE_TOOLS" -eq 0 ]]; then
    log "MarkItDown 已安装，跳过升级"
    return
  fi

  if command -v markitdown >/dev/null 2>&1; then
    log "MarkItDown 已安装，正在通过 uv 升级"
  else
    log "正在通过 uv 安装 MarkItDown"
  fi
  if ! run_with_timeout 900 uv tool install --upgrade "markitdown[all]"; then
    echo "MarkItDown 安装超时或失败。请检查网络后重试。" >&2
    exit 1
  fi
  refresh_path
  if ! command -v markitdown >/dev/null 2>&1; then
    echo "MarkItDown 安装已完成，但当前 PATH 中仍找不到 markitdown。" >&2
    exit 1
  fi
}

enable_obsidian_community_plugin() {
  local vault_path="$1"
  local plugin_id="$2"
  local obsidian_dir="$vault_path/.obsidian"
  local plugins_file="$obsidian_dir/community-plugins.json"

  mkdir -p "$obsidian_dir"
  if [[ ! -f "$plugins_file" ]]; then
    printf '[\n  "%s"\n]\n' "$plugin_id" > "$plugins_file"
    return
  fi

  if grep -q "\"$plugin_id\"" "$plugins_file"; then
    return
  fi

  if perl -0ne 'exit(/\[\s*\]\s*$/ ? 0 : 1)' "$plugins_file"; then
    printf '[\n  "%s"\n]\n' "$plugin_id" > "$plugins_file"
  else
    perl -0pi -e 's/\]\s*$/,\n  "'"$plugin_id"'"\n]\n/s' "$plugins_file"
  fi
}

install_obsidian_excalidraw_plugin() {
  local vault_path="$1"
  local plugin_id="obsidian-excalidraw-plugin"
  local plugin_dir="$vault_path/.obsidian/plugins/$plugin_id"

  if [[ -f "$plugin_dir/manifest.json" && "$UPGRADE_TOOLS" -eq 0 ]]; then
    log "Obsidian Excalidraw 插件已安装，跳过更新"
    enable_obsidian_community_plugin "$vault_path" "$plugin_id"
    return
  fi

  if [[ -f "$plugin_dir/manifest.json" ]]; then
    log "正在更新 Obsidian Excalidraw 插件"
  else
    log "正在安装 Obsidian Excalidraw 插件"
  fi
  mkdir -p "$plugin_dir"
  log "正在下载 Excalidraw 插件文件：main.js"
  curl -fL --connect-timeout 20 --max-time 180 --retry 2 --show-error "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/latest/download/main.js" -o "$plugin_dir/main.js"
  log "正在下载 Excalidraw 插件文件：manifest.json"
  curl -fL --connect-timeout 20 --max-time 180 --retry 2 --show-error "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/latest/download/manifest.json" -o "$plugin_dir/manifest.json"
  log "正在下载 Excalidraw 插件文件：styles.css"
  curl -fL --connect-timeout 20 --max-time 180 --retry 2 --show-error "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/latest/download/styles.css" -o "$plugin_dir/styles.css"
  enable_obsidian_community_plugin "$vault_path" "$plugin_id"
}

register_obsidian_vault() {
  local vault_path="$1"
  local config_dir="$HOME/Library/Application Support/obsidian"
  local config_path="$config_dir/obsidian.json"
  local resolved_vault_path

  resolved_vault_path="$(cd "$vault_path" && pwd -P)"
  mkdir -p "$config_dir"

  OBSIDIAN_CONFIG_PATH="$config_path" OBSIDIAN_VAULT_PATH="$resolved_vault_path" bun -e '
const fs = require("fs");
const crypto = require("crypto");

const configPath = process.env.OBSIDIAN_CONFIG_PATH;
const vaultPath = process.env.OBSIDIAN_VAULT_PATH;
let config = {};

if (fs.existsSync(configPath)) {
  try {
    config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch (error) {
    console.error(`警告：无法读取 Obsidian vault 配置，将保留原文件并跳过自动注册。原因：${error.message}`);
    process.exit(0);
  }
}

if (!config.vaults || typeof config.vaults !== "object") {
  config.vaults = {};
}

let vaultId = Object.keys(config.vaults).find((id) => {
  const entry = config.vaults[id];
  return entry && typeof entry.path === "string" && entry.path.replace(/\/+$/, "") === vaultPath.replace(/\/+$/, "");
});

if (!vaultId) {
  vaultId = crypto.createHash("sha1").update(vaultPath.toLowerCase()).digest("hex").slice(0, 16);
}

config.vaults[vaultId] = {
  path: vaultPath,
  ts: Date.now(),
  open: true,
};

fs.writeFileSync(configPath, JSON.stringify(config), "utf8");
'
}

choose_vault_folder() {
  log "请选择 Obsidian 仓库目录"
  local selected
  local normalized
  if ! selected="$(osascript -e 'POSIX path of (choose folder with prompt "请选择或创建用于 LLM Wiki 的 Obsidian 仓库目录")')" ; then
    warn "未选择仓库目录。脚本退出，不会修改 LLM Wiki。"
    exit 0
  fi
  normalized="${selected%/}"
  if [[ "$normalized" == "/" || "$normalized" == "/Volumes/"* && "${normalized#"/Volumes/"}" != */* ]]; then
    selected="$normalized/codexWiki"
    log "选择的是磁盘根目录，将使用默认仓库目录：$selected"
  fi
  mkdir -p "$selected"
  printf '%s\n' "$selected"
}

codex_download_url() {
  local arch="$1"
  local page
  page="$(curl -LsSf https://developers.openai.com/codex/app)"
  if [[ "$arch" == "arm64" ]]; then
    printf '%s\n' "$page" | grep -Eo 'https://persistent\.oaistatic\.com/codex-app-prod/Codex[^"]*\.dmg' | grep -v 'x64' | head -n 1
  else
    printf '%s\n' "$page" | grep -Eo 'https://persistent\.oaistatic\.com/codex-app-prod/Codex[^"]*x64[^"]*\.dmg' | head -n 1
  fi
}

obsidian_download_url() {
  local page
  page="$(curl -LsSf https://obsidian.md/download)"
  printf '%s\n' "$page" | grep -Eo 'https://github\.com/obsidianmd/obsidian-releases/releases/download/[^"]*/Obsidian-[^"]*\.dmg' | head -n 1
}

install_dmg_app() {
  local name="$1"
  local url="$2"
  local dmg_path
  local mount_dir

  if [[ -z "$url" ]]; then
    echo "无法解析 $name 的下载地址。" >&2
    exit 1
  fi

  dmg_path="$(mktemp "/tmp/${name}.XXXXXX.dmg")"
  mount_dir="$(mktemp -d "/tmp/${name}.mount.XXXXXX")"

  log "正在下载 $name"
  curl -L --fail --show-error --output "$dmg_path" "$url"

  log "正在安装 $name"
  hdiutil attach "$dmg_path" -mountpoint "$mount_dir" -nobrowse -quiet
  local app_path
  app_path="$(find "$mount_dir" -maxdepth 2 -name "*.app" -type d | head -n 1)"
  if [[ -z "$app_path" ]]; then
    hdiutil detach "$mount_dir" -quiet || true
    echo "在 $name dmg 中未找到 .app 应用包。" >&2
    exit 1
  fi

  local target="/Applications/$(basename "$app_path")"
  if [[ -e "$target" ]]; then
    rm -rf "$target" || sudo rm -rf "$target"
  fi
  ditto "$app_path" "$target" || sudo ditto "$app_path" "$target"
  hdiutil detach "$mount_dir" -quiet
  rm -f "$dmg_path"
  rmdir "$mount_dir" 2>/dev/null || true
}

install_or_upgrade_codex() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    arm64|x86_64)
      ;;
    *)
      echo "Codex 应用不支持当前 macOS CPU 架构：$arch" >&2
      exit 1
      ;;
  esac

  if [[ -d "/Applications/Codex.app" ]]; then
    if [[ "$UPGRADE_TOOLS" -eq 1 ]]; then
      log "Codex 已安装，正在升级到官方最新 $arch 构建"
    else
      log "Codex 已安装，跳过"
      return
    fi
  else
    log "Codex 未安装，正在安装官方 $arch 构建"
  fi

  install_dmg_app "Codex" "$(codex_download_url "$arch")"
}

install_or_upgrade_obsidian() {
  if command -v brew >/dev/null 2>&1; then
    if [[ -d "/Applications/Obsidian.app" ]]; then
      if [[ "$UPGRADE_TOOLS" -eq 1 ]]; then
        log "Obsidian 已安装，正在通过 Homebrew 升级"
        brew upgrade --cask obsidian || brew install --cask obsidian
      else
        log "Obsidian 已安装，跳过升级"
      fi
    else
      log "正在通过 Homebrew 安装 Obsidian"
      brew install --cask obsidian
    fi
    return
  fi

  if [[ -d "/Applications/Obsidian.app" ]]; then
    if [[ "$UPGRADE_TOOLS" -eq 1 ]]; then
      log "Obsidian 已安装，正在通过官方 dmg 升级"
    else
      log "Obsidian 已安装，跳过升级"
      return
    fi
  else
    log "Obsidian 未安装，正在安装官方 dmg"
  fi
  install_dmg_app "Obsidian" "$(obsidian_download_url)"
}

copy_template_if_missing() {
  local source_path="$1"
  local path="$2"

  if [[ -f "$path" ]]; then
    log "模板已存在，跳过：$path"
    return
  fi

  log "正在写入模板：$path"
  cp "$source_path" "$path"
}

deploy_llmwiki_workflow() {
  local vault_path="$1"
  local wiki_dir="$vault_path/llmwiki"
  local raw_dir="$wiki_dir/raw"
  local repo_root
  local templates_dir

  log "正在部署 Codex LLM Wiki 工作流"
  mkdir -p \
    "$raw_dir/articles" \
    "$raw_dir/papers" \
    "$raw_dir/transcripts" \
    "$raw_dir/tables" \
    "$raw_dir/documents" \
    "$raw_dir/slides" \
    "$raw_dir/images" \
    "$raw_dir/assets" \
    "$raw_dir/_archive" \
    "$raw_dir/plans/applied" \
    "$raw_dir/tools" \
    "$wiki_dir/实体" \
    "$wiki_dir/概念" \
    "$wiki_dir/对比" \
    "$wiki_dir/问答" \
    "$wiki_dir/总结"

  ensure_one_build_repo_root
  repo_root="$ONE_BUILD_REPO_ROOT"
  templates_dir="$repo_root/templates"
  copy_template_if_missing "$templates_dir/AGENTS.md" "$raw_dir/AGENTS.md"
  copy_template_if_missing "$templates_dir/SCHEMA.md" "$raw_dir/SCHEMA.md"
  copy_template_if_missing "$templates_dir/index.md" "$raw_dir/index.md"
  copy_template_if_missing "$templates_dir/log.md" "$raw_dir/log.md"
  cp "$templates_dir/tools/llmwiki_tool.py" "$raw_dir/tools/llmwiki_tool.py"
  log "已同步 Wiki 工具脚本：$raw_dir/tools/llmwiki_tool.py"
}

global_skills_root() {
  printf '%s\n' "$HOME/.agents/skills"
}

install_managed_skill_directory() {
  local name="$1"
  local source_dir="$2"
  local source_id="$3"
  local skills_root
  local target_dir

  skills_root="$(global_skills_root)"
  mkdir -p "$skills_root"
  target_dir="$skills_root/$name"

  if [[ -d "$target_dir" ]]; then
    rm -rf "$target_dir"
  fi

  cp -R "$source_dir" "$target_dir"
  if [[ "$name" == "defuddle" ]]; then
    perl -0pi -e 's/If not installed: `npm install -g defuddle`/如果未安装，请使用 `bun install -g defuddle`。/g' "$target_dir/SKILL.md"
  fi
  cat > "$target_dir/.one-build-source.json" <<EOF
{
  "name": "$name",
  "source": "$source_id",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

install_managed_skill_from_one_build() {
  local name="$1"
  local source_dir
  local repo_root
  local managed_skill_dir
  local manifest_path
  local relative_path
  local target_path
  local target_parent
  local source_path

  source_dir="$(mktemp -d "/tmp/one-build-managed-skill-$name.XXXXXX")"
  ensure_one_build_repo_root
  repo_root="$ONE_BUILD_REPO_ROOT"
  managed_skill_dir="$repo_root/managed-skills/$name"
  manifest_path="$managed_skill_dir/MANIFEST.txt"

  if [[ ! -d "$managed_skill_dir" ]]; then
    echo "安装资源包中缺少 managed skill：$name" >&2
    exit 1
  fi
  if [[ ! -f "$manifest_path" ]]; then
    echo "managed skill 缺少 MANIFEST.txt：$name" >&2
    exit 1
  fi

  log "正在同步 managed skill：$name"

  while IFS= read -r relative_path || [[ -n "$relative_path" ]]; do
    [[ -n "$relative_path" ]] || continue
    target_path="$source_dir/$relative_path"
    target_parent="$(dirname "$target_path")"
    mkdir -p "$target_parent"
    source_path="$managed_skill_dir/$relative_path"
    if [[ ! -f "$source_path" ]]; then
      echo "managed skill 文件缺失：$name/$relative_path" >&2
      exit 1
    fi
    cp "$source_path" "$target_path"
  done < "$manifest_path"

  install_managed_skill_directory "$name" "$source_dir" "https://github.com/NothingToDooo/one_build/tree/main/managed-skills/$name"
}

install_llmwiki_global_skill() {
  local vault_path="$1"
  local wiki_path="$vault_path/llmwiki"
  local temp_dir

  temp_dir="$(mktemp -d "/tmp/one-build-skill-llm-wiki.XXXXXX")"
  cat > "$temp_dir/SKILL.md" <<EOF
---
name: llm-wiki
description: 定位并进入用户的 LLM Wiki 或 Obsidian 知识库。适用于用户询问项目记忆、资料来源、已有笔记、研究结论、知识库内容、wiki 内容，或要求导入、查询、整理、总结、更新本地知识资料时。
---

# LLM Wiki 入口

这个全局 skill 只负责定位 wiki 和加载本地规则，不定义具体维护规则。

## 当前安装位置

- Obsidian vault：\`$vault_path\`
- LLM Wiki：\`$wiki_path\`

## 使用方式

1. 进入 Obsidian vault：\`$vault_path\`。
2. 确认 \`llmwiki/raw/AGENTS.md\` 存在。
3. 先读取：
   - \`llmwiki/raw/AGENTS.md\`
   - \`llmwiki/raw/SCHEMA.md\`
   - \`llmwiki/raw/index.md\`
   - \`llmwiki/raw/log.md\`
4. 后续全部按照 \`llmwiki/raw/AGENTS.md\` 和 \`llmwiki/raw/SCHEMA.md\` 执行。

如果用户明确指定了另一个 vault，则以用户指定路径为准，并重复读取该 vault 下的 \`llmwiki/raw/\` 规则文件。
EOF

  install_managed_skill_directory "llm-wiki" "$temp_dir" "generated-by-one_build:$wiki_path"
}

sync_global_skills() {
  local vault_path="$1"
  log "正在同步 Codex 全局 skills"
  local name
  for name in defuddle markitdown obsidian-bases obsidian-cli obsidian-markdown; do
    install_managed_skill_from_one_build "$name"
  done

  for name in excalidraw-diagram mermaid-visualizer obsidian-canvas-creator; do
    install_managed_skill_from_one_build "$name"
  done

  install_llmwiki_global_skill "$vault_path"
  log "全局 skills 已同步到：$(global_skills_root)"
  if pgrep -x "Codex" >/dev/null 2>&1; then
    warn "Codex 已在运行。新安装或更新的全局 skills 需要新建会话或重启 Codex 后才会加载。"
  fi
}

ensure_obsidian_cli() {
  log "正在配置 Obsidian CLI"
  local cli_path="/usr/local/bin/obsidian"
  local bundled_cli="/Applications/Obsidian.app/Contents/MacOS/obsidian-cli"

  if ! command -v obsidian >/dev/null 2>&1; then
    if [[ -x "$bundled_cli" ]]; then
      sudo ln -sf "$bundled_cli" "$cli_path"
    else
      warn "未找到 Obsidian CLI。请确认已安装 Obsidian 1.12.7+，并在 Obsidian 设置 -> 通用 中开启 Command line interface。"
      return
    fi
  fi

  if ! pgrep -x "Obsidian" >/dev/null 2>&1; then
    warn "Obsidian 未运行，已配置 Obsidian CLI 路径；跳过实时验证。"
    return
  fi

  if obsidian version >/dev/null 2>&1; then
    log "Obsidian CLI 已可用：$(obsidian version)"
  else
    warn "Obsidian CLI 暂不可用。请打开 Obsidian，在设置 -> 通用 中开启 Command line interface 后重试。"
  fi
}

open_apps() {
  local vault_path="$1"
  local index_path="$vault_path/llmwiki/raw/index.md"
  if [[ "$SKIP_OPEN_APPS" -eq 1 ]]; then
    return
  fi

  log "正在打开 Codex 和 Obsidian"
  open -a "Codex" || true

  register_obsidian_vault "$vault_path"
  if pgrep -x "Obsidian" >/dev/null 2>&1; then
    log "Obsidian 已在运行，跳过打开"
  elif [[ -f "$index_path" ]]; then
    open "obsidian://open?path=$(bun -e 'console.log(encodeURIComponent(process.argv[1]))' "$index_path")" || true
  else
    open -a "Obsidian" || true
  fi
}

main() {
  require_macos
  ensure_command curl
  ensure_command hdiutil
  ensure_command osascript
  ensure_bun
  ensure_uv
  ensure_uv_python
  local vault_path
  vault_path="$(choose_vault_folder)"
  install_or_upgrade_obsidian
  deploy_llmwiki_workflow "$vault_path"
  install_obsidian_excalidraw_plugin "$vault_path"
  register_obsidian_vault "$vault_path"
  ensure_obsidian_cli
  install_defuddle
  install_markitdown
  sync_global_skills "$vault_path"
  install_or_upgrade_codex
  open_apps "$vault_path"
  log "完成"
}

main

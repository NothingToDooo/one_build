#!/usr/bin/env bash
set -euo pipefail

SKIP_OPEN_APPS=0
TEMPLATE_BASE_URL="https://raw.githubusercontent.com/NothingToDooo/one_build/main/templates"

for arg in "$@"; do
  case "$arg" in
    --skip-open-apps)
      SKIP_OPEN_APPS=1
      ;;
    -h|--help)
      cat <<'EOF'
用法：bash ./setup.sh [--skip-open-apps]

安装或升级 Codex 应用、Obsidian、bun、defuddle 和 LLM Wiki 工作流模板。
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

ensure_bun() {
  refresh_path
  if command -v bun >/dev/null 2>&1; then
    log "bun 已可用"
    return
  fi

  log "正在使用 Bun 官方安装器安装 bun"
  curl -fsSL https://bun.sh/install | bash
  refresh_path
  if ! command -v bun >/dev/null 2>&1; then
    echo "bun 安装已完成，但当前 PATH 中仍找不到 bun。" >&2
    exit 1
  fi
}

install_defuddle() {
  refresh_path
  if command -v defuddle >/dev/null 2>&1; then
    log "defuddle 已安装，跳过升级"
    return
  fi

  log "正在通过 bun 安装 defuddle"
  bun install -g defuddle
  refresh_path
  if ! command -v defuddle >/dev/null 2>&1; then
    echo "defuddle 安装已完成，但当前 PATH 中仍找不到 defuddle。" >&2
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

  if [[ -f "$plugin_dir/manifest.json" ]]; then
    log "Obsidian Excalidraw 插件已安装，跳过更新"
    enable_obsidian_community_plugin "$vault_path" "$plugin_id"
    return
  fi

  log "正在安装 Obsidian Excalidraw 插件"
  mkdir -p "$plugin_dir"
  curl -fsSL "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/latest/download/main.js" -o "$plugin_dir/main.js"
  curl -fsSL "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/latest/download/manifest.json" -o "$plugin_dir/manifest.json"
  curl -fsSL "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/latest/download/styles.css" -o "$plugin_dir/styles.css"
  enable_obsidian_community_plugin "$vault_path" "$plugin_id"
}

choose_vault_folder() {
  log "请选择 Obsidian 仓库目录"
  local selected
  if ! selected="$(osascript -e 'POSIX path of (choose folder with prompt "请选择或创建用于 LLM Wiki 的 Obsidian 仓库目录")')" ; then
    warn "未选择仓库目录。脚本退出，不会修改 LLM Wiki。"
    exit 0
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
    log "Codex 已安装，正在升级到官方最新 $arch 构建"
  else
    log "Codex 未安装，正在安装官方 $arch 构建"
  fi

  install_dmg_app "Codex" "$(codex_download_url "$arch")"
}

install_or_upgrade_obsidian() {
  if command -v brew >/dev/null 2>&1; then
    if [[ -d "/Applications/Obsidian.app" ]]; then
      log "Obsidian 已安装，正在通过 Homebrew 升级"
      brew upgrade --cask obsidian || brew install --cask obsidian
    else
      log "正在通过 Homebrew 安装 Obsidian"
      brew install --cask obsidian
    fi
    return
  fi

  if [[ -d "/Applications/Obsidian.app" ]]; then
    log "Obsidian 已安装，正在通过官方 dmg 升级"
  else
    log "Obsidian 未安装，正在安装官方 dmg"
  fi
  install_dmg_app "Obsidian" "$(obsidian_download_url)"
}

download_template_if_missing() {
  local url="$1"
  local path="$2"

  if [[ -f "$path" ]]; then
    log "模板已存在，跳过：$path"
    return
  fi

  log "正在写入模板：$path"
  curl -fsSL "$url" -o "$path"
}

ensure_root_agents_file() {
  local vault_path="$1"
  local root_agents="$vault_path/AGENTS.md"

  if [[ -f "$root_agents" ]] && grep -q 'llmwiki/AGENTS\.md' "$root_agents"; then
    log "根目录 AGENTS.md 已包含 LLM Wiki 指引，跳过"
    return
  fi

  if [[ -f "$root_agents" ]]; then
    log "正在补充根目录 AGENTS.md"
    cat >> "$root_agents" <<'EOF'

## Codex LLM Wiki

这个 Obsidian 仓库包含一套 Codex LLM Wiki 工作流，位置是 `llmwiki/`。

使用或维护这套知识库前，先阅读：

- `llmwiki/AGENTS.md`
- `llmwiki/SCHEMA.md`
- `llmwiki/index.md`
- `llmwiki/log.md`

除非用户明确要求，不要修改 `llmwiki/` 外的用户笔记。
EOF
    return
  fi

  log "正在创建根目录 AGENTS.md"
  cat > "$root_agents" <<'EOF'
# Codex 仓库指引

## Codex LLM Wiki

这个 Obsidian 仓库包含一套 Codex LLM Wiki 工作流，位置是 `llmwiki/`。

使用或维护这套知识库前，先阅读：

- `llmwiki/AGENTS.md`
- `llmwiki/SCHEMA.md`
- `llmwiki/index.md`
- `llmwiki/log.md`

除非用户明确要求，不要修改 `llmwiki/` 外的用户笔记。
EOF
}

deploy_llmwiki_workflow() {
  local vault_path="$1"
  local wiki_dir="$vault_path/llmwiki"

  log "正在部署 Codex LLM Wiki 工作流"
  mkdir -p \
    "$wiki_dir/raw/articles" \
    "$wiki_dir/raw/papers" \
    "$wiki_dir/raw/transcripts" \
    "$wiki_dir/raw/tables" \
    "$wiki_dir/raw/documents" \
    "$wiki_dir/raw/slides" \
    "$wiki_dir/raw/images" \
    "$wiki_dir/raw/assets" \
    "$wiki_dir/entities" \
    "$wiki_dir/concepts" \
    "$wiki_dir/comparisons" \
    "$wiki_dir/queries" \
    "$wiki_dir/_archive"

  download_template_if_missing "$TEMPLATE_BASE_URL/AGENTS.md" "$wiki_dir/AGENTS.md"
  download_template_if_missing "$TEMPLATE_BASE_URL/SCHEMA.md" "$wiki_dir/SCHEMA.md"
  download_template_if_missing "$TEMPLATE_BASE_URL/index.md" "$wiki_dir/index.md"
  download_template_if_missing "$TEMPLATE_BASE_URL/log.md" "$wiki_dir/log.md"
  ensure_root_agents_file "$vault_path"
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
  if [[ "$name" == "excalidraw-diagram" ]]; then
    local tmp_skill="$target_dir/SKILL.md.tmp"
    cat > "$tmp_skill" <<'EOF'
## 安装前置条件

Obsidian 模式需要 vault 内已安装并启用社区插件 `obsidian-excalidraw-plugin`。one_build 安装脚本会自动下载并启用该插件；如果当前 vault 不是 one_build 选择的 vault，首次使用前先检查 `.obsidian/plugins/obsidian-excalidraw-plugin/manifest.json` 和 `.obsidian/community-plugins.json`。

EOF
    cat "$target_dir/SKILL.md" >> "$tmp_skill"
    mv "$tmp_skill" "$target_dir/SKILL.md"
  fi
  cat > "$target_dir/.one-build-source.json" <<EOF
{
  "name": "$name",
  "source": "$source_id",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

expand_repo_archive() {
  local repo="$1"
  local destination="$2"
  local zip_path

  mkdir -p "$destination"
  zip_path="$destination/$(printf '%s' "$repo" | tr '/' '-').zip"
  curl -fL --show-error -o "$zip_path" "https://github.com/$repo/archive/refs/heads/main.zip"
  unzip -q "$zip_path" -d "$destination"
  find "$destination" -maxdepth 1 -type d -name '*-main' | head -n 1
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
2. 确认 \`llmwiki/AGENTS.md\` 存在。
3. 先读取：
   - \`llmwiki/AGENTS.md\`
   - \`llmwiki/SCHEMA.md\`
   - \`llmwiki/index.md\`
   - \`llmwiki/log.md\`
4. 后续全部按照 \`llmwiki/AGENTS.md\` 和 \`llmwiki/SCHEMA.md\` 执行。

如果用户明确指定了另一个 vault，则以用户指定路径为准，并重复读取该 vault 下的 \`llmwiki/\` 规则文件。
EOF

  install_managed_skill_directory "llm-wiki" "$temp_dir" "generated-by-one_build:$wiki_path"
}

sync_global_skills() {
  local vault_path="$1"
  log "正在同步 Codex 全局 skills"
  local temp_root
  local kepano_root
  local visual_root
  local name

  temp_root="$(mktemp -d "/tmp/one-build-skills.XXXXXX")"

  kepano_root="$(expand_repo_archive "kepano/obsidian-skills" "$temp_root/kepano")"
  for name in defuddle obsidian-bases obsidian-cli obsidian-markdown; do
    install_managed_skill_directory "$name" "$kepano_root/skills/$name" "https://github.com/kepano/obsidian-skills/tree/main/skills/$name"
  done

  visual_root="$(expand_repo_archive "axtonliu/axton-obsidian-visual-skills" "$temp_root/axtonliu")"
  for name in excalidraw-diagram mermaid-visualizer obsidian-canvas-creator; do
    install_managed_skill_directory "$name" "$visual_root/$name" "https://github.com/axtonliu/axton-obsidian-visual-skills/tree/main/$name"
  done

  install_llmwiki_global_skill "$vault_path"
  log "全局 skills 已同步到：$(global_skills_root)"
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
    open -a "Obsidian" || warn "无法自动启动 Obsidian 来验证 CLI。"
    sleep 5
  fi

  if obsidian version >/dev/null 2>&1; then
    log "Obsidian CLI 已可用：$(obsidian version)"
  else
    warn "Obsidian CLI 暂不可用。请打开 Obsidian，在设置 -> 通用 中开启 Command line interface 后重试。"
  fi
}

open_apps() {
  local vault_path="$1"
  if [[ "$SKIP_OPEN_APPS" -eq 1 ]]; then
    return
  fi

  log "正在打开 Codex 和 Obsidian"
  open -a "Codex" || true
  open -a "Obsidian" "$vault_path" || true
}

main() {
  require_macos
  ensure_command curl
  ensure_command hdiutil
  ensure_command osascript
  ensure_bun
  local vault_path
  vault_path="$(choose_vault_folder)"
  install_or_upgrade_codex
  install_or_upgrade_obsidian
  ensure_obsidian_cli
  deploy_llmwiki_workflow "$vault_path"
  install_defuddle
  install_obsidian_excalidraw_plugin "$vault_path"
  ensure_command unzip
  sync_global_skills "$vault_path"
  open_apps "$vault_path"
  log "完成"
}

main

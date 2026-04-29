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

安装或升级 Codex 应用、Obsidian、uv 和 llmwiki。
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
  export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
}

ensure_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "缺少必需命令：$name" >&2
    exit 1
  fi
}

ensure_uv() {
  refresh_path
  if command -v uv >/dev/null 2>&1; then
    log "uv 已可用"
    return
  fi

  log "正在使用 Astral 官方安装器安装 uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  refresh_path
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv 安装已完成，但当前 PATH 中仍找不到 uv。" >&2
    exit 1
  fi
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

install_llmwiki() {
  local vault_path="$1"
  local wiki_dir="$vault_path/llmwiki"

  if command -v llmbase >/dev/null 2>&1; then
    log "llmwiki 已安装，跳过升级"
  else
    log "正在安装 llmwiki"
    uv tool install llmwiki
  fi
  refresh_path
  if ! command -v llmbase >/dev/null 2>&1; then
    echo "llmwiki 已安装，但当前 PATH 中仍找不到 llmbase。" >&2
    exit 1
  fi

  mkdir -p "$wiki_dir/raw" "$wiki_dir/wiki/outputs" "$wiki_dir/wiki/_meta" "$wiki_dir/wiki/concepts"
  if [[ -f "$wiki_dir/config.yaml" ]] && (! grep -Eq '^[[:space:]]*outputs[[:space:]]*:' "$wiki_dir/config.yaml" || ! grep -Eq '^[[:space:]]*meta[[:space:]]*:' "$wiki_dir/config.yaml"); then
    log "正在补齐 LLM Wiki 配置：$wiki_dir/config.yaml"
    cat > "$wiki_dir/config.yaml" <<'EOF'
paths:
  raw: raw
  wiki: wiki
  outputs: wiki/outputs
  meta: wiki/_meta
  concepts: wiki/concepts
EOF
  fi

  log "正在检查 LLM Wiki 状态"
  llmbase --base-dir "$wiki_dir" stats || warn "llmbase stats 失败；请稍后检查配置和权限。"
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
  ensure_uv
  local vault_path
  vault_path="$(choose_vault_folder)"
  install_or_upgrade_codex
  install_or_upgrade_obsidian
  ensure_obsidian_cli
  install_llmwiki "$vault_path"
  deploy_llmwiki_workflow "$vault_path"
  open_apps "$vault_path"
  log "完成"
}

main

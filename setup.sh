#!/usr/bin/env bash
set -euo pipefail

SKIP_OPEN_APPS=0

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

  log "正在安装或升级 llmwiki"
  uv tool install --upgrade llmwiki
  refresh_path
  if ! command -v llmwiki >/dev/null 2>&1; then
    echo "llmwiki 已安装，但当前 PATH 中仍找不到 llmwiki。" >&2
    exit 1
  fi

  mkdir -p "$wiki_dir"
  log "正在初始化 LLM Wiki：$wiki_dir"
  (
    cd "$wiki_dir"
    llmwiki init
    log "正在同步可用的 agent 会话"
    llmwiki sync || warn "llmwiki sync 失败；将继续尝试链接 Obsidian。"
    log "正在将 LLM Wiki 链接到 Obsidian 仓库"
    llmwiki link-obsidian --vault "$vault_path" || warn "llmwiki link-obsidian 失败；请检查 llmwiki 版本和仓库权限。"
  )
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
  install_llmwiki "$vault_path"
  open_apps "$vault_path"
  log "完成"
}

main

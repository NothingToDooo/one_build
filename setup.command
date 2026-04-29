#!/usr/bin/env bash
set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.sh"
SCRIPT_PATH="$(mktemp "/tmp/one-build-setup.XXXXXX.sh")"

echo "One Build setup"
echo
echo "正在下载最新安装脚本..."

curl -fL --connect-timeout 20 --max-time 180 --retry 2 --show-error -o "$SCRIPT_PATH" "$SCRIPT_URL"
chmod +x "$SCRIPT_PATH"

echo
echo "正在启动安装流程..."
bash "$SCRIPT_PATH" "$@"

echo
echo "安装流程已结束。可以关闭这个窗口。"
read -r -p "按回车键退出..." _

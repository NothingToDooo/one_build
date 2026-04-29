#!/usr/bin/env bash
set -uo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.sh"
SCRIPT_PATH="$(mktemp "/tmp/one-build-setup.XXXXXX.sh")"

echo "One Build setup"
echo
echo "正在下载最新安装脚本..."

if ! curl -fL --connect-timeout 20 --max-time 180 --retry 2 --show-error -o "$SCRIPT_PATH" "$SCRIPT_URL"; then
  echo
  echo "下载失败。请检查网络，并把这个错误发给维护者。"
  echo
  read -n 1 -s -r -p "按任意键关闭安装窗口..."
  echo
  exit 1
fi
chmod +x "$SCRIPT_PATH"

echo
echo "正在启动安装流程..."
bash "$SCRIPT_PATH" "$@"
EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]; then
  echo
  echo "安装失败。退出码：$EXIT_CODE"
  echo
  read -n 1 -s -r -p "按任意键关闭安装窗口..."
  echo
  exit "$EXIT_CODE"
fi

echo
echo "安装流程已结束。"
read -n 1 -s -r -p "按任意键关闭安装窗口..."
echo

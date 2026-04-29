# One Build 一键配置

用于安装和配置 Codex 应用、Obsidian 与 LLM Wiki 的一键脚本。

脚本已经发布到 GitHub Raw。用户只需要复制对应系统的一条命令执行。

## Windows

用户在 PowerShell 中执行这一条命令：

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p
```

可选：跳过最后自动打开应用。

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -SkipOpenApps
```

可选：强制升级已安装的软件和工具。默认会跳过已安装项目，避免每次运行都很慢。

```powershell
$u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"; $p=Join-Path $env:TEMP "one-build-setup.ps1"; Invoke-RestMethod $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p -UpgradeTools
```

不要使用 `Invoke-RestMethod ... | Invoke-Expression` 直接管道执行主脚本。Windows 脚本需要真实文件路径来完成 UAC 提权重启，所以必须先下载到临时文件再执行。

脚本会请求管理员权限；必要时自动安装或修复 `winget`，安装 `uv`，升级或安装 Codex 应用和 Obsidian，然后要求用户选择 Obsidian 仓库目录。

## macOS

用户在终端中执行这一条命令：

```bash
u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.sh"; f="$(mktemp)"; curl -fsSL "$u" -o "$f"; bash "$f"
```

可选：跳过最后自动打开应用。

```bash
u="https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.sh"; f="$(mktemp)"; curl -fsSL "$u" -o "$f"; bash "$f" --skip-open-apps
```

脚本会在需要时安装 `uv`，要求用户选择 Obsidian 仓库目录，安装或升级 Codex 应用和 Obsidian，然后配置 `llmwiki`。

## 发布要求

- 云端地址必须是 HTTPS。
- `setup.ps1` 和 `setup.sh` 必须作为原始文本返回，不能返回 HTML 预览页。
- Windows 用户命令必须下载到临时文件后执行，不能直接管道执行。
- 如果使用 GitHub，使用 Raw 地址，例如 `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/setup.ps1`。

## 说明

- Codex 登录不会自动化；脚本只负责安装并打开官方应用。
- 脚本不会删除已有的 Obsidian 仓库内容。
- LLM Wiki 会创建或复用所选仓库中的 `llmwiki` 目录。
- PyPI 包名是 `llmwiki`，安装后的命令名是 `llmbase`。

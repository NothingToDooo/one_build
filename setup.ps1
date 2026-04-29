[CmdletBinding()]
param(
    [switch]$SkipOpenApps,
    [switch]$NoPause,
    [switch]$UpgradeTools
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$TemplateBaseUrl = "https://raw.githubusercontent.com/NothingToDooo/one_build/main/templates"

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "警告：$Message" -ForegroundColor Yellow
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    if (Test-Admin) {
        return
    }

    Write-Step "正在请求管理员权限"
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        throw "必须从已保存的 .ps1 文件运行此脚本，这样脚本才能以管理员权限重新启动。"
    }

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptPath`""
    )
    if ($SkipOpenApps) {
        $arguments += "-SkipOpenApps"
    }
    if ($NoPause) {
        $arguments += "-NoPause"
    }
    if ($UpgradeTools) {
        $arguments += "-UpgradeTools"
    }

    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
    exit 0
}

function Add-ProcessPath {
    param([string[]]$Paths)

    $current = [Environment]::GetEnvironmentVariable("PATH", "Process")
    $parts = @($current -split [IO.Path]::PathSeparator | Where-Object { $_ })
    foreach ($path in $Paths) {
        if ($path -and (Test-Path -LiteralPath $path) -and ($parts -notcontains $path)) {
            $parts += $path
        }
    }
    [Environment]::SetEnvironmentVariable("PATH", ($parts -join [IO.Path]::PathSeparator), "Process")
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $user = [Environment]::GetEnvironmentVariable("PATH", "User")
    [Environment]::SetEnvironmentVariable("PATH", "$machine$([IO.Path]::PathSeparator)$user", "Process")
    Add-ProcessPath @(
        (Join-Path $env:USERPROFILE ".local\bin"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
    )
}

function Add-UserPath {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $parts = @($userPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($parts -notcontains $Path) {
        $parts += $Path
        [Environment]::SetEnvironmentVariable("PATH", ($parts -join [IO.Path]::PathSeparator), "User")
    }
    Add-ProcessPath @($Path)
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    Write-Host "+ $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if (($null -ne $exitCode) -and ($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "命令执行失败，退出码 ${exitCode}: $FilePath $($Arguments -join ' ')"
    }
    return $exitCode
}

function Ensure-Winget {
    Refresh-Path
    if (Test-Command "winget") {
        Write-Step "winget 已可用"
        return
    }

    Write-Step "未找到 winget，正在尝试注册 Microsoft App Installer"
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"
    }
    catch {
        Write-Warn "App Installer 注册失败：$($_.Exception.Message)"
    }

    Refresh-Path
    if (Test-Command "winget") {
        Write-Step "注册 App Installer 后 winget 已可用"
        return
    }

    Write-Step "正在下载 Microsoft App Installer 安装包"
    $installerDir = Join-Path $env:TEMP "one-build-winget"
    New-Item -ItemType Directory -Force -Path $installerDir | Out-Null
    $bundlePath = Join-Path $installerDir "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $bundleUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    Invoke-WebRequest -UseBasicParsing -Uri $bundleUrl -OutFile $bundlePath
    Add-AppxPackage -Path $bundlePath

    Refresh-Path
    if (-not (Test-Command "winget")) {
        throw "安装 Microsoft App Installer 后 winget 仍不可用。可能是 Windows 策略或 Appx/MSIX 依赖阻止了安装。"
    }
}

function Ensure-Uv {
    Refresh-Path
    if (Test-Command "uv") {
        Write-Step "uv 已可用"
        return
    }

    Write-Step "正在使用 Astral 官方安装器安装 uv"
    Invoke-RestMethod "https://astral.sh/uv/install.ps1" | Invoke-Expression
    Refresh-Path
    if (-not (Test-Command "uv")) {
        throw "uv 安装已完成，但当前 PATH 中仍找不到 uv。"
    }
}

function Select-VaultFolder {
    Write-Step "请选择 Obsidian 仓库目录"
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = "请选择或创建用于 LLM Wiki 的 Obsidian 仓库目录"
    $dialog.ShowNewFolderButton = $true
    if ($dialog.PSObject.Properties.Name -contains "UseDescriptionForTitle") {
        $dialog.UseDescriptionForTitle = $true
    }
    $result = $dialog.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
        Write-Warn "未选择仓库目录。脚本退出，不会修改 LLM Wiki。"
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $dialog.SelectedPath | Out-Null
    return (Resolve-Path -LiteralPath $dialog.SelectedPath).Path
}

function Test-WingetPackageInstalled {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Source
    )

    if ($Source -eq "msstore") {
        $args = @("list", $Id, "--source", $Source, "--accept-source-agreements")
    }
    else {
        $args = @("list", "--id", $Id, "--accept-source-agreements")
    }
    if ($Source -and $Source -ne "msstore") {
        $args += @("--source", $Source)
    }
    $output = (& winget @args 2>$null) -join "`n"
    return ($output -match [regex]::Escape($Id))
}

function Install-OrUpgradeWingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Source
    )

    if ($Source -eq "msstore") {
        $packageArgs = @($Id)
    }
    else {
        $packageArgs = @("--id", $Id)
    }

    $commonArgs = @("--accept-source-agreements", "--accept-package-agreements")
    if ($Source) {
        $commonArgs += @("--source", $Source)
    }

    if (Test-WingetPackageInstalled -Id $Id -Source $Source) {
        if ($UpgradeTools) {
            Write-Step "$Name 已安装，正在尝试升级"
            Invoke-LoggedCommand -FilePath "winget" -Arguments (@("upgrade") + $packageArgs + $commonArgs) -AllowFailure | Out-Null
        }
        else {
            Write-Step "$Name 已安装，跳过升级"
        }
        return
    }

    Write-Step "正在安装 $Name"
    Invoke-LoggedCommand -FilePath "winget" -Arguments (@("install") + $packageArgs + $commonArgs)
}

function Install-LlmWiki {
    param([string]$VaultPath)

    if (Test-Command "llmbase") {
        if ($UpgradeTools) {
            Write-Step "llmwiki 已安装，正在升级"
            Invoke-LoggedCommand -FilePath "uv" -Arguments @("tool", "upgrade", "llmwiki")
        }
        else {
            Write-Step "llmwiki 已安装，跳过升级"
        }
    }
    else {
        Write-Step "正在安装 llmwiki"
        Invoke-LoggedCommand -FilePath "uv" -Arguments @("tool", "install", "llmwiki")
    }
    Refresh-Path
    if (-not (Test-Command "llmbase")) {
        throw "llmwiki 已安装，但当前 PATH 中仍找不到 llmbase。"
    }

    $wikiDir = Join-Path $VaultPath "llmwiki"
    $rawDir = Join-Path $wikiDir "raw"
    $outputsDir = Join-Path $wikiDir "wiki\outputs"
    $metaDir = Join-Path $wikiDir "wiki\_meta"
    $conceptsDir = Join-Path $wikiDir "wiki\concepts"
    New-Item -ItemType Directory -Force -Path $rawDir, $outputsDir, $metaDir, $conceptsDir | Out-Null

    $configPath = Join-Path $wikiDir "config.yaml"
    if (Test-Path -LiteralPath $configPath) {
        $configText = Get-Content -LiteralPath $configPath -Raw
        if ($configText -notmatch "(?m)^\s*outputs\s*:" -or $configText -notmatch "(?m)^\s*meta\s*:") {
            Write-Step "正在补齐 LLM Wiki 配置：$configPath"
            @"
paths:
  raw: raw
  wiki: wiki
  outputs: wiki/outputs
  meta: wiki/_meta
  concepts: wiki/concepts
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8
        }
    }

    Write-Step "正在检查 LLM Wiki 状态"
    Invoke-LoggedCommand -FilePath "llmbase" -Arguments @("--base-dir", $wikiDir, "stats") -AllowFailure | Out-Null
}

function Save-TemplateIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Step "模板已存在，跳过：$Path"
        return
    }

    Write-Step "正在写入模板：$Path"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path
}

function Ensure-RootAgentsFile {
    param([Parameter(Mandatory = $true)][string]$VaultPath)

    $rootAgents = Join-Path $VaultPath "AGENTS.md"
    $section = @"

## Codex LLM Wiki

这个 Obsidian 仓库包含一套 Codex LLM Wiki 工作流，位置是 `llmwiki/`。

使用或维护这套知识库前，先阅读：

- `llmwiki/AGENTS.md`
- `llmwiki/SCHEMA.md`
- `llmwiki/index.md`
- `llmwiki/log.md`

除非用户明确要求，不要修改 `llmwiki/` 外的用户笔记。
"@

    if (Test-Path -LiteralPath $rootAgents) {
        $existing = Get-Content -LiteralPath $rootAgents -Raw
        if ($existing -match "llmwiki/AGENTS\.md") {
            Write-Step "根目录 AGENTS.md 已包含 LLM Wiki 指引，跳过"
            return
        }
        Write-Step "正在补充根目录 AGENTS.md"
        Add-Content -LiteralPath $rootAgents -Value $section -Encoding UTF8
        return
    }

    Write-Step "正在创建根目录 AGENTS.md"
    @"
# Codex 仓库指引
$section
"@ | Set-Content -LiteralPath $rootAgents -Encoding UTF8
}

function Deploy-LlmWikiWorkflow {
    param([Parameter(Mandatory = $true)][string]$VaultPath)

    Write-Step "正在部署 Codex LLM Wiki 工作流"
    $wikiDir = Join-Path $VaultPath "llmwiki"
    $directories = @(
        $wikiDir,
        (Join-Path $wikiDir "raw\articles"),
        (Join-Path $wikiDir "raw\papers"),
        (Join-Path $wikiDir "raw\transcripts"),
        (Join-Path $wikiDir "raw\assets"),
        (Join-Path $wikiDir "entities"),
        (Join-Path $wikiDir "concepts"),
        (Join-Path $wikiDir "comparisons"),
        (Join-Path $wikiDir "queries"),
        (Join-Path $wikiDir "_archive")
    )
    New-Item -ItemType Directory -Force -Path $directories | Out-Null

    foreach ($name in @("AGENTS.md", "SCHEMA.md", "index.md", "log.md")) {
        Save-TemplateIfMissing -Url "$TemplateBaseUrl/$name" -Path (Join-Path $wikiDir $name)
    }

    Ensure-RootAgentsFile -VaultPath $VaultPath
}

function Get-GlobalSkillsRoot {
    return (Join-Path $HOME ".agents\skills")
}

function Install-ManagedSkillDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$SourceId
    )

    $skillsRoot = Get-GlobalSkillsRoot
    New-Item -ItemType Directory -Force -Path $skillsRoot | Out-Null
    $targetDir = Join-Path $skillsRoot $Name

    if (Test-Path -LiteralPath $targetDir) {
        Remove-Item -LiteralPath $targetDir -Recurse -Force
    }

    Copy-Item -LiteralPath $SourceDir -Destination $targetDir -Recurse -Force
    @{
        name = $Name
        source = $SourceId
        installed_at = (Get-Date).ToString("o")
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $targetDir ".one-build-source.json") -Encoding UTF8
}

function Expand-RepoArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $zipPath = Join-Path $Destination (($Repo -replace "/", "-") + ".zip")
    $url = "https://github.com/$Repo/archive/refs/heads/main.zip"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $Destination -Force
    return (Get-ChildItem -LiteralPath $Destination -Directory | Where-Object { $_.Name -like "*-main" } | Select-Object -First 1).FullName
}

function Install-LlmWikiGlobalSkill {
    param([Parameter(Mandatory = $true)][string]$VaultPath)

    $tempDir = Join-Path $env:TEMP "one-build-skill-llm-wiki"
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $wikiPath = Join-Path $VaultPath "llmwiki"
    @"
---
name: llm-wiki
description: 定位并进入用户的 Codex LLM Wiki。适用于用户提到 llmwiki、LLM Wiki、知识库、Obsidian wiki，或要求导入资料、查询知识库、整理 wiki 时。
---

# Codex LLM Wiki 入口

这个全局 skill 只负责定位 wiki 和加载本地规则，不定义具体维护规则。

## 当前安装位置

- Obsidian vault：`$VaultPath`
- LLM Wiki：`$wikiPath`

## 使用方式

1. 进入 Obsidian vault：`$VaultPath`。
2. 确认 `llmwiki/AGENTS.md` 存在。
3. 先读取：
   - `llmwiki/AGENTS.md`
   - `llmwiki/SCHEMA.md`
   - `llmwiki/index.md`
   - `llmwiki/log.md`
4. 后续全部按照 `llmwiki/AGENTS.md` 和 `llmwiki/SCHEMA.md` 执行。

如果用户明确指定了另一个 vault，则以用户指定路径为准，并重复读取该 vault 下的 `llmwiki/` 规则文件。
"@ | Set-Content -LiteralPath (Join-Path $tempDir "SKILL.md") -Encoding UTF8

    Install-ManagedSkillDirectory -Name "llm-wiki" -SourceDir $tempDir -SourceId "generated-by-one_build:$wikiPath"
}

function Sync-GlobalSkills {
    param([Parameter(Mandatory = $true)][string]$VaultPath)

    Write-Step "正在同步 Codex 全局 skills"
    $tempRoot = Join-Path $env:TEMP "one-build-skills"
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $kepanoRoot = Expand-RepoArchive -Repo "kepano/obsidian-skills" -Destination (Join-Path $tempRoot "kepano")
    foreach ($name in @("defuddle", "obsidian-bases", "obsidian-cli", "obsidian-markdown")) {
        Install-ManagedSkillDirectory -Name $name -SourceDir (Join-Path $kepanoRoot "skills\$name") -SourceId "https://github.com/kepano/obsidian-skills/tree/main/skills/$name"
    }

    $visualRoot = Expand-RepoArchive -Repo "axtonliu/axton-obsidian-visual-skills" -Destination (Join-Path $tempRoot "axtonliu")
    foreach ($name in @("excalidraw-diagram", "mermaid-visualizer", "obsidian-canvas-creator")) {
        Install-ManagedSkillDirectory -Name $name -SourceDir (Join-Path $visualRoot $name) -SourceId "https://github.com/axtonliu/axton-obsidian-visual-skills/tree/main/$name"
    }

    Install-LlmWikiGlobalSkill -VaultPath $VaultPath
    Write-Step "全局 skills 已同步到：$(Get-GlobalSkillsRoot)"
}

function Find-ObsidianCli {
    $command = Get-Command "obsidian" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $command = Get-Command "Obsidian.com" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Obsidian\Obsidian.com"),
        (Join-Path $env:ProgramFiles "Obsidian\Obsidian.com")
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Obsidian\Obsidian.com")
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Ensure-ObsidianCli {
    Write-Step "正在配置 Obsidian CLI"
    $cliPath = Find-ObsidianCli
    if (-not $cliPath) {
        Write-Warn "未找到 Obsidian CLI。请确认已安装 Obsidian 1.12.7+，并在 Obsidian 设置 -> 通用 中开启 Command line interface。"
        return
    }

    Add-UserPath -Path (Split-Path -Parent $cliPath)

    if (-not (Get-Process -Name "Obsidian" -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        try {
            $obsidianExe = Join-Path (Split-Path -Parent $cliPath) "Obsidian.exe"
            if (Test-Path -LiteralPath $obsidianExe) {
                Start-Process -FilePath $obsidianExe -ErrorAction Stop
            }
            else {
                Start-Process "obsidian://" -ErrorAction Stop
            }
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Warn "无法自动启动 Obsidian 来验证 CLI。原因：$($_.Exception.Message)"
        }
    }

    try {
        $versionOutput = (& $cliPath version 2>&1) -join "`n"
        if ($LASTEXITCODE -eq 0) {
            Write-Step "Obsidian CLI 已可用：$versionOutput"
        }
        else {
            Write-Warn "Obsidian CLI 暂不可用。请打开 Obsidian，在设置 -> 通用 中开启 Command line interface 后重试。输出：$versionOutput"
        }
    }
    catch {
        Write-Warn "Obsidian CLI 验证失败。请打开 Obsidian，在设置 -> 通用 中开启 Command line interface 后重试。原因：$($_.Exception.Message)"
    }
}

function Open-InstalledApps {
    param([string]$VaultPath)

    if ($SkipOpenApps) {
        return
    }

    Write-Step "正在打开 Codex 和 Obsidian"

    $codexRunning = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -ieq "Codex" -or ($_.Path -and $_.Path -match "\\OpenAI\.Codex_")
    } | Select-Object -First 1
    if ($codexRunning) {
        Write-Step "Codex 已在运行，跳过打开"
    }
    else {
        try {
            $codexAppId = (Get-StartApps | Where-Object { $_.Name -eq "Codex" -or $_.AppID -match "^OpenAI\.Codex_" } | Select-Object -First 1 -ExpandProperty AppID)
            if ($codexAppId) {
                Start-Process "shell:AppsFolder\$codexAppId" -ErrorAction Stop
            }
            else {
                Write-Warn "未在开始菜单中找到 Codex AppID，请从开始菜单手动打开 Codex。"
            }
        }
        catch {
            Write-Warn "无法自动打开 Codex。请从开始菜单手动打开 Codex。原因：$($_.Exception.Message)"
        }
    }

    $obsidianRunning = Get-Process -Name "Obsidian" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($obsidianRunning) {
        Write-Step "Obsidian 已在运行，跳过打开"
        return
    }

    try {
        Start-Process "obsidian://open?path=$([uri]::EscapeDataString($VaultPath))" -ErrorAction Stop
    }
    catch {
        try {
            $obsidian = Get-Command "Obsidian.exe" -ErrorAction Stop
            Start-Process -FilePath $obsidian.Source -ArgumentList "`"$VaultPath`"" -ErrorAction Stop
        }
        catch {
            Write-Warn "无法自动打开 Obsidian。请手动打开 Obsidian 并选择仓库：$VaultPath。原因：$($_.Exception.Message)"
        }
    }
}

Restart-Elevated

$logPath = Join-Path $env:TEMP "one-build-setup.log"
$success = $false
try {
    Start-Transcript -Path $logPath -Append | Out-Null
}
catch {
    Write-Warn "无法启动日志记录：$($_.Exception.Message)"
}

try {
    Ensure-Winget
    Ensure-Uv
    $vaultPath = Select-VaultFolder
    Install-OrUpgradeWingetPackage -Name "Codex 应用" -Id "9PLM9XGG6VKS" -Source "msstore"
    Install-OrUpgradeWingetPackage -Name "Obsidian" -Id "Obsidian.Obsidian"
    Ensure-ObsidianCli
    Install-LlmWiki -VaultPath $vaultPath
    Deploy-LlmWikiWorkflow -VaultPath $vaultPath
    Sync-GlobalSkills -VaultPath $vaultPath
    try {
        Open-InstalledApps -VaultPath $vaultPath
    }
    catch {
        Write-Warn "自动打开应用失败，但安装配置已经完成。请手动打开 Codex 和 Obsidian。原因：$($_.Exception.Message)"
    }
    $success = $true
    Write-Step "完成。日志文件：$logPath"
}
catch {
    Write-Host ""
    Write-Host "安装失败：" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "日志文件：$logPath" -ForegroundColor Yellow
    Write-Host "请把上面的错误信息或日志内容发给维护者。" -ForegroundColor Yellow
    exit 1
}
finally {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
    if (-not $NoPause) {
        if ($success) {
            Read-Host "已完成，按回车关闭窗口"
        }
        else {
            Read-Host "按回车关闭窗口"
        }
    }
}

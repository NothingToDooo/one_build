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
        (Join-Path $env:USERPROFILE ".bun\bin"),
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

function Ensure-Bun {
    Refresh-Path
    if (Test-Command "bun") {
        Write-Step "bun 已可用"
        return
    }

    Install-OrUpgradeWingetPackage -Name "Bun" -Id "Oven-sh.Bun"
    Refresh-Path
    if (-not (Test-Command "bun")) {
        throw "Bun 安装已完成，但当前 PATH 中仍找不到 bun。"
    }
}

function Install-Defuddle {
    Refresh-Path
    if ((Test-Command "defuddle") -and (-not $UpgradeTools)) {
        Write-Step "defuddle 已安装，跳过升级"
        return
    }

    if ($UpgradeTools -and (Test-Command "defuddle")) {
        Write-Step "defuddle 已安装，正在通过 bun 升级"
    }
    else {
        Write-Step "正在通过 bun 安装 defuddle"
    }

    Invoke-LoggedCommand -FilePath "bun" -Arguments @("install", "-g", "defuddle")
    Add-UserPath -Path (Join-Path $env:USERPROFILE ".bun\bin")
    Refresh-Path
    if (-not (Test-Command "defuddle")) {
        throw "defuddle 安装已完成，但当前 PATH 中仍找不到 defuddle。"
    }
}

function Enable-ObsidianCommunityPlugin {
    param(
        [Parameter(Mandatory = $true)][string]$VaultPath,
        [Parameter(Mandatory = $true)][string]$PluginId
    )

    $obsidianDir = Join-Path $VaultPath ".obsidian"
    New-Item -ItemType Directory -Force -Path $obsidianDir | Out-Null
    $pluginsPath = Join-Path $obsidianDir "community-plugins.json"

    $plugins = @()
    if (Test-Path -LiteralPath $pluginsPath) {
        try {
            $parsed = Get-Content -LiteralPath $pluginsPath -Raw | ConvertFrom-Json
            if ($parsed) {
                $plugins = @($parsed)
            }
        }
        catch {
            Write-Warn "无法解析 community-plugins.json，正在重建插件启用列表。原因：$($_.Exception.Message)"
        }
    }

    if ($plugins -notcontains $PluginId) {
        $plugins += $PluginId
    }

    ConvertTo-Json -InputObject $plugins | Set-Content -LiteralPath $pluginsPath -Encoding UTF8
}

function Install-ObsidianExcalidrawPlugin {
    param([Parameter(Mandatory = $true)][string]$VaultPath)

    $pluginId = "obsidian-excalidraw-plugin"
    $pluginDir = Join-Path $VaultPath ".obsidian\plugins\$pluginId"
    $manifestPath = Join-Path $pluginDir "manifest.json"
    if ((Test-Path -LiteralPath $manifestPath) -and (-not $UpgradeTools)) {
        Write-Step "Obsidian Excalidraw 插件已安装，跳过更新"
        Enable-ObsidianCommunityPlugin -VaultPath $VaultPath -PluginId $pluginId
        return
    }

    Write-Step "正在安装 Obsidian Excalidraw 插件"
    New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
    foreach ($file in @("main.js", "manifest.json", "styles.css")) {
        $url = "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/latest/download/$file"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile (Join-Path $pluginDir $file)
    }
    Enable-ObsidianCommunityPlugin -VaultPath $VaultPath -PluginId $pluginId
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

function Ensure-LlmWikiBulkRule {
    param([Parameter(Mandatory = $true)][string]$WikiDir)

    $agentsPath = Join-Path $WikiDir "AGENTS.md"
    if (-not (Test-Path -LiteralPath $agentsPath)) {
        return
    }

    $content = Get-Content -LiteralPath $agentsPath -Raw
    if ($content -match "## 批量资料处理") {
        return
    }

    Write-Step "正在补充 LLM Wiki 批量资料处理规则"
    $rule = @'

## 批量资料处理

当用户要求处理大量文件、整个目录、多个资料包，或资料类型明显混杂时：

1. 先盘点文件清单，按目录或类型分组，例如网页、PDF、Word、表格、幻灯片、会议记录、图片和其他附件。
2. 设计子代理分工，每个子代理只负责一个清晰边界：一个目录、一类文件，或一批相同格式资料。
3. 子代理只做提取、摘要、候选实体/概念、来源记录和风险标记，不直接改写彼此负责的文件。
4. 主代理负责合并子代理结果，去重同义实体和概念，决定是否创建或更新 wiki 页面。
5. 合并时保留每批资料的来源路径、处理状态和未解决问题。
6. 最后由主代理统一更新 `index.md` 和 `log.md`。

如果当前运行环境没有子代理能力，就先完成分组和处理计划，再按分组顺序逐批处理；不要在没有盘点的情况下直接把大量文件混在一起总结。
'@

    Add-Content -LiteralPath $agentsPath -Value $rule -Encoding UTF8
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

    Ensure-LlmWikiBulkRule -WikiDir $wikiDir
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
    if ($Name -eq "defuddle") {
        $skillPath = Join-Path $targetDir "SKILL.md"
        $skillText = Get-Content -LiteralPath $skillPath -Raw
        $skillText = $skillText.Replace('If not installed: `npm install -g defuddle`', '如果未安装，请使用 `bun install -g defuddle`。')
        Set-Content -LiteralPath $skillPath -Value $skillText -Encoding UTF8
    }
    if ($Name -eq "excalidraw-diagram") {
        $skillPath = Join-Path $targetDir "SKILL.md"
        $skillText = Get-Content -LiteralPath $skillPath -Raw
        $prefix = @"
## 安装前置条件

Obsidian 模式需要 vault 内已安装并启用社区插件 `obsidian-excalidraw-plugin`。one_build 安装脚本会自动下载并启用该插件；如果当前 vault 不是 one_build 选择的 vault，首次使用前先检查 `.obsidian/plugins/obsidian-excalidraw-plugin/manifest.json` 和 `.obsidian/community-plugins.json`。

"@
        Set-Content -LiteralPath $skillPath -Value ($prefix + $skillText) -Encoding UTF8
    }
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
description: 定位并进入用户的 LLM Wiki 或 Obsidian 知识库。适用于用户询问项目记忆、资料来源、已有笔记、研究结论、知识库内容、wiki 内容，或要求导入、查询、整理、总结、更新本地知识资料时。
---

# LLM Wiki 入口

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
    Ensure-Bun
    $vaultPath = Select-VaultFolder
    Install-OrUpgradeWingetPackage -Name "Codex 应用" -Id "9PLM9XGG6VKS" -Source "msstore"
    Install-OrUpgradeWingetPackage -Name "Obsidian" -Id "Obsidian.Obsidian"
    Ensure-ObsidianCli
    Deploy-LlmWikiWorkflow -VaultPath $vaultPath
    Install-Defuddle
    Install-ObsidianExcalidrawPlugin -VaultPath $vaultPath
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

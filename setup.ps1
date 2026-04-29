[CmdletBinding()]
param(
    [switch]$SkipOpenApps
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

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

    $args = @("list", "--id", $Id, "--accept-source-agreements")
    if ($Source) {
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

    $commonArgs = @("--id", $Id, "--accept-source-agreements", "--accept-package-agreements")
    if ($Source) {
        $commonArgs += @("--source", $Source)
    }

    if (Test-WingetPackageInstalled -Id $Id -Source $Source) {
        Write-Step "$Name 已安装，正在尝试升级"
        Invoke-LoggedCommand -FilePath "winget" -Arguments (@("upgrade") + $commonArgs) -AllowFailure | Out-Null
        return
    }

    Write-Step "正在安装 $Name"
    Invoke-LoggedCommand -FilePath "winget" -Arguments (@("install") + $commonArgs)
}

function Install-LlmWiki {
    param([string]$VaultPath)

    Write-Step "正在安装或升级 llmwiki"
    Invoke-LoggedCommand -FilePath "uv" -Arguments @("tool", "install", "--upgrade", "llmwiki")
    Refresh-Path
    if (-not (Test-Command "llmwiki")) {
        throw "llmwiki 已安装，但当前 PATH 中仍找不到 llmwiki。"
    }

    $wikiDir = Join-Path $VaultPath "llmwiki"
    New-Item -ItemType Directory -Force -Path $wikiDir | Out-Null

    Push-Location $wikiDir
    try {
        Write-Step "正在初始化 LLM Wiki：$wikiDir"
        Invoke-LoggedCommand -FilePath "llmwiki" -Arguments @("init")
        Write-Step "正在同步可用的 agent 会话"
        Invoke-LoggedCommand -FilePath "llmwiki" -Arguments @("sync") -AllowFailure | Out-Null
        Write-Step "正在将 LLM Wiki 链接到 Obsidian 仓库"
        Invoke-LoggedCommand -FilePath "llmwiki" -Arguments @("link-obsidian", "--vault", $VaultPath) -AllowFailure | Out-Null
    }
    finally {
        Pop-Location
    }
}

function Open-InstalledApps {
    param([string]$VaultPath)

    if ($SkipOpenApps) {
        return
    }

    Write-Step "正在打开 Codex 和 Obsidian"
    Start-Process "shell:AppsFolder\9PLM9XGG6VKS!App" -ErrorAction SilentlyContinue
    Start-Process "obsidian://open?path=$([uri]::EscapeDataString($VaultPath))" -ErrorAction SilentlyContinue
}

Restart-Elevated

$logPath = Join-Path $env:TEMP "one-build-setup.log"
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
    Install-LlmWiki -VaultPath $vaultPath
    Open-InstalledApps -VaultPath $vaultPath
    Write-Step "完成。日志文件：$logPath"
}
finally {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
}

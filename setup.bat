@echo off
setlocal

set "SCRIPT_URL=https://raw.githubusercontent.com/NothingToDooo/one_build/main/setup.ps1"
set "SCRIPT_PATH=%TEMP%\one-build-setup.ps1"

echo One Build setup
echo.
echo Downloading latest setup script...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-RestMethod '%SCRIPT_URL%' -OutFile '%SCRIPT_PATH%'"
if errorlevel 1 (
  echo.
  echo Download failed. Please check your network and send this error to the maintainer.
  pause
  exit /b 1
)

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  echo.
  echo Requesting administrator permission...
  set "ONE_BUILD_PS1=%SCRIPT_PATH%"
  set "ONE_BUILD_ARGS=%*"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$argList = '-NoProfile -ExecutionPolicy Bypass -File \"' + $env:ONE_BUILD_PS1 + '\" ' + $env:ONE_BUILD_ARGS; Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs"
  exit /b 0
)

echo.
echo Starting setup...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %* -NoPause
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo Setup failed. Exit code: %EXIT_CODE%
  pause
  exit /b %EXIT_CODE%
)

echo.
echo Setup finished.
pause
exit /b 0

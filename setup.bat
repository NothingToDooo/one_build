@echo off
setlocal

if not "%ONE_BUILD_CHILD%"=="1" (
  set "ONE_BUILD_CHILD=1"
  set "ONE_BUILD_BAT=%~f0"
  set "ONE_BUILD_ARGS=%*"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$argList = '/c \"\"' + $env:ONE_BUILD_BAT + '\" ' + $env:ONE_BUILD_ARGS + '\"'; Start-Process -FilePath 'cmd.exe' -ArgumentList $argList -Verb RunAs"
  exit /b 0
)

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

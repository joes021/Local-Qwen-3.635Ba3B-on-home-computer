@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "INSTALL_SCRIPT=%SCRIPT_DIR%install\windows\install.ps1"

if not exist "%INSTALL_SCRIPT%" (
    echo Installer script not found: %INSTALL_SCRIPT%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%"
exit /b %ERRORLEVEL%

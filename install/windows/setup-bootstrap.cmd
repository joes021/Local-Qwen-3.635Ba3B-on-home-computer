@echo off
setlocal
title Local Qwen Home Computer Setup
set "SCRIPT_DIR=%~dp0"
set "INSTALL_SCRIPT=%SCRIPT_DIR%install\windows\install.ps1"

echo ===============================================
echo Local Qwen Home Computer - Windows Setup
echo ===============================================
echo.
echo This installer will:
echo   1. Prepare the LocalQwenHome workspace
echo   2. Check dependencies and copy launchers
echo   3. Create desktop shortcuts
echo   4. Verify runtime, model, OpenCode and final state
echo.

if not exist "%INSTALL_SCRIPT%" (
    echo Installer script not found: %INSTALL_SCRIPT%
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo Installation failed with exit code %EXITCODE%.
    echo Review the stage output above before closing this window.
    echo.
    pause
    exit /b %EXITCODE%
)

echo.
echo Installation complete.
echo This window will close automatically in 3 seconds.
timeout /t 3 /nobreak >nul
exit /b 0

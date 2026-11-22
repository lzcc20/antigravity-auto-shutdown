@echo off
setlocal

set "DEST=%USERPROFILE%\.gemini\config\plugins\auto-shutdown"

echo [Auto Shutdown] Uninstalling Antigravity plugin...

if exist "%DEST%\scripts\ctl.mjs" (
    node "%DEST%\scripts\ctl.mjs" disarm >nul 2>&1
)

if exist "%DEST%" (
    rmdir /s /q "%DEST%"
    echo [Auto Shutdown] Removed plugin directory: %DEST%
) else (
    echo [Auto Shutdown] Plugin directory not found: %DEST%
)

echo [Auto Shutdown] User preferences at %USERPROFILE%\.gemini\config\auto-shutdown were preserved.
echo                 Delete that folder manually if you want a complete reset.
endlocal

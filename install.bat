@echo off
setlocal EnableDelayedExpansion

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
set "DEST=%USERPROFILE%\.gemini\config\plugins\auto-shutdown"

echo [Auto Shutdown] Installing Antigravity plugin...
echo   Source: %SRC%
echo   Target: %DEST%

if not exist "%USERPROFILE%\.gemini\config\plugins" (
    mkdir "%USERPROFILE%\.gemini\config\plugins"
)

if exist "%DEST%" (
    rmdir /s /q "%DEST%"
)
mkdir "%DEST%"

copy /y "%SRC%\plugin.json" "%DEST%\plugin.json" >nul
copy /y "%SRC%\hooks.json" "%DEST%\hooks.json" >nul
copy /y "%SRC%\README.md" "%DEST%\README.md" >nul
copy /y "%SRC%\LICENSE" "%DEST%\LICENSE" >nul

xcopy /e /i /y "%SRC%\assets" "%DEST%\assets" >nul
xcopy /e /i /y "%SRC%\scripts" "%DEST%\scripts" >nul
xcopy /e /i /y "%SRC%\skills" "%DEST%\skills" >nul

echo.
echo [Auto Shutdown] Installed successfully!
echo   - Config ^& state are preserved at: %USERPROFILE%\.gemini\config\auto-shutdown
echo   - Launching bottom-right floating widget...
node "%DEST%\scripts\ctl.mjs" ui >nul 2>&1

echo   - Open Antigravity Customizations to manage the plugin, or run /auto-shutdown in chat.
endlocal

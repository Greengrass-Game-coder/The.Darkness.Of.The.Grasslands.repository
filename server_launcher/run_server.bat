@echo off
cd /d "%~dp0"

echo ============================================
echo   The Darkness of the Grasslands - Server
echo ============================================
echo.

REM === CONFIGURATION ===
set SERVER_EXE=TheDarknessServer.exe
set SERVER_DIR=%~dp0server
set NGROK_PATH=C:\tools\ngrok\ngrok.exe
set NGROK_DOMAIN=enlisted-cardstock-bunny.ngrok-free.dev
set SERVER_PORT=8080
REM ======================

REM Make sure server exe exists
if not exist "%SERVER_DIR%\%SERVER_EXE%" (
    echo [ERROR] Server executable not found at:
    echo   %SERVER_DIR%\%SERVER_EXE%
    echo.
    echo First export the server in Godot:
    echo   Project ^> Export ^> Add Windows Desktop ^> Export PCK/ZIP
    echo   Save to: %SERVER_DIR%\%SERVER_EXE%
    echo.
    pause
    exit /b 1
)

echo [1/3] Starting Dedicated Server...
start "DarknessServer" /B "%SERVER_DIR%\%SERVER_EXE%" --headless

REM Wait for server to be ready
echo [2/3] Waiting for server on port %SERVER_PORT%...
:waitloop
timeout /t 2 /nobreak >nul
netstat -an 2>nul | find ":%SERVER_PORT% " | find "LISTEN" >nul
if errorlevel 1 goto waitloop

echo   Server is running on port %SERVER_PORT%!

REM Check ngrok exists
if not exist "%NGROK_PATH%" (
    echo [WARNING] ngrok not found at %NGROK_PATH%
    echo   Install from: https://ngrok.com/download
    echo   Then update NGROK_PATH in this script.
    echo.
    echo Server is still running at localhost:%SERVER_PORT%
    echo You can connect directly without ngrok.
    pause
    exit /b 0
)

echo [3/3] Starting ngrok tunnel...
echo   Domain: %NGROK_DOMAIN%
echo   Dashboard: http://localhost:4040
echo.
"%NGROK_PATH%" http --domain=%NGROK_DOMAIN% %SERVER_PORT%

REM If ngrok exits, keep the server running so user sees it
echo.
echo ngrok has stopped. Server is still running.
echo Close this window to stop the server.
pause
taskkill /f /im "%SERVER_EXE%" 2>nul

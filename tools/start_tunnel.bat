@echo off
title Darkness of the Grasslands - Tunnel
echo ========================================
echo   Darkness of the Grasslands - Tunnel
echo ========================================
echo.
echo Your new tunnel URL will appear below.
echo Copy it and send it to Ziva to update the game!
echo.

:TUNNEL_LOOP
echo [%date% %time%] Starting tunnel...
cloudflared tunnel --url http://localhost:8080

echo [%date% %time%] Tunnel crashed! Restarting in 3 seconds...
timeout /t 3 /nobreak >nul
goto TUNNEL_LOOP
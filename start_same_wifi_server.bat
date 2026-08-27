@echo off
rem ============================================================
rem  PLAY WITH SOMEONE ON THE SAME WI-FI (same internet)
rem
rem  Run this on ONE computer (the "host"). It starts a game server
rem  on that computer and shows you the address your friend types.
rem
rem  Then on BOTH computers, in the game's LOGIN screen, in the
rem  "Server URL" box:
rem    - HOST types:      ws://localhost:8080
rem    - FRIEND (same Wi-Fi): ws://THE-IP-SHOWN-BELOW:8080
rem
rem  Both press LOGIN, then "Find a Game". You meet in the same lobby
rem  and the countdown starts the match together.
rem ============================================================
setlocal
set "EXE=%~dp0server_launcher\server\TheDarknessServer.exe"
if not exist "%EXE%" (
    echo [ERROR] Server executable not found at:
    echo   %EXE%
    echo.
    echo Export the server first in Godot: Project ^> Export,
    echo or check the path above.
    pause
    exit /b 1
)

echo ============================================
echo  Starting the SAME-WI-FI server...
echo ============================================
start "DarknessServer" /B "%EXE%" --headless
echo.
echo  Server started on port 8080.
echo.
echo  Your address to give to the friend on the same Wi-Fi:
echo.
ipconfig | findstr /i "IPv4"
echo.
echo  Instructions:
echo    YOU (host):   type   ws://localhost:8080   in the Server URL box
echo    YOUR FRIEND:  type   ws://<one of the IPs above>:8080
echo  Then both press LOGIN and "Find a Game".
echo.
echo  If the friend can't connect, Windows Firewall is blocking it.
echo  Run this ONCE as Administrator to allow it, then retry:
echo    netsh advfirewall firewall add rule name="Darkness 8080" ^
      dir=in action=allow protocol=TCP localport=8080
echo.
echo  Keep this window OPEN to keep the server running.
echo  Close it to stop the server.
pause
taskkill /f /im "TheDarknessServer.exe" >nul 2>&1
endlocal

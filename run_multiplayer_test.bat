@echo off
rem ============================================================
rem  TEST MULTIPLAYER BY YOURSELF, ON ONE LAPTOP
rem
rem  Opens 9 SEPARATE players (Player1..Player9) that all connect
rem  to the same online game at once, so you can watch/balance how
rem  the game behaves with many players.
rem
rem  Usage:  double-click it (9 players), or:
rem          run_multiplayer_test.bat 6   (6 players instead)
rem
rem  Close each window to stop that player.
rem ============================================================
setlocal enabledelayedexpansion
if "%~1"=="" (set "COUNT=9") else (set "COUNT=%~1")

set "GODOT=C:\Users\misfer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
set "PROJ=C:\Users\misfer\Documents\the-darkness-of-the-grasslands"

set "COL=3"
set /a "ROWS=(COUNT+COL-1)/COL"
set "W=640"
set "H=400"
set "GAP=8"

for /L %%i in (1,1,%COUNT%) do (
    set "USERDIR=%APPDATA%\The Darkness Of The Grasslands-player%%i"
    if not exist "!USERDIR!" mkdir "!USERDIR!"
    > "!USERDIR!\session.dat" echo Player%%i
    set /a "ci=(%%i-1) %% COL"
    set /a "ri=(%%i-1) / COL"
    set /a "PX=ci*(W+GAP)+40"
    set /a "PY=ri*(H+GAP)+20"
    start "Player %%i" "%GODOT%" --path "%PROJ%\test_instances\player%%i" --windowed --resolution %W%x%H% --position !PX!,!PY!
    timeout /t 1 /nobreak >nul
)
echo Launched %COUNT% separate players: Player1 .. Player%COUNT%.
echo (All logged in and connected to the same online game.)
endlocal

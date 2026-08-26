@echo off
rem ============================================================
rem  Launch N windowed copies of the game side-by-side so you can
rem  watch them all run at once and spot anything wrong.
rem
rem  Usage:  double-click it (opens 9), or:
rem          run_parallel_instances.bat 6   (opens 6 instead)
rem
rem  The windows are placed in a grid so they don't cover each other.
rem  Close each window to stop that copy.
rem ============================================================
setlocal enabledelayedexpansion

if "%~1"=="" (set "COUNT=9") else (set "COUNT=%~1")

set "GODOT=C:\Users\misfer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
set "PROJ=C:\Users\misfer\Documents\the-darkness-of-the-grasslands"

set "COL=3"
set /a "ROWS=(COUNT + COL - 1) / COL"
set "W=640"
set "H=400"
set "GAP=8"

for /L %%i in (1,1,%COUNT%) do (
    set /a "ci = (%%i - 1) %% COL"
    set /a "ri = (%%i - 1) / COL"
    set /a "PX = ci * (W + GAP) + 40"
    set /a "PY = ri * (H + GAP) + 20"
    start "Game %%i" "%GODOT%" --path "%PROJ%" --windowed --resolution %W%x%H% --position !PX!,!PY!
    timeout /t 1 /nobreak >nul
)

echo Launched %COUNT% windowed instances (grid %COL% x %ROWS%).
echo Close each window to stop that copy.
endlocal

@echo off
REM Double-click to start the IT Helpdesk Toolkit as Administrator.
REM If this window isn't elevated, it relaunches itself through the UAC prompt.
REM Choosing "No" at the prompt opens the toolkit as a standard user instead.

REM fltmc only succeeds when elevated (more reliable than "net session")
fltmc >nul 2>&1
if %errorlevel% equ 0 goto :launch

set "HDT_BAT=%~f0"
powershell.exe -NoProfile -Command "try { Start-Process -FilePath $env:ComSpec -ArgumentList '/c', ('\"' + $env:HDT_BAT + '\"') -Verb RunAs -WindowStyle Hidden -ErrorAction Stop } catch { exit 1 }"
if %errorlevel% equ 0 exit /b

REM UAC was cancelled - open without admin rights
:launch
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Toolkit\HelpdeskToolkit-GUI.ps1" -NoElevate

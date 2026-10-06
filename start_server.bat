@echo off
title Sam Connected Server Engine
echo ========================================================
echo   Sam Connected - Local Photo & Video Backup Server
echo ========================================================
echo.

set PORT=8080
set STORAGE=%USERPROFILE%\Pictures\SamConnectedBackup

if not exist "%STORAGE%" (
    mkdir "%STORAGE%"
)

echo Port     : %PORT%
echo Storage  : %STORAGE%
echo.
echo Menjalankan engine backup Sam Connected di Windows...
echo Server siap menerima backup dari iPhone / Android di jaringan WiFi lokal.
echo Tekan Ctrl+C untuk menghentikan server.
echo ========================================================
echo.

"%~dp0client\assets\bin\server.exe" -port %PORT% -storage "%STORAGE%"

pause

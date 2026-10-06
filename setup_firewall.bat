@echo off
:: BatchGotAdmin
:-------------------------------------
REM --> Check for permissions
IF '%PROCESSOR_ARCHITECTURE%' EQU 'amd64' (
   >nul 2>&1 "%SYSTEMROOT%\SysWOW64\cacls.exe" "%SYSTEMROOT%\SysWOW64\config\system"
) ELSE (
   >nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
)

REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo [INFO] Membutuhkan hak akses Administrator untuk menambahkan aturan Windows Firewall.
    echo Klik "Yes" pada jendela pop-up konfirmasi Administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

title Sam Connected - Konfigurasi Windows Firewall
echo ========================================================
echo   Sam Connected - Konfigurasi Port Windows Firewall
echo ========================================================
echo.
echo Menambahkan izin Windows Firewall untuk komunikasi jaringan lokal (Wi-Fi):
echo.
echo 1. Port 8080 (TCP) - HTTP REST API ^& Web Dashboard...
netsh advfirewall firewall delete rule name="Sam Connected Server (TCP 8080)" >nul 2>&1
netsh advfirewall firewall add rule name="Sam Connected Server (TCP 8080)" dir=in action=allow protocol=TCP localport=8080 profile=any >nul

echo 2. Port 8088 (UDP) - Auto-Discovery Beacon ^& Broadcast...
netsh advfirewall firewall delete rule name="Sam Connected Server (UDP 8088)" >nul 2>&1
netsh advfirewall firewall add rule name="Sam Connected Server (UDP 8088)" dir=in action=allow protocol=UDP localport=8088 profile=any >nul

echo 3. Program SamConnectedServer.exe...
netsh advfirewall firewall delete rule name="Sam Connected Server App" >nul 2>&1
netsh advfirewall firewall add rule name="Sam Connected Server App" dir=in action=allow program="%~dp0SamConnectedServer.exe" enable=yes profile=any >nul

echo.
echo ========================================================
echo   [SUKSES] Windows Firewall berhasil dikonfigurasi!
echo   Sekarang iPhone / iPad / Client dapat langsung
echo   mendeteksi server secara otomatis di jaringan Wi-Fi.
echo ========================================================
echo.
pause

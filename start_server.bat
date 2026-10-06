@echo off
title Sam Connected - Host Storage Server
cls
echo ========================================================
echo   Sam Connected - Host Storage Server (Windows)
echo ========================================================
echo.
echo [INFO] Alamat IP PC Anda di jaringan lokal (Gunakan IP ini di iPhone):
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4 Address" /c:"Alamat IPv4"') do (
    echo    * %%a
)
echo.
echo [PENTING UNTUK KONEKSI DARI IPHONE]:
echo  1. Pastikan profil jaringan Windows adalah "Private Network".
echo  2. Jika iPhone gagal terhubung, jalankan file "setup_firewall.bat"
echo     (Klik kanan ^> Run as administrator) untuk membuka port 8080.
echo.
echo Membuka aplikasi Sam Connected Server...
start "" "%~dp0SamConnectedServer.exe"
timeout /t 3 >nul
exit

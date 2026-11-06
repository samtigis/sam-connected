# Panduan Setup AltStore untuk Sam Connected

Dokumen ini menjelaskan alur lengkap pemasangan dan pembaruan otomatis aplikasi **Sam Connected** di iPhone menggunakan **AltStore** tanpa akun Apple Developer berbayar.

---

## 📌 Mengapa Menggunakan AltStore?
- **Gratis ($0)**: Menggunakan Apple ID gratis biasa Anda.
- **Auto-Refresh di Latar Belakang**: AltStore akan me-refresh sertifikat aplikasi setiap 7 hari secara otomatis melalui jaringan Wi-Fi lokal bersama Mac Anda. Aplikasi tidak akan pernah kadaluarsa.
- **Mandiri & Stabil**: Menggunakan build **Release** resmi tanpa ketergantungan pada sesi debugger Xcode.

---

## 🛠️ Langkah-Langkah Pemasangan (Sekali Setup)

### 1. Pasang AltStore ke iPhone dari Mac
1. **AltServer** sudah terpasang dan berjalan di Mac Anda (lihat ikon wajik AltServer di Menu Bar kanan atas macOS).
2. Hubungkan iPhone Anda ke Mac menggunakan kabel Lightning / USB-C.
3. Buka **Finder**, pilih iPhone Anda di sidebar, dan centang:
   - ✅ **"Show this iPhone when on Wi-Fi"** (agar ke depannya bisa auto-refresh tanpa colok kabel).
4. Klik ikon **AltServer** di Menu Bar atas Mac:
   - Pilih **Install AltStore** > Pilih nama iPhone Anda.
   - Masukkan Apple ID dan Password Anda (kredensial dikirim langsung ke server otentikasi Apple untuk membuat sertifikat pengembang gratis).
5. Tunggu beberapa detik sampai aplikasi **AltStore** muncul di layar iPhone.

### 2. Beri Izin Pengembang di iPhone
Setelah ikon AltStore muncul di iPhone:
1. Buka **Settings** (Pengaturan) di iPhone.
2. Masuk ke **General** > **VPN & Device Management** (Manajemen Perangkat & VPN).
3. Pilih Apple ID Anda dan tekan **Trust** (Percayai).
4. *(Khusus iOS 16 & iOS 17 ke atas)*:
   - Buka **Settings** > **Privacy & Security** > Gulir ke paling bawah ke **Developer Mode** (Mode Pengembang).
   - Nyalakan **Developer Mode** dan restart iPhone sesuai instruksi di layar.

---

## 🚀 Menginstall Sam Connected via AltStore

Setiap kali Anda ingin memperbarui atau memasang aplikasi:

### Langkah A: Build IPA (1 Perintah)
Jalankan skrip yang sudah disiapkan di root proyek:
```bash
./build_ipa.sh
```
Skrip ini akan mengompilasi mode release dan membuat file siap pasang di:
`dist/SamConnected.ipa`

### Langkah B: Pasang ke iPhone
1. Kirim file `dist/SamConnected.ipa` ke iPhone Anda:
   - **Cara termudah**: Klik kanan file `dist/SamConnected.ipa` di Finder > **Share** > **AirDrop** ke iPhone Anda.
   - Atau simpan ke **iCloud Drive** / aplikasi **Files** di iPhone.
2. Buka aplikasi **AltStore** di iPhone.
3. Masuk ke tab **My Apps**.
4. Tekan tombol tambah (**`+`**) di pojok kiri atas.
5. Pilih file **`SamConnected.ipa`**.
6. AltStore akan memproses, menandatangani, dan memasang aplikasi **Sam Connected** ke layar utama iPhone Anda!

---

## 🔄 Bagaimana Cara Kerjanya Agar Terus Aktif?
- Selama laptop Mac Anda menyala dan berada di jaringan Wi-Fi lokal yang sama dengan iPhone, AltStore di iPhone akan berkomunikasi dengan AltServer di Mac dan me-refresh masa berlaku 7 hari secara otomatis di latar belakang (*Background App Refresh*).
- Anda juga bisa me-refresh manual kapan saja dengan menekan tombol **Refresh All** di tab **My Apps** pada aplikasi AltStore di iPhone.

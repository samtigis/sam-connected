# 📸 Sam Connected

**Sam Connected** adalah solusi pencadangan foto & video otomatis lokal berkecepatan tinggi tanpa cloud publik, dirancang khusus untuk membackup galeri HP (iOS / Android) langsung ke penyimpanan laptop/PC (macOS / Windows) di jaringan Wi-Fi lokal.

---

## 🏗️ Arsitektur Sistem

Proyek ini menggunakan arsitektur **Hybrid Dual-Engine**:

```text
[ iPhone / Android (Client Mode) ]
              │
              │  mDNS Zeroconf Discovery (_photobackup._tcp)
              │  HTTP/REST API (Streaming SHA-256 Check & Upload)
              ▼
[ MacBook / Windows PC (Host Server Mode) ]
   ├── Flutter Desktop GUI (Monitoring, Storage Picker, Live Logs)
   └── Go Server Sidecar Daemon (:8080)
        ├── SQLite Database (WAL Mode, CGO-Free)
        ├── File Storage (:storage/{device_id}/{YYYY}/{MM}/{hash}.ext)
        ├── Auto Thumbnail Generator
        └── Streaming Hasher & Disk Metric Service
```

1. **Backend Server (`server/`)**:
   - Dibuat dengan **Go (Golang) + Fiber Framework**.
   - **Database**: SQLite WAL mode (CGO-free menggunakan `github.com/glebarez/sqlite`) untuk operasi konkurensi tinggi tanpa lock.
   - **Streaming SHA-256**: Mencegah duplikasi file tanpa membebani RAM (mendukung file hingga 4 GB).
   - **mDNS Zeroconf**: Menyiarkan service `_photobackup._tcp` di port 8080 agar client di jaringan WiFi dapat menemukan server secara instan tanpa perlu mengetik IP manual.
   - **Pemrosesan Gambar**: Auto generate thumbnail resolusi optimal dan pembacaan metadata EXIF (tanggal ambil, kamera).

2. **Aplikasi Multiplatform (`client/`)**:
   - Dibuat dengan **Flutter Multiplatform** (iOS, macOS, Android, Windows).
   - **Unified Dual-Mode**:
     - **Mode Server / Host Storage (Desktop Only)**: Manajemen storage harddisk, kontrol engine daemon sidecar, pemantauan kapasitas HDD, live log aktivitas, dan tombol akses cepat **Galeri Server**.
     - **Mode Client / Uploader (Mobile / Semua Perangkat)**:
       - 🖼️ **Galeri Perangkat & Server Terpadu**:
          - **Indikator Status Visual**: Setiap foto dan video di galeri dilengkapi tanda status di pojok kanan atas:
            - **Centang Hijau (✅)**: File sudah aman tercadangkan di server host.
            - **Tanda Seru Oranye (⚠️)**: File lokal di HP belum tercadangkan ke server.
          - **Filter Cerdas**: Filter instan untuk melihat *Semua*, *Belum Backup (⚠️)*, *Sudah Backup (✅)*, *Foto*, dan *Video*.
          - **Mode Switcher**: Beralih antara **Galeri Perangkat (iPhone)** dan **Galeri Server (Host)** dengan satu sentuhan.
          - **Media Viewer Lengkap & Pemutar Video**:
            - Lightbox interaktif foto (pinch-to-zoom hingga 5x, swipe antarmedia, lembar info detail EXIF & metadata).
            - **Pemutar Video Terintegrasi**: Putar video langsung di aplikasi layaknya galeri bawaan (kontrol play/pause, slider scrubber, cap waktu durasi, dan toggle audio mute).
            - **Aksi Cepat Cadangkan**: Tombol sekali klik di viewer untuk mencadangkan file individual yang bertanda seru langsung ke server.
       - ☁️ **Manajer Cadangan**: Pemindaian galeri lokal, kalkulasi hash cerdas SHA-256 preflight, dan progres upload real-time.
       - ⏱️ **Jadwal & Otomatisasi Sinkronisasi**: Konfigurasi otomatis kapan sinkron berjalan (saat aplikasi dibuka, interval berkala tiap 15m/1jam/24jam, aturan Wi-Fi only). Pengguna **tidak perlu lagi menyentuh aplikasi Files di iPhone/iPad**!

---

## 🚀 Panduan Menjalankan

### A. Menjalankan sebagai Server di Windows PC

Tersedia aplikasi desktop siap pakai **`SamConnectedServer.exe`** di root folder dan **`client/assets/bin/server.exe`**.

#### 🚀 Cara Menjalankan (Sangat Mudah):
Cukup klik ganda (double-click) **`SamConnectedServer.exe`** atau **`start_server.bat`** di folder root proyek.
- **Antarmuka Desktop Native Lengkap**: Jendela aplikasi GUI langsung terbuka (persis seperti di MacBook).
- **Dual-Channel Auto-Discovery**: Memancarkan sinyal server secara aktif di jaringan Wi-Fi lokal melalui **mDNS Zeroconf** (`_photobackup._tcp`) dan **UDP Discovery Beacon** (Port `8088`) sehingga client iPhone/iPad langsung terhubung otomatis tanpa ketik IP.
- **Dashboard Host Server**: Menampilkan alamat IP lokal Wi-Fi fisik (otomatis mengabaikan adapter virtual WSL/Hyper-V/Docker), port `8080`, status disk, dan live console logs.
- **Pemilih Disk / Folder (HDD Picker)**: Anda bisa langsung memilih disk mana saja (`C:`, `D:`, `E:`, `F:`, atau Harddisk Eksternal 2TB/4TB) melalui tombol **"Ganti Folder / Disk"** yang memunculkan dialog Windows Explorer resmi. Lokasi pilihan Anda otomatis tersimpan.
- **Galeri Server (Google Photos-style)**: Dilengkapi tab Galeri bawaan dengan timeline foto/video, filter (Foto, Video, Favorit), search, dan Lightbox Viewer interaktif (zoom, detail EXIF kamera/resolusi/ukuran/SHA-256, unduh file asli, dan hapus).
- **Akses Fleksibel**: Selain lewat jendela aplikasi di Windows, antarmuka ini juga bisa diakses langsung via browser dari laptop/tablet di jaringan Wi-Fi lokal melalui `http://[IP-PC]:8080`.

#### 🛡️ Konfigurasi Windows Firewall (1-Klik):
Jika client belum langsung membaca server di jaringan Wi-Fi, cukup klik kanan dan pilih *Run as Administrator* pada file **`setup_firewall.bat`** untuk membuka port `8080` (TCP) dan `8088` (UDP) secara otomatis.

#### Menjalankan via Command Line (Headless / Mode Server Background):
Jika ingin menjalankan tanpa tampilan antarmuka (mode CLI daemon):
```powershell
.\SamConnectedServer.exe -cli -port 8080 -storage "D:\FotoBackup"
```

### B. Menjalankan sebagai Server di MacBook (macOS)

#### 1. Menggunakan GUI Desktop (Rekomendasi)
```bash
cd client
flutter run -d macos
```
- Pilih **Mode Server / Host Storage**.
- Tentukan direktori penyimpanan (misal folder lokal atau Harddisk eksternal).
- Klik **Nyalakan Server**.

#### 2. Menjalankan Langsung Engine Go (Headless Terminal)
```bash
# Menjalankan binary yang sudah dikompilasi
./client/assets/bin/server_mac -port 8080 -storage ~/Documents/SamBackup

# Atau menjalankan langsung dari source code
cd server
go run ./cmd/api -port 8080 -storage ~/Documents/SamBackup
```

---

### C. Menjalankan sebagai Client di Smartphone (iOS / Android)

1. Jalankan aplikasi client:
```bash
cd client
flutter run -d <device_or_simulator_id>
```
*(Untuk iOS: buka file `client/ios/Runner.xcworkspace` di Xcode dan tekan Run).*

2. Pada onboarding, pilih **Mode Client / Uploader**.
3. Aplikasi akan mendeteksi server secara otomatis via mDNS atau Anda dapat memasukkan alamat server (misal: `http://<IP_PC_WINDOWS>:8080/api/v1`).
4. Berikan izin akses foto dan tekan **Mulai Cadangkan Sekarang**.

---

## 📡 API Endpoints (v1)

| Method | Endpoint | Deskripsi |
|---|---|---|
| `GET` | `/api/v1/ping` | Healthcheck server & metrik kapasitas disk |
| `POST` | `/api/v1/sync/preflight` | Pengecekan hash SHA-256 file (apakah sudah ada di server) |
| `POST` | `/api/v1/sync/upload` | Upload streaming media foto/video (Multipart, max 4GB) |
| `GET` | `/api/v1/medias` | Daftar media tersimpan terpaginasi |
| `GET` | `/api/v1/medias/:id/file` | Download file media asli |
| `GET` | `/api/v1/medias/:id/thumbnail` | Mendapatkan thumbnail gambar |
| `GET` | `/api/v1/metrics/disk` | Informasi real-time kapasitas disk host |

---

## 🛠️ Kompilasi Binary Server (Build dari Source)

Binary siap pakai sudah disertakan di `client/assets/bin/` (`server.exe` untuk Windows dan `server_mac` untuk macOS).
Jika Anda memodifikasi kode Go di folder `server/`, berikut cara mengompilasi ulang:

```powershell
# Untuk Windows (PowerShell / CMD)
cd server
$env:CGO_ENABLED="0"; $env:GOOS="windows"; $env:GOARCH="amd64"
go build -ldflags="-s -w" -o ../client/assets/bin/server.exe ./cmd/api
```

```bash
# Untuk macOS (ARM64 / Apple Silicon)
cd server
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o ../client/assets/bin/server_mac ./cmd/api

# Untuk Linux (x64)
cd server
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ../client/assets/bin/server_linux ./cmd/api
```

---

## 💡 Tentang Sam Connected (About)

### 🌟 Latar Belakang & Filosofi
Di era digital saat ini, kamera smartphone menghasilkan ribuan foto dan video beresolusi tinggi (4K/ProRes) yang cepat memenuhi memori perangkat. Solusi cloud komersial (seperti Google Photos, Apple iCloud, atau Dropbox) menghadirkan tantangan:
- **Biaya Langganan Bulanan**: Biaya storage terus membengkak seiring bertambahnya koleksi foto keluarga Anda.
- **Kekhawatiran Privasi**: Foto dan kenangan pribadi tersimpan di server pihak ketiga yang rentan pemindaian data atau kebocoran privasi.
- **Keterbatasan Bandwidth Internet**: Mengunggah video puluhan gigabyte melalui internet publik lambat dan memakan kuota.

**Sam Connected** hadir sebagai solusi **Local-First & Self-Hosted Photo Backup** yang mengubah laptop atau PC rumah Anda (MacBook, Windows, atau Mini PC) menjadi *private cloud storage* mandiri.

---

### ✨ Keunggulan Utama

- **🚀 Kecepatan Penuh Jaringan Lokal (LAN / Wi-Fi 6)**: Pencadangan berjalan melalui jalur Wi-Fi lokal berkecepatan tinggi tanpa bergantung pada kecepatan upload internet ISP.
- **🔒 100% Privasi & Tanpa Biaya Langganan**: Foto dan video Anda tidak pernah meninggalkan rumah Anda. Tidak ada biaya bulanan, cukup gunakan harddisk atau SSD yang Anda miliki.
- **🧠 Deduplikasi Cerdas (Streaming SHA-256 Preflight)**: Setiap foto diperiksa hash-nya terlebih dahulu. Jika file sudah pernah dicadangkan, file tidak akan diunggah ulang—menghemat waktu, baterai, dan ruang harddisk.
- **🌐 Zero-Configuration Discovery (mDNS Zeroconf)**: Begitu aplikasi dibuka di HP, server MacBook/PC Anda akan otomatis terdeteksi via protokol `_photobackup._tcp` tanpa perlu repot mengetik IP manual.
- **📂 Struktur File Rapi & Tanpa Vendor Lock-In**:
  File disimpan dalam struktur hierarki yang bersih:
  ```text
  storage/
  └── {device_id}/
      └── {YYYY}/
          └── {MM}/
              ├── {sha256_hash}.jpg
              └── {sha256_hash}.mp4
  ```
  Anda dapat membuka, menyalin, dan memindahkan foto langsung dari Finder atau Windows Explorer kapan saja tanpa aplikasi khusus.
- **🖼️ Auto-Generated Thumbnail & EXIF Parsing**: Server Go secara otomatis membuat thumbnail optimal dan membaca metadata tanggal pengambilan foto dari tag EXIF.

---

## 👨‍💻 Kontributor & Pengembang
- **Pengembang**: Sam Tigis ([@samtigis](https://github.com/samtigis))
- **Proyek**: Sam Connected Local Auto-Backup System

---

## 📄 Lisensi
Hak Cipta © 2026 Sam Connected. Dilindungi undang-undang.

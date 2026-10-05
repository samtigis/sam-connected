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
     - **Mode Server / Host Storage (Desktop Only)**: Manajemen storage harddisk, kontrol engine daemon sidecar, pemantauan kapasitas HDD, dan live log aktivitas.
     - **Mode Client / Uploader (Mobile / Semua Perangkat)**: Pemindaian galeri lokal, kalkulasi hash cerdas, preflight check ke server, dan pencadangan otomatis foto/video.

---

## 🚀 Panduan Menjalankan

### A. Menjalankan sebagai Server di MacBook (macOS)

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

### B. Menjalankan sebagai Client di iPhone (iOS / Simulator)

1. Jalankan aplikasi client:
```bash
cd client
flutter run -d <device_or_simulator_id>
```
*(Atau buka file `client/ios/Runner.xcworkspace` di Xcode dan tekan Run).*

2. Pada onboarding, pilih **Mode Client / Uploader**.
3. Aplikasi akan mendeteksi server secara otomatis via mDNS atau Anda dapat memasukkan alamat server (misal: `http://<IP_MACBOOK>:8080/api/v1`).
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

## 🛠️ Kompilasi Binary Server

Jika Anda memodifikasi kode Go di folder `server/`, kompilasi ulang binary ke folder assets client:

```bash
# Untuk macOS (ARM64 / Apple Silicon)
cd server
go build -o ../client/assets/bin/server_mac ./cmd/api

# Untuk Windows (x64)
GOOS=windows GOARCH=amd64 go build -o ../client/assets/bin/server.exe ./cmd/api

# Untuk Linux (x64)
GOOS=linux GOARCH=amd64 go build -o ../client/assets/bin/server_linux ./cmd/api
```

---

## 📄 Lisensi
Hak Cipta © 2026 Sam Connected.

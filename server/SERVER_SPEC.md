# Sam Connected - Server Specification & Sidecar Integration Guide

Dokumentasi arsitektur, spesifikasi API, dan panduan kompilasi headless binary untuk **Sam Connected Auto-Backup Engine**.

---

## 1. Arsitektur & Struktur Direktori

Engine backend Go dirancang dengan arsitektur modular, hemat memori (streaming I/O tanpa buffering file besar di RAM), dan bebas CGO (*CGO-free SQLite*) sehingga dapat di-cross-compile ke berbagai platform secara instan.

```
server/
├── cmd/
│   └── api/
│       └── main.go              # Entry point daemon, routing, CLI flags, graceful shutdown
├── internal/
│   ├── database/
│   │   ├── db.go                # SQLite pure-Go connection & PRAGMA WAL optimization
│   │   └── schema.go            # GORM Media entity schema
│   ├── discovery/
│   │   └── mdns.go              # mDNS Zeroconf broadcaster (_photobackup._tcp)
│   ├── handler/
│   │   ├── health.go            # GET /api/v1/ping & monitor disk dinamis
│   │   ├── media.go             # Media query cursor pagination, thumbnail & raw stream
│   │   └── sync.go              # Preflight hash check & streaming multipart upload
│   └── service/
│       ├── disk.go              # Cross-platform disk space interface
│       ├── disk_unix.go         # Implementasi syscall Statfs (macOS / Linux)
│       ├── disk_windows.go      # Implementasi Win32 GetDiskFreeSpaceExW (Windows)
│       ├── hasher.go            # SHA-256 stream hasher
│       ├── storage.go           # File management, path partitioning, background worker
│       └── thumbnail.go         # Image resize 400px & Safe EXIF parsing
├── go.mod
├── go.sum
└── SERVER_SPEC.md
```

---

## 2. Struktur Penyimpanan File (Storage Hierarchy)

File media disimpan secara terorganisir berdasarkan identitas perangkat dan waktu pengambilan:

```
storage/
├── sam_backup.db                # SQLite database (WAL mode aktif)
├── sam_backup.db-wal
├── sam_backup.db-shm
├── .tmp/                        # Direktori sementara saat upload streaming
└── {device_id}/
    ├── thumbnails/
    │   └── {hash}.jpg           # Thumbnail terkompresi (max-width 400px)
    └── {YYYY}/
        └── {MM}/
            └── {hash}.ext       # File asli (nama file berdasarkan SHA-256 checksum)
```

---

## 3. Spesifikasi API RESTful

Base URL: `http://<HOST>:<PORT>/api/v1`

### 3.1 `GET /api/v1/ping`
Digunakan oleh antarmuka Flutter untuk health check berkala dan mengetahui kapasitas sisa penyimpanan harddisk host secara real-time.

* **Response (200 OK):**
```json
{
  "status": "ok",
  "service": "sam-connected-backup",
  "version": "1.0.0",
  "uptime_seconds": 3600,
  "server_time": "2026-10-05T10:15:30Z",
  "disk": {
    "total_bytes": 1000204886016,
    "free_bytes": 512400128000,
    "available_bytes": 498200100000,
    "used_bytes": 487804758016,
    "used_percent": 48.77
  }
}
```

---

### 3.2 `POST /api/v1/sync/preflight`
Sebelum client mengirim file berukuran besar, client mengirimkan daftar hash SHA-256 file lokal. Server akan memfilter dan hanya mengembalikan hash yang **belum tersimpan** di database (deduplikasi kilat).

* **Header:** `Content-Type: application/json`
* **Request Body:**
```json
{
  "device_id": "iphone-sigit-01",
  "hashes": [
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e"
  ]
}
```
* **Response (200 OK):**
```json
{
  "missing_hashes": [
    "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e"
  ],
  "existing_count": 1,
  "missing_count": 1,
  "total_checked": 2
}
```

---

### 3.3 `POST /api/v1/sync/upload`
Menerima file streaming multipart. Server menghitung hash SHA-256 secara langsung sewaktu byte stream masuk (*zero-double-buffering*) dan menyimpannya ke `./storage/{device_id}/{YYYY}/{MM}/{hash}.ext`. Thumbnail dibuat secara asinkron (*non-blocking*).

* **Header:** `Content-Type: multipart/form-data`
* **Form Data:**
  - `file`: Binary file stream (foto / video, maksimal 4GB).
  - `device_id`: String ID perangkat pengirim (contoh: `samsung-s23-sigit`).
  - `client_hash`: *(Opsional)* SHA-256 dari client untuk validasi integritas checksum.
  - `taken_at`: *(Opsional)* Format ISO-8601 `2026-10-05T12:00:00Z` jika tersedia.
* **Response (201 Created):**
```json
{
  "message": "media stored successfully",
  "media": {
    "id": 142,
    "device_id": "samsung-s23-sigit",
    "hash": "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e",
    "file_name": "IMG_20261005_120000.jpg",
    "file_path": "/storage/samsung-s23-sigit/2026/10/a591a6d4...jpg",
    "has_thumbnail": false,
    "file_size": 4194304,
    "mime_type": "image/jpeg",
    "extension": ".jpg",
    "taken_at": "2026-10-05T12:00:00Z",
    "created_at": "2026-10-05T12:00:05Z",
    "updated_at": "2026-10-05T12:00:05Z"
  }
}
```

---

### 3.4 `GET /api/v1/media`
Cursor pagination untuk menelusuri galeri metadata foto dan video secara efisien tanpa lag query offset.

* **Query Parameters:**
  - `cursor`: ID media terakhir yang diterima (default `0`).
  - `limit`: Jumlah per halaman (default `50`, max `200`).
  - `device_id`: *(Opsional)* Filter berdasarkan perangkat tertentu.
  - `order`: `desc` (terbaru, default) atau `asc` (terlama).
* **Response (200 OK):**
```json
{
  "data": [
    {
      "id": 142,
      "device_id": "samsung-s23-sigit",
      "hash": "a591a6d4...",
      "file_name": "IMG_20261005_120000.jpg",
      "has_thumbnail": true,
      "width": 4032,
      "height": 3024,
      "file_size": 4194304,
      "mime_type": "image/jpeg",
      "extension": ".jpg",
      "taken_at": "2026-10-05T12:00:00Z",
      "created_at": "2026-10-05T12:00:05Z"
    }
  ],
  "count": 1,
  "next_cursor": 142,
  "has_more": false
}
```

---

### 3.5 `GET /api/v1/media/:id/thumb`
Mengalirkan thumbnail gambar beresolusi 400px dengan header caching performa tinggi:
* **Headers:**
  - `Cache-Control: public, max-age=31536000, immutable`
  - `ETag: W/"thumb-<hash>"`
* **Dukungan 304 Not Modified:** Jika client mengirim header `If-None-Match`, server merespons instan `304 Not Modified` tanpa transfer data ulang.

---

### 3.6 `GET /api/v1/media/:id/raw`
Mengalirkan file asli dengan dukungan **HTTP Byte-Range (`Accept-Ranges: bytes`)** untuk pemutaran video langsung di antarmuka Flutter/Video Player tanpa perlu download penuh.

---

## 4. Panduan Kompilasi Headless Binary

Karena server ini menggunakan SQLite pure-Go (`github.com/glebarez/sqlite`), Anda **TIDAK memerlukan GCC atau toolchain C** untuk cross-compile!

Jalankan perintah ini dari dalam folder `server/`:

### A. Kompilasi untuk macOS (Intel & Apple Silicon Universal Binary)
```bash
# 1. Kompilasi Apple Silicon (M1/M2/M3/M4)
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o server_mac_arm64 ./cmd/api

# 2. Kompilasi Intel Mac (x86_64)
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o server_mac_x86 ./cmd/api

# 3. Gabungkan menjadi Universal Binary (Opsional tapi direkomendasikan untuk macOS App bundle)
lipo -create -output server_mac server_mac_arm64 server_mac_x86
chmod +x server_mac
```

### B. Kompilasi untuk Windows (`server.exe` Headless)
Agar binary berjalan sebagai background daemon tanpa memunculkan jendela hitam Command Prompt di Windows, gunakan flag `-H=windowsgui`:

```bash
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags="-s -w -H=windowsgui" -o server.exe ./cmd/api
```
*(Flag `-s -w` menghapus simbol debug sehingga ukuran binary jauh lebih kecil dan cepat dibuka)*.

### C. Kompilasi untuk Linux
```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o server_linux ./cmd/api
chmod +x server_linux
```

---

## 5. Integrasi Sidecar Daemon dengan Flutter Desktop

Aplikasi Flutter Desktop (macOS / Windows) mengendalikan lifecycle daemon Go secara transparan melalui `dart:io`.

### 5.1 Contoh Implementasi Dart Sidecar Manager

```dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class BackendSidecarManager {
  Process? _serverProcess;
  final int port = 8080;
  final String storagePath;

  BackendSidecarManager({required this.storagePath});

  /// Memulai background engine
  Future<bool> startServer() async {
    String executableName;
    if (Platform.isWindows) {
      executableName = 'server.exe';
    } else if (Platform.isMacOS) {
      executableName = 'server_mac';
    } else {
      executableName = 'server_linux';
    }

    // Path ke binary di dalam assets / bundle aplikasi Flutter
    final binaryPath = '${Directory.current.path}/assets/bin/$executableName';

    try {
      _serverProcess = await Process.start(
        binaryPath,
        [
          '-port', '$port',
          '-storage', storagePath,
          '-mdns-name', 'SamConnectedHost',
        ],
        mode: ProcessStartMode.normal,
      );

      // Tangkap log engine untuk debug
      _serverProcess!.stdout
          .transform(utf8.decoder)
          .listen((data) => print('[Go Engine stdout]: $data'));

      _serverProcess!.stderr
          .transform(utf8.decoder)
          .listen((data) => print('[Go Engine stderr]: $data'));

      // Tunggu hingga server siap (Health check polling)
      return await _waitForHealthy(retries: 20, delayMs: 250);
    } catch (e) {
      print('Gagal menjalankan Go server: $e');
      return false;
    }
  }

  /// Health check polling
  Future<bool> _waitForHealthy({int retries = 20, int delayMs = 250}) async {
    for (int i = 0; i < retries; i++) {
      await Future.delayed(Duration(milliseconds: delayMs));
      try {
        final res = await http.get(Uri.parse('http://127.0.0.1:$port/api/v1/ping'));
        if (res.statusCode == 200) {
          print('Go Backup Engine siap menerima koneksi!');
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Mematikan server secara graceful saat aplikasi ditutup
  Future<void> stopServer() async {
    if (_serverProcess != null) {
      _serverProcess!.kill(ProcessSignal.sigterm);
      await _serverProcess!.exitCode;
      _serverProcess = null;
      print('Go Backup Engine berhasil dimatikan.');
    }
  }
}
```

---

## 6. Penemuan Jaringan Otomatis (mDNS / Zeroconf Discovery)

Engine Go secara otomatis mem-broadcast service:
- **Service Name:** `_photobackup._tcp`
- **Domain:** `local.`
- **Port:** `8080` (atau port dinamis yang dikonfigurasi)
- **TXT Records:** `version=1.0`, `path=/api/v1`, `app=sam-connected`

Pada aplikasi Flutter Client (misalnya di smartphone Android/iOS), gunakan library Flutter mDNS (seperti package `nsd` atau `bonsoir`) untuk menemukan server ini di jaringan Wi-Fi lokal tanpa perlu memasukkan IP address manual.

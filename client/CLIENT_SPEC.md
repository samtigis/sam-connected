# Sam Connected Client - Architecture & Native Configuration Guide

Panduan teknis arsitektur aplikasi Flutter **Unified Dual-Mode**, konfigurasi perizinan native (Android, iOS, macOS, Windows), logika anti-duplikasi, dan manajemen sidecar server.

---

## 1. Konsep Arsitektur Unified Dual-Mode

Aplikasi ini menggunakan satu codebase tunggal multiplatform yang dapat berperan ganda sesuai pilihan pengguna pada saat *Onboarding* pertama kali:

```
                          [App Launch]
                               │
                    SharedPreferences Check
                               │
            ┌──────────────────┴──────────────────┐
     [Role: Unselected]                    [Role Configured]
            │                                     │
   RoleSelectionScreen              ┌─────────────┴─────────────┐
(Pilih Server vs Client)            │                           │
                            [Server Host]               [Client Uploader]
                                    │                           │
                          ServerDashboardScreen         ClientSyncScreen
                          (Process.start daemon)       (Scan, Hash, Upload)
```

1. **Mode Server / Host Storage (Desktop Only - Windows & macOS):**
   * Mengontrol binary daemon Go di latar belakang (`Process.start`).
   * Menentukan folder penyimpanan (misal HDD Eksternal 2TB).
   * Menampilkan metrik kapasitas disk dinamis, IP host, status mDNS, dan log koneksi masuk.
2. **Mode Client / Uploader (Android, iOS, Desktop):**
   * Memindai foto & video galeri secara bertahap (*paginated scanning*).
   * Smart Hashing hemat baterai untuk file video besar.
   * Melakukan *pre-flight check* batch (50 hash) ke server untuk deduplikasi instan.
   * Mengunggah hanya file yang belum ada di server melalui streaming multipart.

---

## 2. Logika Anti-Duplikasi & Smart Hashing

### 2.1 Alur Anti-Duplikasi Client
1. **Langkah 1 (Lokal SQLite):** Cek apakah ID aset galeri atau hash-nya sudah berstatus `synced` di database SQLite lokal perangkat (`local_sync_index.db`). Jika ya, lewati tanpa hashing ulang.
2. **Langkah 2 (Smart Hasher):**
   * **Foto (< 50MB):** Dihitung hash SHA-256 stream penuh dari byte gambar.
   * **Video (>= 50MB):** Menggunakan formula hemat daya tanpa membaca seluruh file ke RAM:
     $$\text{Hash} = \text{SHA256}(\text{"fastvideo:"} + \text{Ukuran File} + \text{64KB Awal} + \text{64KB Akhir})$$
3. **Langkah 3 (Pre-flight Check Batch):** Mengirim array hingga 50 hash sekaligus ke `POST /api/v1/sync/preflight`.
   * Jika hash sudah ada di server: SQLite lokal langsung di-update menjadi `synced` tanpa upload!
   * Jika hash belum ada: masukkan ke antrean upload.
4. **Langkah 4 (Upload):** Kirim file via multipart form streaming dengan monitoring persentase byte terkirim.

---

## 3. Konfigurasi Perizinan Native (Mandatory Permissions)

### 3.1 Android (`android/app/src/main/AndroidManifest.xml`)

Buka `android/app/src/main/AndroidManifest.xml` dan tambahkan perizinan berikut di dalam tag `<manifest>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Akses Jaringan & Discovery mDNS -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />

    <!-- Akses Galeri & Media (Android 13+ / API 33+) -->
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />

    <!-- Akses Media untuk Android 12 ke bawah (API <= 32) -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />

    <!-- Background Task (WorkManager saat charging & Wi-Fi) -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

    <application
        android:label="Sam Connected"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true"> <!-- Mengizinkan koneksi HTTP LAN lokal -->
        
        <activity
            android:name=".MainActivity"
            android:exported="true"
            ...>
        </activity>
    </application>
</manifest>
```

---

### 3.2 iOS (`ios/Runner/Info.plist`)

Buka `ios/Runner/Info.plist` dan tambahkan kunci perizinan privasi dan mDNS Bonjour Service:

```xml
<dict>
    <!-- Izin Galeri Foto & Video -->
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Aplikasi membutuhkan izin galeri untuk mencadangkan foto dan video Anda ke Host Storage lokal.</string>
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>Aplikasi membutuhkan izin untuk menyimpan status pencadangan media.</string>

    <!-- Izin Jaringan Lokal (Local Network Permission) -->
    <key>NSLocalNetworkUsageDescription</key>
    <string>Aplikasi membutuhkan akses jaringan lokal untuk menemukan Host Storage Sam Connected via Wi-Fi.</string>

    <!-- Pendaftaran Bonjour Service untuk mDNS Discovery -->
    <key>NSBonjourServices</key>
    <array>
        <string>_photobackup._tcp</string>
    </array>

    <!-- Izinkan koneksi HTTP lokal (App Transport Security) -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
```

---

### 3.3 macOS Entitlements (`macos/Runner/DebugProfile.entitlements` & `Release.entitlements`)

Untuk menjalankan binary server Go dan mengakses disk eksternal (HDD 2TB) di macOS App Sandbox:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Izinkan koneksi jaringan keluar (Client) dan masuk (Server Host) -->
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>

    <!-- Izinkan pengguna memilih folder penyimpanan eksternal (HDD 2TB) -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <!-- Izinkan akses library foto/video pengguna jika dalam mode Client -->
    <key>com.apple.security.assets.movies.read-write</key>
    <true/>
    <key>com.apple.security.assets.pictures.read-write</key>
    <true/>
</dict>
</plist>
```

---

## 4. Panduan Menjalankan Aplikasi Flutter

### Menyiapkan Dependensi:
```bash
cd client
flutter pub get
```

### Menempatkan Binary Server Go untuk Mode Desktop:
Sebelum menjalankan aplikasi Flutter Desktop dalam mode Server, pastikan binary server Go sudah dikompilasi ke folder `assets/bin/`:
```bash
# Dari root project:
cd server
# Kompilasi macOS
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o ../client/assets/bin/server_mac ./cmd/api
# Kompilasi Windows
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags="-s -w -H=windowsgui" -o ../client/assets/bin/server.exe ./cmd/api
```

### Menjalankan di Perangkat / Emulator:
```bash
# Menjalankan di macOS Desktop
flutter run -d macos

# Menjalankan di Windows Desktop
flutter run -d windows

# Menjalankan di Android Phone
flutter run -d android
```

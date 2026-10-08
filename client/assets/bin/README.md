# Server Binary Assets Directory

Tempatkan file binary daemon Go hasil kompilasi dari folder `server/` di sini agar dapat dipanggil secara otomatis oleh Flutter Desktop via `Process.start()`:

- **macOS:** `server_mac` (Prebuilt siap pakai)
- **Windows:** `server.exe` (Prebuilt siap pakai)
- **Linux:** `server_linux`

### Perintah Kompilasi Ulang (dari root server):
```bash
# Untuk Windows (PowerShell)
$env:CGO_ENABLED="0"; $env:GOOS="windows"; $env:GOARCH="amd64"
go build -ldflags="-s -w" -o ../client/assets/bin/server.exe ./cmd/api

# Untuk macOS
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o ../client/assets/bin/server_mac ./cmd/api

# Untuk Linux
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ../client/assets/bin/server_linux ./cmd/api
```

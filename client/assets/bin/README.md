# Server Binary Assets Directory

Tempatkan file binary daemon Go hasil kompilasi dari folder `server/` di sini agar dapat dipanggil secara otomatis oleh Flutter Desktop via `Process.start()`:

- **macOS:** `server_mac` (atau `server_mac_arm64`)
- **Windows:** `server.exe`
- **Linux:** `server_linux`

### Perintah Kompilasi Cepat (dari root server):
```bash
# Untuk macOS
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o ../client/assets/bin/server_mac ./cmd/api

# Untuk Windows
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags="-s -w -H=windowsgui" -o ../client/assets/bin/server.exe ./cmd/api
```

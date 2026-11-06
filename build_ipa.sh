#!/bin/bash
set -e

# ==============================================================================
# Sam Connected - iOS IPA Builder for AltStore & Sideloading
# ==============================================================================

# Ensure standard tools, Flutter, and Xcode are in PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:/Users/user/development/flutter/bin:$PATH"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$PROJECT_ROOT/client"
DIST_DIR="$PROJECT_ROOT/dist"
IPA_NAME="SamConnected.ipa"
IPA_PATH="$DIST_DIR/$IPA_NAME"
TEMP_BUILD_DIR="$PROJECT_ROOT/build_temp"

echo "=========================================================="
echo "  🚀 Memulai Pembuatan IPA Sam Connected untuk AltStore"
echo "=========================================================="
echo "📂 Direktori Proyek: $PROJECT_ROOT"
echo "📱 Target: $IPA_PATH"
echo ""

# 1. Validasi Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Error: Flutter tidak ditemukan di PATH."
    echo "Pastikan Flutter sudah terpasang di sistem."
    exit 1
fi

# 2. Update dependencies
echo "📦 1/4 Mengambil dependensi Flutter (flutter pub get)..."
cd "$CLIENT_DIR"
flutter pub get

# 3. Build iOS Release (tanpa code-signing karena AltStore yang akan melakukan signing)
echo ""
echo "⚙️ 2/4 Melakukan kompilasi iOS Release binary (tanpa code-signing)..."
flutter build ios --release --no-codesign

# 4. Packaging ke format .ipa
echo ""
echo "📦 3/4 Mengemas Runner.app menjadi $IPA_NAME..."
mkdir -p "$DIST_DIR"
rm -rf "$TEMP_BUILD_DIR"
mkdir -p "$TEMP_BUILD_DIR/Payload"

# Copy Runner.app ke Payload
cp -R "$CLIENT_DIR/build/ios/iphoneos/Runner.app" "$TEMP_BUILD_DIR/Payload/"

# Zip Payload ke format .ipa
cd "$TEMP_BUILD_DIR"
zip -r -q "$IPA_PATH" Payload

# Bersihkan temporary build directory
rm -rf "$TEMP_BUILD_DIR"

echo ""
echo "=========================================================="
echo "  ✅ BERHASIL MEMBUAT IPA UNTUK ALTSTORE!"
echo "=========================================================="
echo "📍 File IPA: $IPA_PATH"
echo "📏 Ukuran File: $(du -sh "$IPA_PATH" | cut -f1)"
echo ""
echo "📲 CARA PASANG KE IPHONE VIA ALTSTORE:"
echo "1. Pastikan AltServer aktif di Mac (ikon AltServer di Menu Bar atas)."
echo "2. Hubungkan iPhone ke Mac (lewat kabel Lightning/USB-C atau Wi-Fi yang sama)."
echo "3. Kirim file '$IPA_NAME' ke iPhone:"
echo "   - Bisa via AirDrop langsung ke iPhone, ATAU"
echo "   - Simpan ke iCloud Drive / Google Drive / aplikasi Files di iPhone."
echo "4. Di iPhone:"
echo "   - Buka aplikasi AltStore."
echo "   - Masuk ke tab 'My Apps'."
echo "   - Tekan tanda tambah (+) di pojok kiri atas."
echo "   - Pilih file '$IPA_NAME'."
echo "5. AltStore akan me-resign dan menginstall aplikasi ke iPhone Anda!"
echo "   Aplikasi akan otomatis di-refresh sertifikatnya setiap 7 hari oleh AltStore."
echo "=========================================================="

# Buka folder output di Finder agar user langsung bisa AirDrop ke iPhone
open -R "$IPA_PATH" 2>/dev/null || true

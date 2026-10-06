//go:build windows

package gui

import (
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"net"
	"os/exec"
	"path/filepath"
	"strings"
	"unicode/utf16"
)

// PickFolderDialog opens native Windows FolderBrowserDialog
func PickFolderDialog(initialDir string) (string, error) {
	script := fmt.Sprintf(`
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "Pilih Lokasi Penyimpanan Cadangan Foto & Video (HDD / SSD)"
$dialog.ShowNewFolderButton = $true
if ("%s" -ne "") { $dialog.SelectedPath = "%s" }
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::WriteLine($dialog.SelectedPath)
}
`, strings.ReplaceAll(initialDir, `"`, `\"`), strings.ReplaceAll(initialDir, `"`, `\"`))

	utf16Runes := utf16.Encode([]rune(script))
	bytes := make([]byte, len(utf16Runes)*2)
	for i, v := range utf16Runes {
		binary.LittleEndian.PutUint16(bytes[i*2:], v)
	}
	encoded := base64.StdEncoding.EncodeToString(bytes)

	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", encoded)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}

	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "<") || strings.HasPrefix(trimmed, "#") || trimmed == "" {
			continue
		}
		return trimmed, nil
	}
	return "", nil
}

// OpenFolderInExplorer launches Windows Explorer focused on the specified folder
func OpenFolderInExplorer(path string) error {
	cleanPath := filepath.Clean(path)
	cmd := exec.Command("explorer.exe", cleanPath)
	return cmd.Start()
}

// GetLocalIPv4 returns the first non-loopback IPv4 address
func GetLocalIPv4() string {
	interfaces, err := net.Interfaces()
	if err != nil {
		return "127.0.0.1"
	}

	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip != nil && !ip.IsLoopback() && ip.To4() != nil {
				return ip.String()
			}
		}
	}
	return "127.0.0.1"
}

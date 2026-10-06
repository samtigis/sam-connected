//go:build !windows

package gui

import (
	"errors"
	"net"
	"os/exec"
)

// PickFolderDialog dummy stub for non-windows
func PickFolderDialog(initialDir string) (string, error) {
	return "", errors.New("native dialog only supported on Windows")
}

// OpenFolderInExplorer dummy stub for non-windows
func OpenFolderInExplorer(path string) error {
	cmd := exec.Command("open", path)
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

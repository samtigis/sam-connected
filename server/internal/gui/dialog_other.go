//go:build !windows

package gui

import (
	"errors"
	"os/exec"

	"github.com/samtigis/sam-connected/server/internal/discovery"
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

// OpenFileInDefaultApp launches default application on macOS / Linux
func OpenFileInDefaultApp(path string) error {
	cmd := exec.Command("open", path)
	return cmd.Start()
}

// GetLocalIPv4 returns the prioritized physical LAN IPv4 address
func GetLocalIPv4() string {
	return discovery.GetBestLocalIPv4()
}

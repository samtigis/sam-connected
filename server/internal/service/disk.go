package service

import (
	"os"
	"path/filepath"
)

// DiskStatus holds storage partition usage details in bytes and percentage.
type DiskStatus struct {
	TotalBytes     uint64  `json:"total_bytes"`
	FreeBytes      uint64  `json:"free_bytes"`
	AvailableBytes uint64  `json:"available_bytes"`
	UsedBytes      uint64  `json:"used_bytes"`
	UsedPercent    float64 `json:"used_percent"`
}

// GetDirectoryDiskStatus resolves closest existing ancestor path and queries partition usage.
func GetDirectoryDiskStatus(targetPath string) (DiskStatus, error) {
	absPath, err := filepath.Abs(targetPath)
	if err != nil {
		absPath = targetPath
	}

	curr := absPath
	for {
		if _, err := os.Stat(curr); err == nil {
			break
		}
		parent := filepath.Dir(curr)
		if parent == curr {
			break
		}
		curr = parent
	}

	return getDiskUsage(curr)
}

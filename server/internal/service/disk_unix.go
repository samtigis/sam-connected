//go:build !windows

package service

import (
	"syscall"
)

func getDiskUsage(path string) (DiskStatus, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return DiskStatus{}, err
	}

	bsize := uint64(stat.Bsize)
	total := stat.Blocks * bsize
	free := stat.Bfree * bsize
	avail := stat.Bavail * bsize
	used := total - free

	var percent float64
	if total > 0 {
		percent = (float64(used) / float64(total)) * 100.0
	}

	return DiskStatus{
		TotalBytes:     total,
		FreeBytes:      free,
		AvailableBytes: avail,
		UsedBytes:      used,
		UsedPercent:    percent,
	}, nil
}

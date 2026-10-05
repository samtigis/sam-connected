//go:build windows

package service

import (
	"syscall"
	"unsafe"
)

var (
	kernel32            = syscall.NewLazyDLL("kernel32.dll")
	getDiskFreeSpaceExW = kernel32.NewProc("GetDiskFreeSpaceExW")
)

func getDiskUsage(path string) (DiskStatus, error) {
	var freeBytesAvailable, totalNumberOfBytes, totalNumberOfFreeBytes uint64

	pathPtr, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return DiskStatus{}, err
	}

	r1, _, callErr := getDiskFreeSpaceExW.Call(
		uintptr(unsafe.Pointer(pathPtr)),
		uintptr(unsafe.Pointer(&freeBytesAvailable)),
		uintptr(unsafe.Pointer(&totalNumberOfBytes)),
		uintptr(unsafe.Pointer(&totalNumberOfFreeBytes)),
	)

	if r1 == 0 {
		return DiskStatus{}, callErr
	}

	used := totalNumberOfBytes - totalNumberOfFreeBytes
	var percent float64
	if totalNumberOfBytes > 0 {
		percent = (float64(used) / float64(totalNumberOfBytes)) * 100.0
	}

	return DiskStatus{
		TotalBytes:     totalNumberOfBytes,
		FreeBytes:      totalNumberOfFreeBytes,
		AvailableBytes: freeBytesAvailable,
		UsedBytes:      used,
		UsedPercent:    percent,
	}, nil
}

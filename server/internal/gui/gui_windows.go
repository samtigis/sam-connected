//go:build windows

package gui

import (
	"log"
	"syscall"

	"github.com/jchv/go-webview2"
)

var (
	kernel32         = syscall.NewLazyDLL("kernel32.dll")
	user32           = syscall.NewLazyDLL("user32.dll")
	getConsoleWindow = kernel32.NewProc("GetConsoleWindow")
	showWindow       = user32.NewProc("ShowWindow")
)

// HideConsoleWindow hides the Windows terminal/console window if present
func HideConsoleWindow() {
	hwnd, _, _ := getConsoleWindow.Call()
	if hwnd != 0 {
		showWindow.Call(hwnd, 0) // SW_HIDE = 0
	}
}

// LaunchGUI initializes and opens the native Windows WebView2 application window
func LaunchGUI(url string, initialStorage string, onSelectFolder func() string, onOpenExplorer func(path string), onExit func()) {
	// Hide black console window so only the GUI appears
	HideConsoleWindow()

	w := webview2.New(false)
	if w == nil {
		log.Printf("[WARN] WebView2 is not available on this machine. Falling back to background server.")
		return
	}
	defer w.Destroy()

	w.SetTitle("Sam Connected - Host Storage Server")
	w.SetSize(1200, 820, webview2.HintNone)

	// Bind native functions to JavaScript window object
	if onSelectFolder != nil {
		_ = w.Bind("nativeSelectFolder", onSelectFolder)
	}
	if onOpenExplorer != nil {
		_ = w.Bind("nativeOpenExplorer", onOpenExplorer)
	}

	w.Navigate(url)
	w.Run()

	if onExit != nil {
		onExit()
	}
}

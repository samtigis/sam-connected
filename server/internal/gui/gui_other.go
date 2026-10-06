//go:build !windows

package gui

// HideConsoleWindow stub for non-windows
func HideConsoleWindow() {}

// LaunchGUI stub for non-windows
func LaunchGUI(url string, initialStorage string, onSelectFolder func() string, onOpenExplorer func(path string), onExit func()) {
	// No-op on non-windows
}

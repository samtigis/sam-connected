package logbuffer

import (
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

// LogEntry represents an individual log line with timestamp.
type LogEntry struct {
	Timestamp string `json:"timestamp"`
	Message   string `json:"message"`
}

// Buffer holds an in-memory circular list of recent log lines.
type Buffer struct {
	mu      sync.RWMutex
	entries []LogEntry
	maxSize int
}

// Global default buffer
var DefaultBuffer = NewBuffer(250)

// NewBuffer creates a new Buffer with maximum capacity.
func NewBuffer(maxSize int) *Buffer {
	return &Buffer{
		entries: make([]LogEntry, 0, maxSize),
		maxSize: maxSize,
	}
}

// Add appends a message to the buffer.
func (b *Buffer) Add(msg string) {
	b.mu.Lock()
	defer b.mu.Unlock()

	entry := LogEntry{
		Timestamp: time.Now().Format("15:04:05"),
		Message:   msg,
	}

	if len(b.entries) >= b.maxSize {
		b.entries = b.entries[1:]
	}
	b.entries = append(b.entries, entry)
}

// GetEntries returns a snapshot of all recorded log entries.
func (b *Buffer) GetEntries() []LogEntry {
	b.mu.RLock()
	defer b.mu.RUnlock()

	out := make([]LogEntry, len(b.entries))
	copy(out, b.entries)
	return out
}

// Clear clears the buffer.
func (b *Buffer) Clear() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.entries = b.entries[:0]
}

// Writer wraps standard io.Writer and intercepts writes to the buffer.
type Writer struct {
	buffer *Buffer
	dest   io.Writer
}

// NewWriter creates an io.Writer that duplicates output to stdout and the buffer.
func NewWriter(b *Buffer, dest io.Writer) *Writer {
	if dest == nil {
		dest = os.Stdout
	}
	return &Writer{
		buffer: b,
		dest:   dest,
	}
}

func (w *Writer) Write(p []byte) (n int, err error) {
	if w.dest != nil {
		// Ignore write errors to stdout/stderr in Windows GUI subsystem
		_, _ = w.dest.Write(p)
	}
	msg := string(p)
	// Remove trailing newline for cleaner GUI display
	if len(msg) > 0 && msg[len(msg)-1] == '\n' {
		msg = msg[:len(msg)-1]
	}
	if len(msg) > 0 && msg[len(msg)-1] == '\r' {
		msg = msg[:len(msg)-1]
	}
	if msg != "" {
		w.buffer.Add(msg)
	}
	return len(p), nil
}

// Logf formats and adds to DefaultBuffer directly.
func Logf(format string, a ...interface{}) {
	msg := fmt.Sprintf(format, a...)
	DefaultBuffer.Add(msg)
}

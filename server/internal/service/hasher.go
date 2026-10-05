package service

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
)

// Hasher provides SHA-256 computation utilities.
type Hasher struct{}

// NewHasher returns a new instance of Hasher.
func NewHasher() *Hasher {
	return &Hasher{}
}

// ComputeSHA256 reads from r until EOF and returns hex-encoded SHA-256 and total bytes read.
func (h *Hasher) ComputeSHA256(r io.Reader) (string, int64, error) {
	hasher := sha256.New()
	written, err := io.Copy(hasher, r)
	if err != nil {
		return "", 0, fmt.Errorf("failed to compute hash from stream: %w", err)
	}
	return hex.EncodeToString(hasher.Sum(nil)), written, nil
}

// ComputeFileSHA256 opens the specified file and computes its SHA-256 hash.
func (h *Hasher) ComputeFileSHA256(filePath string) (string, int64, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", 0, fmt.Errorf("failed to open file %s for hashing: %w", filePath, err)
	}
	defer f.Close()

	return h.ComputeSHA256(f)
}

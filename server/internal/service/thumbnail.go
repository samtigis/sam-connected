package service

import (
	"fmt"
	"image"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/disintegration/imaging"
	"github.com/rwcarlsen/goexif/exif"
)

// ThumbnailService handles image resizing, thumbnail creation, and safe EXIF extraction.
type ThumbnailService struct {
	MaxWidth int
	Quality  int
}

// ImageMeta holds parsed dimensions and capture time.
type ImageMeta struct {
	Width   int
	Height  int
	TakenAt *time.Time
}

// NewThumbnailService creates a new ThumbnailService with default max width 400px.
func NewThumbnailService() *ThumbnailService {
	return &ThumbnailService{
		MaxWidth: 400,
		Quality:  80,
	}
}

// ExtractExifTime safely parses EXIF date/time from an image file.
// Returns nil if file is not JPEG or has no valid EXIF timestamp.
func (s *ThumbnailService) ExtractExifTime(filePath string) *time.Time {
	f, err := os.Open(filePath)
	if err != nil {
		return nil
	}
	defer f.Close()

	x, err := exif.Decode(f)
	if err != nil {
		// Non-JPEG, no EXIF, or malformed header - safely ignored
		return nil
	}

	tm, err := x.DateTime()
	if err != nil {
		return nil
	}

	return &tm
}

// GenerateThumbnail resizes the source image to max width 400px and saves as JPEG thumbnail.
func (s *ThumbnailService) GenerateThumbnail(srcPath, destPath string) (*ImageMeta, error) {
	// Ensure parent directory exists
	if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
		return nil, fmt.Errorf("failed to create thumbnail directory: %w", err)
	}

	// Safely extract EXIF timestamp first
	takenAt := s.ExtractExifTime(srcPath)

	// Decode source image using imaging (supports AutoOrientation, JPEG, PNG, GIF, BMP, TIFF)
	srcImg, err := imaging.Open(srcPath, imaging.AutoOrientation(true))
	if err != nil {
		return nil, fmt.Errorf("imaging.Open failed (possibly unsupported format or video): %w", err)
	}

	bounds := srcImg.Bounds()
	origWidth := bounds.Dx()
	origHeight := bounds.Dy()

	var thumbImg image.Image
	if origWidth > s.MaxWidth {
		// Scale down to maxWidth while maintaining aspect ratio
		thumbImg = imaging.Resize(srcImg, s.MaxWidth, 0, imaging.Lanczos)
	} else {
		thumbImg = srcImg
	}

	// Save as optimized JPEG
	if err := imaging.Save(thumbImg, destPath, imaging.JPEGQuality(s.Quality)); err != nil {
		return nil, fmt.Errorf("failed to save thumbnail to %s: %w", destPath, err)
	}

	return &ImageMeta{
		Width:   origWidth,
		Height:  origHeight,
		TakenAt: takenAt,
	}, nil
}

// IsImageExtension checks if the extension is typically an image format.
func IsImageExtension(ext string) bool {
	ext = strings.ToLower(strings.TrimPrefix(ext, "."))
	switch ext {
	case "jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "tif", "heic", "heif":
		return true
	default:
		return false
	}
}

// IsVideoExtension checks if the extension is typically a video format.
func IsVideoExtension(ext string) bool {
	ext = strings.ToLower(strings.TrimPrefix(ext, "."))
	switch ext {
	case "mp4", "mov", "m4v", "avi", "mkv", "webm", "3gp", "flv", "wmv":
		return true
	default:
		return false
	}
}

// ProcessThumbnailAsync creates thumbnail in background and updates DB record.
func (s *ThumbnailService) ProcessThumbnailAsync(mediaID uint, srcPath, destPath string, onComplete func(meta *ImageMeta, err error)) {
	go func() {
		meta, err := s.GenerateThumbnail(srcPath, destPath)
		if err != nil {
			log.Printf("[THUMBNAIL] Skipped/Failed for media ID %d: %v", mediaID, err)
		}
		if onComplete != nil {
			onComplete(meta, err)
		}
	}()
}

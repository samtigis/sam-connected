package service

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"mime"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/samtigis/sam-connected/server/internal/database"
	"gorm.io/gorm"
)

var (
	ErrHashMismatch   = errors.New("computed hash does not match client-provided hash")
	ErrDuplicateMedia = errors.New("media with this hash already exists")
	safeNameRegex     = regexp.MustCompile(`[^a-zA-Z0-9_\-\.]`)
)

// StorageService manages file persistence, directory structures, and metadata records.
type StorageService struct {
	BaseDir      string
	DB           *gorm.DB
	ThumbService *ThumbnailService
	Hasher       *Hasher
}

// NewStorageService creates a new StorageService instance.
func NewStorageService(baseDir string, db *gorm.DB, thumbSvc *ThumbnailService, hasher *Hasher) (*StorageService, error) {
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create base storage directory: %w", err)
	}

	return &StorageService{
		BaseDir:      baseDir,
		DB:           db,
		ThumbService: thumbSvc,
		Hasher:       hasher,
	}, nil
}

// SanitizeDeviceID ensures deviceID doesn't contain traversal or invalid characters.
func SanitizeDeviceID(deviceID string) string {
	cleaned := strings.TrimSpace(deviceID)
	if cleaned == "" {
		return "default_device"
	}
	cleaned = safeNameRegex.ReplaceAllString(cleaned, "_")
	return filepath.Clean(cleaned)
}

// SaveUploadedFile streams reader directly to a temporary file while hashing via SHA-256.
// Upon completion, it moves the file to ./storage/{device_id}/{YYYY}/{MM}/{hash}.ext
// and registers the entry in the database.
func (s *StorageService) SaveUploadedFile(
	deviceID string,
	originalName string,
	clientHash string,
	reader io.Reader,
	clientTakenAt *time.Time,
	width int,
	height int,
	duration float64,
	thumbReader ...io.Reader,
) (*database.Media, error) {
	cleanDeviceID := SanitizeDeviceID(deviceID)
	ext := strings.ToLower(filepath.Ext(originalName))
	if ext == "" {
		ext = ".bin"
	}

	// Create temp directory under storage base
	tmpDir := filepath.Join(s.BaseDir, ".tmp")
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create tmp directory: %w", err)
	}

	tmpFile, err := os.CreateTemp(tmpDir, "upload-*"+ext)
	if err != nil {
		return nil, fmt.Errorf("failed to create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()
	defer func() {
		// Clean up temporary file if it still exists
		if _, err := os.Stat(tmpPath); err == nil {
			_ = os.Remove(tmpPath)
		}
	}()

	// Stream write while computing SHA-256 simultaneously
	hasher := sha256.New()
	mw := io.MultiWriter(tmpFile, hasher)

	writtenBytes, err := io.Copy(mw, reader)
	_ = tmpFile.Close()
	if err != nil {
		return nil, fmt.Errorf("error during file streaming write: %w", err)
	}

	computedHash := hex.EncodeToString(hasher.Sum(nil))

	// Verify client hash if provided (log if mismatch, but use server's verified SHA-256)
	if clientHash != "" && !strings.EqualFold(clientHash, computedHash) {
		log.Printf("[WARN] Client hash mismatch (client: %s, server: %s), using server hash", clientHash, computedHash)
	}

	// Check if this hash already exists in DB for this device
	var existing database.Media
	if err := s.DB.Where("device_id = ? AND hash = ?", cleanDeviceID, computedHash).First(&existing).Error; err == nil {
		// Already exists - verify physical file exists
		if _, statErr := os.Stat(existing.FilePath); statErr == nil {
			return &existing, nil
		}
	}

	// Determine year and month for partition: ./storage/{device_id}/{YYYY}/{MM}/{hash}.ext
	eventTime := time.Now()
	if clientTakenAt != nil {
		eventTime = *clientTakenAt
	}

	yearStr := eventTime.Format("2006")
	monthStr := eventTime.Format("01")

	targetRelDir := filepath.Join(cleanDeviceID, yearStr, monthStr)
	targetFullDir := filepath.Join(s.BaseDir, targetRelDir)
	if err := os.MkdirAll(targetFullDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create target storage directory: %w", err)
	}

	targetFileName := computedHash + ext
	targetFullPath := filepath.Join(targetFullDir, targetFileName)

	// Move temp file to final location
	if err := os.Rename(tmpPath, targetFullPath); err != nil {
		// If rename fails across partitions/devices, fall back to copy
		if copyErr := copyFile(tmpPath, targetFullPath); copyErr != nil {
			return nil, fmt.Errorf("failed to persist file to destination: %w", copyErr)
		}
		_ = os.Remove(tmpPath)
	}

	mimeType := mime.TypeByExtension(ext)
	if mimeType == "" {
		if IsImageExtension(ext) {
			mimeType = "image/" + strings.TrimPrefix(ext, ".")
		} else if IsVideoExtension(ext) {
			mimeType = "video/" + strings.TrimPrefix(ext, ".")
		} else {
			mimeType = "application/octet-stream"
		}
	}

	// Prepare database record
	media := &database.Media{
		DeviceID:     cleanDeviceID,
		Hash:         computedHash,
		FileName:     originalName,
		FilePath:     targetFullPath,
		FileSize:     writtenBytes,
		MimeType:     mimeType,
		Extension:    ext,
		Width:        width,
		Height:       height,
		Duration:     duration,
		TakenAt:      clientTakenAt,
		HasThumbnail: false,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}

	if err := s.DB.Create(media).Error; err != nil {
		return nil, fmt.Errorf("failed to save media record to db: %w", err)
	}

	thumbRelDir := filepath.Join(cleanDeviceID, "thumbnails")
	thumbFullDir := filepath.Join(s.BaseDir, thumbRelDir)
	thumbFileName := computedHash + ".jpg"
	thumbFullPath := filepath.Join(thumbFullDir, thumbFileName)

	var customThumb io.Reader
	if len(thumbReader) > 0 && thumbReader[0] != nil {
		customThumb = thumbReader[0]
	}

	if customThumb != nil {
		_ = os.MkdirAll(thumbFullDir, 0755)
		if tf, err := os.Create(thumbFullPath); err == nil {
			_, _ = io.Copy(tf, customThumb)
			_ = tf.Close()
			s.DB.Model(&database.Media{}).Where("id = ?", media.ID).Updates(map[string]interface{}{
				"has_thumbnail":  true,
				"thumbnail_path": thumbFullPath,
			})
			media.HasThumbnail = true
			media.ThumbnailPath = thumbFullPath
		}
	} else if IsImageExtension(ext) {
		s.ThumbService.ProcessThumbnailAsync(media.ID, targetFullPath, thumbFullPath, func(meta *ImageMeta, err error) {
			if err != nil {
				return
			}
			updates := map[string]interface{}{
				"has_thumbnail":  true,
				"thumbnail_path": thumbFullPath,
				"width":          meta.Width,
				"height":         meta.Height,
			}
			if meta.TakenAt != nil && media.TakenAt == nil {
				updates["taken_at"] = meta.TakenAt
			}
			if updateErr := s.DB.Model(&database.Media{}).Where("id = ?", media.ID).Updates(updates).Error; updateErr != nil {
				log.Printf("[STORAGE] Failed to update media %d thumbnail metadata: %v", media.ID, updateErr)
			}
		})
	} else if IsVideoExtension(ext) {
		// Attempt video thumbnail generation and duration extraction via ffmpeg if available
		go func() {
			updates := make(map[string]interface{})
			if dur, w, h, err := s.ThumbService.ExtractVideoMetadata(targetFullPath); err == nil {
				if media.Duration <= 0 && dur > 0 {
					updates["duration"] = dur
				}
				if media.Width <= 0 && w > 0 {
					updates["width"] = w
				}
				if media.Height <= 0 && h > 0 {
					updates["height"] = h
				}
			}
			if err := s.ThumbService.GenerateVideoThumbnail(targetFullPath, thumbFullPath); err == nil {
				updates["has_thumbnail"] = true
				updates["thumbnail_path"] = thumbFullPath
			} else {
				log.Printf("[STORAGE] Video thumbnail generation failed for %s: %v", targetFullPath, err)
			}
			if len(updates) > 0 {
				s.DB.Model(&database.Media{}).Where("id = ?", media.ID).Updates(updates)
			}
		}()
	}

	return media, nil
}

// BackfillMissingThumbnails scans for media missing thumbnails and generates them in the background.
func (s *StorageService) BackfillMissingThumbnails() {
	go func() {
		var missing []database.Media
		if err := s.DB.Where("has_thumbnail = ? OR thumbnail_path = ''", false).Find(&missing).Error; err != nil {
			log.Printf("[THUMBNAIL] Error querying media with missing thumbnails: %v", err)
			return
		}

		if len(missing) == 0 {
			return
		}

		log.Printf("[THUMBNAIL] Found %d media items with missing thumbnails, starting backfill...", len(missing))
		successCount := 0

		for _, m := range missing {
			if m.FilePath == "" {
				continue
			}
			if _, err := os.Stat(m.FilePath); os.IsNotExist(err) {
				continue
			}

			thumbDir := filepath.Join(s.BaseDir, m.DeviceID, "thumbnails")
			thumbPath := filepath.Join(thumbDir, m.Hash+".jpg")

			// Check if physical thumbnail file already exists on disk
			if _, statErr := os.Stat(thumbPath); statErr == nil {
				s.DB.Model(&database.Media{}).Where("id = ?", m.ID).Updates(map[string]interface{}{
					"has_thumbnail":  true,
					"thumbnail_path": thumbPath,
				})
				successCount++
				continue
			}

			if IsImageExtension(m.Extension) {
				meta, err := s.ThumbService.GenerateThumbnail(m.FilePath, thumbPath)
				if err == nil {
					updates := map[string]interface{}{
						"has_thumbnail":  true,
						"thumbnail_path": thumbPath,
						"width":          meta.Width,
						"height":         meta.Height,
					}
					if meta.TakenAt != nil && m.TakenAt == nil {
						updates["taken_at"] = meta.TakenAt
					}
					s.DB.Model(&database.Media{}).Where("id = ?", m.ID).Updates(updates)
					successCount++
				}
			} else if IsVideoExtension(m.Extension) {
				updates := make(map[string]interface{})
				if m.Duration <= 0 || m.Width <= 0 {
					if dur, w, h, err := s.ThumbService.ExtractVideoMetadata(m.FilePath); err == nil {
						if m.Duration <= 0 && dur > 0 {
							updates["duration"] = dur
						}
						if m.Width <= 0 && w > 0 {
							updates["width"] = w
						}
						if m.Height <= 0 && h > 0 {
							updates["height"] = h
						}
					}
				}
				if err := s.ThumbService.GenerateVideoThumbnail(m.FilePath, thumbPath); err == nil {
					updates["has_thumbnail"] = true
					updates["thumbnail_path"] = thumbPath
					successCount++
				}
				if len(updates) > 0 {
					s.DB.Model(&database.Media{}).Where("id = ?", m.ID).Updates(updates)
				}
			}
		}

		// Also backfill duration for videos that already have thumbnails but 0 duration
		var zeroDurVideos []database.Media
		if err := s.DB.Where("mime_type LIKE 'video/%' AND (duration = 0 OR duration IS NULL)").Find(&zeroDurVideos).Error; err == nil && len(zeroDurVideos) > 0 {
			log.Printf("[METADATA] Checking %d videos with 0 duration...", len(zeroDurVideos))
			for _, vm := range zeroDurVideos {
				p := vm.FilePath
				if _, err := os.Stat(p); os.IsNotExist(err) {
					p = filepath.Join(s.BaseDir, vm.FilePath)
				}
				if dur, w, h, err := s.ThumbService.ExtractVideoMetadata(p); err == nil && dur > 0 {
					u := map[string]interface{}{"duration": dur}
					if vm.Width <= 0 && w > 0 {
						u["width"] = w
					}
					if vm.Height <= 0 && h > 0 {
						u["height"] = h
					}
					s.DB.Model(&database.Media{}).Where("id = ?", vm.ID).Updates(u)
					log.Printf("[METADATA] Video ID %d duration backfilled: %.2fs", vm.ID, dur)
				}
			}
		}

		log.Printf("[THUMBNAIL] Completed backfill: %d/%d thumbnails generated/updated.", successCount, len(missing))
	}()
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	if _, err := io.Copy(out, in); err != nil {
		return err
	}
	return out.Sync()
}

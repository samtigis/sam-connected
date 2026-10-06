package handler

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/samtigis/sam-connected/server/internal/database"
	"github.com/samtigis/sam-connected/server/internal/service"
	"gorm.io/gorm"
)

// MediaHandler handles media listing, thumbnail streaming, and raw media streaming.
type MediaHandler struct {
	DB           *gorm.DB
	Storage      *service.StorageService
	ThumbService *service.ThumbnailService
}

// NewMediaHandler creates a new MediaHandler instance.
func NewMediaHandler(db *gorm.DB, storage *service.StorageService, thumbSvc *service.ThumbnailService) *MediaHandler {
	return &MediaHandler{
		DB:           db,
		Storage:      storage,
		ThumbService: thumbSvc,
	}
}

// List handles cursor-based pagination for media items.
// GET /api/v1/media?cursor=100&limit=50&device_id=phone1&order=desc
func (h *MediaHandler) List(c *fiber.Ctx) error {
	cursorStr := c.Query("cursor", "0")
	cursor, _ := strconv.ParseUint(cursorStr, 10, 64)

	limitStr := c.Query("limit", "50")
	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}

	deviceID := strings.TrimSpace(c.Query("device_id"))
	order := strings.ToLower(c.Query("order", "desc"))
	mediaType := strings.ToLower(strings.TrimSpace(c.Query("type")))
	favoriteParam := strings.TrimSpace(c.Query("favorite"))
	searchParam := strings.TrimSpace(c.Query("search"))

	query := h.DB.Model(&database.Media{})
	if deviceID != "" {
		query = query.Where("device_id = ?", deviceID)
	}

	if mediaType == "image" {
		query = query.Where("mime_type LIKE 'image/%'")
	} else if mediaType == "video" {
		query = query.Where("mime_type LIKE 'video/%'")
	}

	if favoriteParam == "true" || favoriteParam == "1" {
		query = query.Where("is_favorite = ?", true)
	}

	if searchParam != "" {
		query = query.Where("file_name LIKE ?", "%"+searchParam+"%")
	}

	if order == "asc" {
		if cursor > 0 {
			query = query.Where("id > ?", cursor)
		}
		query = query.Order("id ASC")
	} else {
		// Default: descending (newest ID first)
		if cursor > 0 {
			query = query.Where("id < ?", cursor)
		}
		query = query.Order("id DESC")
	}

	// Fetch limit + 1 to determine if there are more items
	var items []database.Media
	if err := query.Limit(limit + 1).Find(&items).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to query media database",
		})
	}

	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}

	var nextCursor uint = 0
	if len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	return c.JSON(fiber.Map{
		"data":        items,
		"count":       len(items),
		"next_cursor": nextCursor,
		"has_more":    hasMore,
	})
}

// TimelineGroup holds grouped media by calendar date.
type TimelineGroup struct {
	Date  string           `json:"date"`
	Count int              `json:"count"`
	Items []database.Media `json:"items"`
}

// GetTimeline groups media by date (YYYY-MM-DD) for Google Photos-like timeline feeds.
// GET /api/v1/media/timeline?device_id=...&type=image|video&favorite=true
func (h *MediaHandler) GetTimeline(c *fiber.Ctx) error {
	deviceID := strings.TrimSpace(c.Query("device_id"))
	mediaType := strings.ToLower(strings.TrimSpace(c.Query("type")))
	favoriteParam := strings.TrimSpace(c.Query("favorite"))

	query := h.DB.Model(&database.Media{})
	if deviceID != "" {
		query = query.Where("device_id = ?", deviceID)
	}
	if mediaType == "image" {
		query = query.Where("mime_type LIKE 'image/%'")
	} else if mediaType == "video" {
		query = query.Where("mime_type LIKE 'video/%'")
	}
	if favoriteParam == "true" || favoriteParam == "1" {
		query = query.Where("is_favorite = ?", true)
	}

	var allItems []database.Media
	if err := query.Order("created_at DESC").Limit(500).Find(&allItems).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to query media timeline",
		})
	}

	// Group by date (YYYY-MM-DD)
	groupsMap := make(map[string][]database.Media)
	var orderedDates []string

	for _, item := range allItems {
		var dateKey string
		if item.TakenAt != nil && !item.TakenAt.IsZero() {
			dateKey = item.TakenAt.Format("2006-01-02")
		} else {
			dateKey = item.CreatedAt.Format("2006-01-02")
		}

		if _, exists := groupsMap[dateKey]; !exists {
			orderedDates = append(orderedDates, dateKey)
		}
		groupsMap[dateKey] = append(groupsMap[dateKey], item)
	}

	timeline := make([]TimelineGroup, 0)
	for _, date := range orderedDates {
		timeline = append(timeline, TimelineGroup{
			Date:  date,
			Count: len(groupsMap[date]),
			Items: groupsMap[date],
		})
	}

	return c.JSON(fiber.Map{
		"total_media": len(allItems),
		"groups":      timeline,
	})
}

// GetByID returns the complete metadata for a single media item.
// GET /api/v1/media/:id
func (h *MediaHandler) GetByID(c *fiber.Ctx) error {
	idParam := c.Params("id")
	id, err := strconv.ParseUint(idParam, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid media id",
		})
	}

	var media database.Media
	if err := h.DB.First(&media, id).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "media not found",
		})
	}

	return c.JSON(fiber.Map{
		"data": media,
	})
}

// ToggleFavorite toggles the favorite status of a media item.
// POST /api/v1/media/:id/favorite
func (h *MediaHandler) ToggleFavorite(c *fiber.Ctx) error {
	idParam := c.Params("id")
	id, err := strconv.ParseUint(idParam, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid media id",
		})
	}

	var media database.Media
	if err := h.DB.First(&media, id).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "media not found",
		})
	}

	media.IsFavorite = !media.IsFavorite
	if err := h.DB.Model(&database.Media{}).Where("id = ?", media.ID).Update("is_favorite", media.IsFavorite).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to update favorite status",
		})
	}

	return c.JSON(fiber.Map{
		"id":          media.ID,
		"is_favorite": media.IsFavorite,
	})
}

// Delete removes a media file from disk and database.
// DELETE /api/v1/media/:id
func (h *MediaHandler) Delete(c *fiber.Ctx) error {
	idParam := c.Params("id")
	id, err := strconv.ParseUint(idParam, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid media id",
		})
	}

	var media database.Media
	if err := h.DB.First(&media, id).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "media not found",
		})
	}

	// Remove physical files
	if media.FilePath != "" {
		_ = os.Remove(media.FilePath)
	}
	if media.ThumbnailPath != "" {
		_ = os.Remove(media.ThumbnailPath)
	}

	// Delete DB row
	if err := h.DB.Delete(&media).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to delete media database record",
		})
	}

	return c.JSON(fiber.Map{
		"status":  "deleted",
		"id":      media.ID,
		"message": "Media and associated thumbnails deleted successfully",
	})
}

// GetThumbnail streams the thumbnail image with aggressive caching headers.
// GET /api/v1/media/:id/thumb
func (h *MediaHandler) GetThumbnail(c *fiber.Ctx) error {
	idParam := c.Params("id")
	id, err := strconv.ParseUint(idParam, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid media id",
		})
	}

	var media database.Media
	if err := h.DB.First(&media, id).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "media not found",
		})
	}

	// Check if thumbnail exists
	if !media.HasThumbnail || media.ThumbnailPath == "" {
		thumbDir := filepath.Join(h.Storage.BaseDir, media.DeviceID, "thumbnails")
		thumbPath := filepath.Join(thumbDir, media.Hash+".jpg")

		// If media is image, attempt on-demand generation
		if service.IsImageExtension(media.Extension) && media.FilePath != "" {
			meta, genErr := h.ThumbService.GenerateThumbnail(media.FilePath, thumbPath)
			if genErr == nil {
				media.HasThumbnail = true
				media.ThumbnailPath = thumbPath
				media.Width = meta.Width
				media.Height = meta.Height
				h.DB.Model(&database.Media{}).Where("id = ?", media.ID).Updates(map[string]interface{}{
					"has_thumbnail":  true,
					"thumbnail_path": thumbPath,
					"width":          meta.Width,
					"height":         meta.Height,
				})
			} else {
				return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
					"error": "thumbnail not available for this media",
				})
			}
		} else if service.IsVideoExtension(media.Extension) && media.FilePath != "" {
			// If media is video, extract a frame via ThumbService
			cleanThumbPath := filepath.Clean(thumbPath)
			if err := h.ThumbService.GenerateVideoThumbnail(media.FilePath, cleanThumbPath); err == nil {
				media.HasThumbnail = true
				media.ThumbnailPath = cleanThumbPath
				h.DB.Model(&database.Media{}).Where("id = ?", media.ID).Updates(map[string]interface{}{
					"has_thumbnail":  true,
					"thumbnail_path": cleanThumbPath,
				})
			} else {
				log.Printf("[THUMBNAIL] Video thumbnail generation failed for media ID %d: %v", media.ID, err)
				return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
					"error": "video thumbnail generation failed",
				})
			}
		} else {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "media has no thumbnail",
			})
		}
	}

	// Verify thumbnail file exists on disk
	if _, err := os.Stat(media.ThumbnailPath); os.IsNotExist(err) {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "thumbnail file not found on disk",
		})
	}

	// Caching headers
	etag := fmt.Sprintf(`W/"thumb-%s"`, media.Hash)
	c.Set("ETag", etag)
	c.Set("Cache-Control", "public, max-age=31536000, immutable")
	c.Set("Content-Type", "image/jpeg")

	if match := c.Get("If-None-Match"); match == etag {
		return c.SendStatus(fiber.StatusNotModified)
	}

	return c.SendFile(media.ThumbnailPath)
}

// GetRaw streams the original media file, supporting HTTP 206 Partial Content (Byte-Range) for videos.
// GetRaw streams the original media file, supporting HTTP 206 Partial Content (Byte-Range) for videos.
// GET /api/v1/media/:id/raw
func (h *MediaHandler) GetRaw(c *fiber.Ctx) error {
	idParam := c.Params("id")
	id, err := strconv.ParseUint(idParam, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid media id",
		})
	}

	var media database.Media
	if err := h.DB.First(&media, id).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "media not found",
		})
	}

	rawFilePath := media.FilePath
	stat, statErr := os.Stat(rawFilePath)
	if statErr != nil || stat.IsDir() {
		found := false
		lowerHash := strings.ToLower(media.Hash)

		// Candidate 1: Try relative to Storage.BaseDir
		if media.FilePath != "" {
			candRel := filepath.Join(h.Storage.BaseDir, media.FilePath)
			if s, e := os.Stat(candRel); e == nil && !s.IsDir() {
				rawFilePath = candRel
				found = true
			}
		}

		// Candidate 2: Try partitioned directory based on TakenAt / CreatedAt
		if !found {
			t := media.CreatedAt
			if media.TakenAt != nil && !media.TakenAt.IsZero() {
				t = *media.TakenAt
			}
			candDate := filepath.Join(h.Storage.BaseDir, media.DeviceID, t.Format("2006"), t.Format("01"), media.Hash+media.Extension)
			if s, e := os.Stat(candDate); e == nil && !s.IsDir() {
				rawFilePath = candDate
				found = true
			}
		}

		// Candidate 3: Try device root directory
		if !found {
			candDev := filepath.Join(h.Storage.BaseDir, media.DeviceID, media.Hash+media.Extension)
			if s, e := os.Stat(candDev); e == nil && !s.IsDir() {
				rawFilePath = candDev
				found = true
			}
		}

		// Candidate 4: Recursive WalkDir search across BaseDir matching media.Hash
		if !found && h.Storage.BaseDir != "" {
			_ = filepath.WalkDir(h.Storage.BaseDir, func(p string, d os.DirEntry, err error) error {
				if err == nil && !d.IsDir() {
					if strings.Contains(p, "thumbnails") {
						return nil
					}
					if strings.Contains(strings.ToLower(d.Name()), lowerHash) {
						rawFilePath = p
						found = true
						return filepath.SkipAll
					}
				}
				return nil
			})
		}

		if !found {
			log.Printf("[RAW 404] Media ID %d (Hash: %s, Device: %s, File: %s) not found on disk. FilePath: %s, BaseDir: %s",
				media.ID, media.Hash, media.DeviceID, media.FileName, media.FilePath, h.Storage.BaseDir)
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "raw file not found on disk",
			})
		}
	}

	// Determine accurate content type based on extension
	ext := strings.ToLower(filepath.Ext(media.FileName))
	if ext == "" {
		ext = strings.ToLower(media.Extension)
	}
	if ext == "" {
		ext = strings.ToLower(filepath.Ext(rawFilePath))
	}
	if !strings.HasPrefix(ext, ".") && ext != "" {
		ext = "." + ext
	}

	contentType := "application/octet-stream"
	switch ext {
	case ".mp4":
		contentType = "video/mp4"
	case ".mov":
		contentType = "video/quicktime"
	case ".m4v":
		contentType = "video/x-m4v"
	case ".webm":
		contentType = "video/webm"
	case ".avi":
		contentType = "video/x-msvideo"
	case ".mkv":
		contentType = "video/x-matroska"
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".png":
		contentType = "image/png"
	case ".heic", ".heif":
		contentType = "image/heic"
	case ".webp":
		contentType = "image/webp"
	default:
		if media.MimeType != "" && media.MimeType != "application/octet-stream" && !strings.Contains(media.MimeType, "mov") {
			contentType = media.MimeType
		}
	}

	c.Set("Content-Type", contentType)
	c.Set("Accept-Ranges", "bytes")
	c.Set("Content-Disposition", fmt.Sprintf(`inline; filename="%s"`, filepath.Base(media.FileName)))

	// Fiber's SendFile automatically honors Range headers and sends 206 Partial Content for videos
	err = c.SendFile(rawFilePath)
	c.Response().Header.SetContentType(contentType)
	return err
}

// GetDevices returns all distinct client devices that have backed up media to the server, including custom friendly names.
// GET /api/v1/devices
func (h *MediaHandler) GetDevices(c *fiber.Ctx) error {
	type Result struct {
		DeviceID    string     `json:"device_id"`
		CustomName  string     `json:"custom_name"`
		DisplayName string     `json:"display_name"`
		TotalMedia  int        `json:"total_media"`
		TotalBytes  int64      `json:"total_bytes"`
		LastActive  *time.Time `json:"last_active"`
	}
	var results []Result
	err := h.DB.Model(&database.Media{}).
		Select("device_id, count(*) as total_media, sum(file_size) as total_bytes, max(created_at) as last_active").
		Group("device_id").
		Order("last_active desc").
		Scan(&results).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to query devices: " + err.Error(),
		})
	}

	// Lookup custom names in devices table
	var devRecords []database.Device
	_ = h.DB.Find(&devRecords).Error
	nameMap := make(map[string]string)
	for _, d := range devRecords {
		nameMap[d.DeviceID] = d.CustomName
	}

	for i := range results {
		cName := nameMap[results[i].DeviceID]
		results[i].CustomName = cName
		if cName != "" {
			results[i].DisplayName = cName
		} else {
			results[i].DisplayName = results[i].DeviceID
		}
	}

	return c.JSON(fiber.Map{
		"devices": results,
		"count":   len(results),
	})
}

// SetDeviceName updates the custom friendly display name for a client device.
// POST /api/v1/devices/:id/name
func (h *MediaHandler) SetDeviceName(c *fiber.Ctx) error {
	deviceID := strings.TrimSpace(c.Params("id"))
	if deviceID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "device_id is required"})
	}

	type RequestBody struct {
		Name string `json:"name"`
	}
	var body RequestBody
	if err := c.BodyParser(&body); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	customName := strings.TrimSpace(body.Name)

	var dev database.Device
	if err := h.DB.Where("device_id = ?", deviceID).First(&dev).Error; err != nil {
		dev = database.Device{
			DeviceID:   deviceID,
			CustomName: customName,
			LastActive: time.Now(),
		}
		if err := h.DB.Create(&dev).Error; err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to save device name"})
		}
	} else {
		dev.CustomName = customName
		dev.UpdatedAt = time.Now()
		if err := h.DB.Save(&dev).Error; err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update device name"})
		}
	}

	log.Printf("[DEVICE] Device '%s' renamed to '%s'", deviceID, customName)

	return c.JSON(fiber.Map{
		"message":     "Device name updated successfully",
		"device_id":   deviceID,
		"custom_name": customName,
		"display_name": func() string {
			if customName != "" {
				return customName
			}
			return deviceID
		}(),
	})
}


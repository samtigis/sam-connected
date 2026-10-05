package handler

import (
	"fmt"
	"os"
	"strconv"
	"strings"

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

	query := h.DB.Model(&database.Media{})
	if deviceID != "" {
		query = query.Where("device_id = ?", deviceID)
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
		// If media is image, attempt on-demand generation
		if service.IsImageExtension(media.Extension) && media.FilePath != "" {
			thumbDir := fmt.Sprintf("%s/%s/thumbnails", h.Storage.BaseDir, media.DeviceID)
			thumbPath := fmt.Sprintf("%s/%s.jpg", thumbDir, media.Hash)

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

	if _, err := os.Stat(media.FilePath); os.IsNotExist(err) {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "raw file not found on disk",
		})
	}

	// Content headers
	if media.MimeType != "" {
		c.Set("Content-Type", media.MimeType)
	}
	c.Set("Accept-Ranges", "bytes")
	c.Set("Content-Disposition", fmt.Sprintf(`inline; filename="%s"`, media.FileName))

	// Fiber's SendFile automatically honors Range headers and sends 206 Partial Content for videos
	return c.SendFile(media.FilePath)
}

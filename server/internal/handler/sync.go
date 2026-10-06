package handler

import (
	"errors"
	"io"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/samtigis/sam-connected/server/internal/database"
	"github.com/samtigis/sam-connected/server/internal/service"
	"gorm.io/gorm"
)

// PreflightRequest payload containing batch hashes to verify.
type PreflightRequest struct {
	DeviceID string   `json:"device_id"`
	Hashes   []string `json:"hashes"`
}

// PreflightResponse payload returning hashes that must be uploaded.
type PreflightResponse struct {
	MissingHashes []string `json:"missing_hashes"`
	ExistingCount int      `json:"existing_count"`
	MissingCount  int      `json:"missing_count"`
	TotalChecked  int      `json:"total_checked"`
}

// SyncHandler handles preflight checks and streaming multipart uploads.
type SyncHandler struct {
	DB      *gorm.DB
	Storage *service.StorageService
}

// NewSyncHandler creates a new SyncHandler instance.
func NewSyncHandler(db *gorm.DB, storage *service.StorageService) *SyncHandler {
	return &SyncHandler{
		DB:      db,
		Storage: storage,
	}
}

// Preflight checks an array of SHA-256 hashes against existing database records.
// POST /api/v1/sync/preflight
func (h *SyncHandler) Preflight(c *fiber.Ctx) error {
	var req PreflightRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	if len(req.Hashes) == 0 {
		return c.JSON(PreflightResponse{
			MissingHashes: []string{},
			ExistingCount: 0,
			MissingCount:  0,
			TotalChecked:  0,
		})
	}

	// Clean hashes list (trim space, lowercase)
	uniqueHashes := make(map[string]struct{})
	cleanList := make([]string, 0, len(req.Hashes))
	for _, h := range req.Hashes {
		trimmed := strings.ToLower(strings.TrimSpace(h))
		if len(trimmed) == 64 { // SHA-256 hex length
			if _, exists := uniqueHashes[trimmed]; !exists {
				uniqueHashes[trimmed] = struct{}{}
				cleanList = append(cleanList, trimmed)
			}
		}
	}

	// Query database for existing hashes in batches of 1000
	existingSet := make(map[string]struct{})
	chunkSize := 1000
	for i := 0; i < len(cleanList); i += chunkSize {
		end := i + chunkSize
		if end > len(cleanList) {
			end = len(cleanList)
		}
		chunk := cleanList[i:end]

		var foundHashes []string
		if err := h.DB.Model(&database.Media{}).
			Where("hash IN (?)", chunk).
			Pluck("hash", &foundHashes).Error; err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "database query failed",
			})
		}
		for _, f := range foundHashes {
			existingSet[strings.ToLower(f)] = struct{}{}
		}
	}

	// Determine missing hashes
	missing := make([]string, 0)
	for _, ch := range cleanList {
		if _, exists := existingSet[ch]; !exists {
			missing = append(missing, ch)
		}
	}

	return c.JSON(PreflightResponse{
		MissingHashes: missing,
		ExistingCount: len(existingSet),
		MissingCount:  len(missing),
		TotalChecked:  len(cleanList),
	})
}

// Upload handles multipart file upload, calculates SHA-256 on the fly, and persists media.
// POST /api/v1/sync/upload
func (h *SyncHandler) Upload(c *fiber.Ctx) error {
	fileHeader, err := c.FormFile("file")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "missing 'file' in multipart form data: " + err.Error(),
		})
	}

	deviceID := c.FormValue("device_id")
	if deviceID == "" {
		deviceID = "unidentified_device"
	}

	clientHash := strings.ToLower(strings.TrimSpace(c.FormValue("client_hash")))
	takenAtStr := strings.TrimSpace(c.FormValue("taken_at"))

	var clientTakenAt *time.Time
	if takenAtStr != "" {
		if parsed, err := time.Parse(time.RFC3339, takenAtStr); err == nil {
			clientTakenAt = &parsed
		} else if parsed, err := time.Parse("2006-01-02 15:04:05", takenAtStr); err == nil {
			clientTakenAt = &parsed
		}
	}

	// Open multipart file stream
	srcStream, err := fileHeader.Open()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to open upload stream: " + err.Error(),
		})
	}
	defer srcStream.Close()

	// Open optional thumbnail multipart stream if provided
	var thumbStream io.Reader
	if thumbHeader, err := c.FormFile("thumbnail"); err == nil && thumbHeader != nil {
		if ts, err := thumbHeader.Open(); err == nil {
			defer ts.Close()
			thumbStream = ts
		}
	}

	// Stream and save
	media, err := h.Storage.SaveUploadedFile(deviceID, fileHeader.Filename, clientHash, srcStream, clientTakenAt, thumbStream)
	if err != nil {
		if errors.Is(err, service.ErrHashMismatch) {
			return c.Status(fiber.StatusUnprocessableEntity).JSON(fiber.Map{
				"error": err.Error(),
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to process and store file: " + err.Error(),
		})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"message": "media stored successfully",
		"media":   media,
	})
}

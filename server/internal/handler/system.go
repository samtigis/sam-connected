package handler

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/samtigis/sam-connected/server/internal/config"
	"github.com/samtigis/sam-connected/server/internal/database"
	"github.com/samtigis/sam-connected/server/internal/gui"
	"github.com/samtigis/sam-connected/server/internal/logbuffer"
	"github.com/samtigis/sam-connected/server/internal/service"
	"gorm.io/gorm"
)

// SystemHandler manages system configuration, folder picker, and server logs
type SystemHandler struct {
	ConfigSvc    *config.ConfigService
	StorageSvc   *service.StorageService
	HealthHdlr   *HealthHandler
	DB           *gorm.DB
	onPathChange func(newPath string)
}

// NewSystemHandler creates a new SystemHandler
func NewSystemHandler(
	cfgSvc *config.ConfigService,
	storageSvc *service.StorageService,
	healthHdlr *HealthHandler,
	db *gorm.DB,
	onPathChange func(newPath string),
) *SystemHandler {
	return &SystemHandler{
		ConfigSvc:    cfgSvc,
		StorageSvc:   storageSvc,
		HealthHdlr:   healthHdlr,
		DB:           db,
		onPathChange: onPathChange,
	}
}

// GetConfig returns the current configuration and local network info
func (h *SystemHandler) GetConfig(c *fiber.Ctx) error {
	cfg := h.ConfigSvc.Get()
	localIP := gui.GetLocalIPv4()

	var totalMedia int64
	var totalImages int64
	var totalVideos int64
	var totalBytes int64

	h.DB.Model(&database.Media{}).Count(&totalMedia)
	h.DB.Model(&database.Media{}).Where("mime_type LIKE 'image/%'").Count(&totalImages)
	h.DB.Model(&database.Media{}).Where("mime_type LIKE 'video/%'").Count(&totalVideos)

	type Result struct {
		TotalSize int64
	}
	var res Result
	h.DB.Model(&database.Media{}).Select("COALESCE(SUM(file_size), 0) as total_size").Scan(&res)
	totalBytes = res.TotalSize

	diskStatus, _ := service.GetDirectoryDiskStatus(cfg.StoragePath)

	return c.JSON(fiber.Map{
		"storage_path": cfg.StoragePath,
		"port":         cfg.Port,
		"local_ip":     localIP,
		"api_url":      "http://" + localIP + ":8080/api/v1",
		"stats": fiber.Map{
			"total_media":  totalMedia,
			"total_images": totalImages,
			"total_videos": totalVideos,
			"total_bytes":  totalBytes,
		},
		"disk": diskStatus,
	})
}

// ChooseFolder opens the native Windows folder picker dialog and returns the selected path
func (h *SystemHandler) ChooseFolder(c *fiber.Ctx) error {
	currentPath := h.ConfigSvc.Get().StoragePath
	selectedPath, err := gui.PickFolderDialog(currentPath)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Gagal membuka dialog pemilih folder: " + err.Error(),
		})
	}

	if selectedPath == "" {
		return c.JSON(fiber.Map{
			"selected": false,
			"path":     currentPath,
		})
	}

	return c.JSON(fiber.Map{
		"selected": true,
		"path":     selectedPath,
	})
}

// SetFolder updates the storage path in config and runtime service
func (h *SystemHandler) SetFolder(c *fiber.Ctx) error {
	type Request struct {
		Path string `json:"path"`
	}
	var req Request
	if err := c.BodyParser(&req); err != nil || strings.TrimSpace(req.Path) == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Path folder tidak valid",
		})
	}

	cleanPath := filepath.Clean(strings.TrimSpace(req.Path))
	if err := h.ConfigSvc.SetStoragePath(cleanPath); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Gagal menyimpan konfigurasi: " + err.Error(),
		})
	}

	if h.StorageSvc != nil {
		h.StorageSvc.BaseDir = cleanPath
	}
	if h.HealthHdlr != nil {
		h.HealthHdlr.storagePath = cleanPath
	}
	if h.onPathChange != nil {
		h.onPathChange(cleanPath)
	}

	logbuffer.Logf("[STORAGE] Lokasi penyimpanan berhasil diubah ke: %s", cleanPath)

	return c.JSON(fiber.Map{
		"status":       "ok",
		"storage_path": cleanPath,
	})
}

// OpenFolder opens the current storage directory in Windows File Explorer
func (h *SystemHandler) OpenFolder(c *fiber.Ctx) error {
	type Request struct {
		Path string `json:"path"`
	}
	var req Request
	_ = c.BodyParser(&req)

	targetPath := req.Path
	if targetPath == "" {
		targetPath = h.ConfigSvc.Get().StoragePath
	}

	if err := gui.OpenFolderInExplorer(targetPath); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Gagal membuka File Explorer: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{"status": "ok"})
}

// GetLogs returns recent logs captured from server output
func (h *SystemHandler) GetLogs(c *fiber.Ctx) error {
	entries := logbuffer.DefaultBuffer.GetEntries()
	return c.JSON(fiber.Map{
		"logs": entries,
	})
}

// ClearLogs clears the in-memory log buffer
func (h *SystemHandler) ClearLogs(c *fiber.Ctx) error {
	logbuffer.DefaultBuffer.Clear()
	return c.JSON(fiber.Map{"status": "ok"})
}

// OpenFile opens a media file directly in Windows default application (Windows Media Player, VLC, Photos)
func (h *SystemHandler) OpenFile(c *fiber.Ctx) error {
	type Request struct {
		MediaID uint   `json:"media_id"`
		Path    string `json:"path"`
	}
	var req Request
	_ = c.BodyParser(&req)

	targetPath := req.Path
	if targetPath == "" && req.MediaID > 0 {
		var media database.Media
		if err := h.DB.First(&media, req.MediaID).Error; err == nil {
			targetPath = media.FilePath
			if _, err := os.Stat(targetPath); os.IsNotExist(err) {
				cand := filepath.Join(h.StorageSvc.BaseDir, media.FilePath)
				if _, sErr := os.Stat(cand); sErr == nil {
					targetPath = cand
				} else {
					_ = filepath.WalkDir(h.StorageSvc.BaseDir, func(p string, d os.DirEntry, err error) error {
						if err == nil && !d.IsDir() && !strings.Contains(p, "thumbnails") && strings.Contains(strings.ToLower(d.Name()), strings.ToLower(media.Hash)) {
							targetPath = p
							return filepath.SkipAll
						}
						return nil
					})
				}
			}
		}
	}

	if targetPath == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "File media tidak ditemukan"})
	}

	if err := gui.OpenFileInDefaultApp(targetPath); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Gagal membuka aplikasi default: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{"status": "ok", "path": targetPath})
}

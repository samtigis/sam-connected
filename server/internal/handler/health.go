package handler

import (
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/samtigis/sam-connected/server/internal/service"
)

// HealthHandler manages system status and disk metrics.
type HealthHandler struct {
	startTime   time.Time
	storagePath string
}

// NewHealthHandler creates a new HealthHandler.
func NewHealthHandler(storagePath string) *HealthHandler {
	return &HealthHandler{
		startTime:   time.Now(),
		storagePath: storagePath,
	}
}

// Ping returns the server status, running duration, and dynamic disk usage of storage path.
// GET /api/v1/ping
func (h *HealthHandler) Ping(c *fiber.Ctx) error {
	diskStatus, err := service.GetDirectoryDiskStatus(h.storagePath)
	if err != nil {
		diskStatus = service.DiskStatus{}
	}

	uptime := time.Since(h.startTime).Seconds()

	return c.JSON(fiber.Map{
		"status":         "ok",
		"service":        "sam-connected-backup",
		"version":        "1.2.0",
		"uptime_seconds": int64(uptime),
		"server_time":    time.Now().UTC(),
		"disk":           diskStatus,
	})
}

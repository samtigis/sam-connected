package handler

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/samtigis/sam-connected/server/internal/database"
)

func TestGetDevices(t *testing.T) {
	dbPath := "./test_devices.db"
	defer os.Remove(dbPath)

	db, err := database.InitDB(dbPath)
	if err != nil {
		t.Fatalf("InitDB failed: %v", err)
	}

	app := fiber.New()
	handler := &MediaHandler{DB: db}
	app.Get("/api/v1/devices", handler.GetDevices)

	// 1. Test when DB is empty
	req := httptest.NewRequest("GET", "/api/v1/devices", nil)
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("app.Test failed: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Errorf("expected 200 on empty db, got %d", resp.StatusCode)
	}

	// 2. Insert a media record and test
	now := time.Now()
	m := database.Media{
		DeviceID: "test-device-1",
		Hash: "abc1234",
		FileName: "test.jpg",
		FilePath: "/tmp/test.jpg",
		FileSize: 1024,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := db.Create(&m).Error; err != nil {
		t.Fatalf("failed to insert media: %v", err)
	}

	req = httptest.NewRequest("GET", "/api/v1/devices", nil)
	resp, err = app.Test(req)
	if err != nil {
		t.Fatalf("app.Test failed: %v", err)
	}
	t.Logf("Status code with 1 item: %d", resp.StatusCode)
	if resp.StatusCode != 200 {
		var body map[string]interface{}
		_ = json.NewDecoder(resp.Body).Decode(&body)
		t.Errorf("expected 200, got %d, body: %v", resp.StatusCode, body)
	}
}

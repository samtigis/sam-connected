package database

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// InitDB initializes SQLite database using pure-Go (CGO-free) driver and applies pragmas.
func InitDB(dbPath string) (*gorm.DB, error) {
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create database directory %s: %w", dir, err)
	}

	db, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Warn),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to open sqlite database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get underlying sql.DB: %w", err)
	}

	// SQLite connection pool configuration for WAL mode
	sqlDB.SetMaxOpenConns(1) // Avoid database lock in single-file sqlite with multiple writers
	sqlDB.SetMaxIdleConns(1)

	// Execute performance and safety pragmas
	pragmas := []string{
		"PRAGMA journal_mode = WAL;",
		"PRAGMA synchronous = NORMAL;",
		"PRAGMA foreign_keys = ON;",
		"PRAGMA busy_timeout = 5000;",
		"PRAGMA temp_store = MEMORY;",
		"PRAGMA cache_size = -64000;", // 64MB cache
	}

	for _, p := range pragmas {
		if err := db.Exec(p).Error; err != nil {
			log.Printf("[DB WARN] Failed to execute pragma '%s': %v", p, err)
		}
	}

	// Auto-migrate tables
	if err := db.AutoMigrate(&Media{}, &Device{}); err != nil {
		return nil, fmt.Errorf("failed to auto-migrate database schema: %w", err)
	}

	// Migrate legacy global unique index on hash to per-device composite unique index
	_ = db.Exec("DROP INDEX IF EXISTS idx_medias_hash;").Error
	_ = db.Exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_device_hash ON medias(device_id, hash);").Error
	_ = db.Exec("CREATE INDEX IF NOT EXISTS idx_medias_hash ON medias(hash);").Error

	log.Printf("[DB] SQLite database initialized successfully at: %s (WAL enabled)", dbPath)
	return db, nil
}

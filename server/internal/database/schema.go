package database

import (
	"time"
)

// Media represents a backed-up photo or video file in the system.
type Media struct {
	ID            uint       `gorm:"primaryKey;autoIncrement" json:"id"`
	DeviceID      string     `gorm:"size:128;not null;uniqueIndex:idx_device_hash;index:idx_medias_device_id" json:"device_id"`
	Hash          string     `gorm:"size:64;not null;uniqueIndex:idx_device_hash;index:idx_medias_hash" json:"hash"` // SHA-256 checksum (hex)
	FileName      string     `gorm:"size:255;not null" json:"file_name"`
	FilePath      string     `gorm:"size:512;not null" json:"file_path"`
	ThumbnailPath string     `gorm:"size:512" json:"thumbnail_path,omitempty"`
	HasThumbnail  bool       `gorm:"default:false;index" json:"has_thumbnail"`
	FileSize      int64      `gorm:"not null" json:"file_size"`
	MimeType      string     `gorm:"size:128" json:"mime_type"`
	Extension     string     `gorm:"size:32" json:"extension"`
	Width         int        `gorm:"default:0" json:"width,omitempty"`
	Height        int        `gorm:"default:0" json:"height,omitempty"`
	Duration      float64    `gorm:"default:0" json:"duration,omitempty"` // Video duration in seconds
	TakenAt       *time.Time `gorm:"index" json:"taken_at,omitempty"`     // Captured time from EXIF or client
	IsFavorite    bool       `gorm:"default:false;index" json:"is_favorite"`
	CreatedAt     time.Time  `gorm:"index" json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

// TableName specifies table name for GORM.
func (Media) TableName() string {
	return "medias"
}

// Device represents a registered client device with an optional custom friendly name.
type Device struct {
	ID         uint      `gorm:"primaryKey;autoIncrement" json:"id"`
	DeviceID   string    `gorm:"size:128;uniqueIndex;not null" json:"device_id"`
	CustomName string    `gorm:"size:128;default:''" json:"custom_name"`
	Model      string    `gorm:"size:128;default:''" json:"model"`
	LastActive time.Time `gorm:"index" json:"last_active"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// TableName specifies table name for GORM.
func (Device) TableName() string {
	return "devices"
}

package database

import (
	"time"
)

// Media represents a backed-up photo or video file in the system.
type Media struct {
	ID            uint       `gorm:"primaryKey;autoIncrement" json:"id"`
	DeviceID      string     `gorm:"size:128;index;not null" json:"device_id"`
	Hash          string     `gorm:"size:64;uniqueIndex;not null" json:"hash"` // SHA-256 checksum (hex)
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
	CreatedAt     time.Time  `gorm:"index" json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

// TableName specifies table name for GORM.
func (Media) TableName() string {
	return "medias"
}

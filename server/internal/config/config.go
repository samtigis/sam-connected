package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// AppConfig holds persistent user preferences.
type AppConfig struct {
	StoragePath string `json:"storage_path"`
	Port        int    `json:"port"`
	DBPath      string `json:"db_path"`
	Headless    bool   `json:"headless"`
}

// ConfigService manages loading and saving persistent configuration.
type ConfigService struct {
	filePath string
	config   AppConfig
	mu       sync.RWMutex
}

// NewConfigService initializes configuration with sensible defaults.
func NewConfigService() *ConfigService {
	// Default storage path: try ~/Pictures/SamConnectedBackup, fallback to ~/SamConnectedBackup or ./storage
	homeDir, _ := os.UserHomeDir()
	defaultStorage := filepath.Join(homeDir, "Pictures", "SamConnectedBackup")
	if err := os.MkdirAll(defaultStorage, 0755); err != nil {
		defaultStorage = filepath.Join(homeDir, "SamConnectedBackup")
		if err := os.MkdirAll(defaultStorage, 0755); err != nil {
			defaultStorage = "./storage"
		}
	}

	// Determine config file path in AppData or executable directory
	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = homeDir
	}
	appDir := filepath.Join(configDir, "SamConnected")
	_ = os.MkdirAll(appDir, 0755)
	configFile := filepath.Join(appDir, "config.json")

	svc := &ConfigService{
		filePath: configFile,
		config: AppConfig{
			StoragePath: defaultStorage,
			Port:        8080,
			DBPath:      "",
			Headless:    false,
		},
	}

	svc.Load()
	return svc
}

// Load reads config from disk if available.
func (s *ConfigService) Load() {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.filePath)
	if err != nil {
		return
	}

	var loaded AppConfig
	if err := json.Unmarshal(data, &loaded); err == nil {
		if loaded.StoragePath != "" {
			s.config.StoragePath = loaded.StoragePath
		}
		if loaded.Port > 0 {
			s.config.Port = loaded.Port
		}
		s.config.DBPath = loaded.DBPath
		s.config.Headless = loaded.Headless
	}
}

// Save persists config to disk.
func (s *ConfigService) Save() error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	data, err := json.MarshalIndent(s.config, "", "  ")
	if err != nil {
		return err
	}

	_ = os.MkdirAll(filepath.Dir(s.filePath), 0755)
	return os.WriteFile(s.filePath, data, 0644)
}

// Get returns the current configuration copy.
func (s *ConfigService) Get() AppConfig {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.config
}

// SetStoragePath updates storage directory and saves.
func (s *ConfigService) SetStoragePath(newPath string) error {
	s.mu.Lock()
	s.config.StoragePath = newPath
	s.mu.Unlock()
	return s.Save()
}

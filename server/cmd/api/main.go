package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"

	"github.com/samtigis/sam-connected/server/internal/database"
	"github.com/samtigis/sam-connected/server/internal/discovery"
	"github.com/samtigis/sam-connected/server/internal/handler"
	"github.com/samtigis/sam-connected/server/internal/service"
)

func main() {
	// Parse CLI flags and environment variables
	portFlag := flag.Int("port", getEnvInt("PORT", 8080), "Server port")
	storageFlag := flag.String("storage", getEnv("STORAGE_DIR", "./storage"), "Base storage directory")
	dbFlag := flag.String("db", getEnv("DB_PATH", ""), "Path to SQLite database file")
	mdnsNameFlag := flag.String("mdns-name", getEnv("MDNS_NAME", "SamConnectedStorage"), "mDNS instance broadcast name")
	flag.Parse()

	// Default database file inside storage directory if not specified
	dbPath := *dbFlag
	if dbPath == "" {
		dbPath = filepath.Join(*storageFlag, "sam_backup.db")
	}

	log.Printf("[INIT] Starting Sam Connected Local Auto-Backup Engine")
	log.Printf("[INIT] Storage Path: %s", *storageFlag)
	log.Printf("[INIT] Database Path: %s", dbPath)
	log.Printf("[INIT] HTTP Port: %d", *portFlag)

	// 1. Initialize Database (CGO-free SQLite with WAL)
	db, err := database.InitDB(dbPath)
	if err != nil {
		log.Fatalf("[FATAL] Could not initialize database: %v", err)
	}

	// 2. Initialize Core Services
	hasherSvc := service.NewHasher()
	thumbSvc := service.NewThumbnailService()
	storageSvc, err := service.NewStorageService(*storageFlag, db, thumbSvc, hasherSvc)
	if err != nil {
		log.Fatalf("[FATAL] Could not initialize storage service: %v", err)
	}

	// 3. Initialize mDNS Service (_photobackup._tcp)
	mdnsSvc := discovery.NewMDNSService(*mdnsNameFlag, *portFlag)
	if err := mdnsSvc.Start(); err != nil {
		log.Printf("[WARN] mDNS broadcast could not start (non-fatal): %v", err)
	}
	defer mdnsSvc.Stop()

	// 4. Initialize Fiber App (4GB BodyLimit for video files)
	app := fiber.New(fiber.Config{
		BodyLimit:             4 * 1024 * 1024 * 1024, // 4 Gigabytes
		ReadTimeout:           30 * time.Minute,       // Generous timeout for large video uploads
		WriteTimeout:          30 * time.Minute,
		ServerHeader:          "SamConnected-BackupEngine/1.0",
		DisableStartupMessage: false,
	})

	// Global Middlewares
	app.Use(recover.New())
	app.Use(logger.New(logger.Config{
		Format:     "[${time}] ${status} - ${latency} ${method} ${path}\n",
		TimeFormat: "15:04:05",
		TimeZone:   "Local",
	}))
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowMethods: "GET,POST,HEAD,PUT,DELETE,PATCH,OPTIONS",
		AllowHeaders: "*",
	}))

	// 5. Initialize Handlers
	healthHandler := handler.NewHealthHandler(*storageFlag)
	syncHandler := handler.NewSyncHandler(db, storageSvc)
	mediaHandler := handler.NewMediaHandler(db, storageSvc, thumbSvc)

	// 6. Register API Routes
	api := app.Group("/api/v1")
	{
		// Ping & Disk usage
		api.Get("/ping", healthHandler.Ping)

		// Sync endpoints
		syncGroup := api.Group("/sync")
		{
			syncGroup.Post("/preflight", syncHandler.Preflight)
			syncGroup.Post("/upload", syncHandler.Upload)
		}

		// Media retrieval & streaming
		mediaGroup := api.Group("/media")
		{
			mediaGroup.Get("/", mediaHandler.List)
			mediaGroup.Get("/:id/thumb", mediaHandler.GetThumbnail)
			mediaGroup.Get("/:id/raw", mediaHandler.GetRaw)
		}
	}

	// 7. Setup Graceful Shutdown channel
	shutdownChan := make(chan os.Signal, 1)
	signal.Notify(shutdownChan, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	go func() {
		addr := fmt.Sprintf("0.0.0.0:%d", *portFlag)
		log.Printf("[SERVER] Listening on http://%s", addr)
		if err := app.Listen(addr); err != nil {
			log.Printf("[SERVER] Server closed: %v", err)
		}
	}()

	// Wait for shutdown signal
	sig := <-shutdownChan
	log.Printf("[SHUTDOWN] Received signal: %s. Initiating graceful termination...", sig)

	// Stop mDNS broadcast first so clients discover server is closing
	mdnsSvc.Stop()

	// Shutdown Fiber web engine with 10s deadline
	if err := app.ShutdownWithTimeout(10 * time.Second); err != nil {
		log.Printf("[SHUTDOWN] Fiber shutdown error: %v", err)
	}

	// Close database connection
	if sqlDB, err := db.DB(); err == nil {
		_ = sqlDB.Close()
	}

	log.Println("[SHUTDOWN] Sam Connected backup engine terminated cleanly.")
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
	}
	return defaultVal
}

package main

import (
	"flag"
	"fmt"
	"log"
	"mime"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"syscall"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/filesystem"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"

	"github.com/samtigis/sam-connected/server/internal/config"
	"github.com/samtigis/sam-connected/server/internal/database"
	"github.com/samtigis/sam-connected/server/internal/discovery"
	"github.com/samtigis/sam-connected/server/internal/gui"
	"github.com/samtigis/sam-connected/server/internal/handler"
	"github.com/samtigis/sam-connected/server/internal/logbuffer"
	"github.com/samtigis/sam-connected/server/internal/service"
	"github.com/samtigis/sam-connected/server/internal/web"
)

func init() {
	// Register essential video and image MIME types to guarantee correct streaming headers on all OSes
	_ = mime.AddExtensionType(".mov", "video/quicktime")
	_ = mime.AddExtensionType(".MOV", "video/quicktime")
	_ = mime.AddExtensionType(".mp4", "video/mp4")
	_ = mime.AddExtensionType(".MP4", "video/mp4")
	_ = mime.AddExtensionType(".m4v", "video/x-m4v")
	_ = mime.AddExtensionType(".M4V", "video/x-m4v")
	_ = mime.AddExtensionType(".webm", "video/webm")
	_ = mime.AddExtensionType(".heic", "image/heic")
	_ = mime.AddExtensionType(".HEIC", "image/heic")
}

func main() {
	// Hook log output into GUI log buffer and standard output
	logWriter := logbuffer.NewWriter(logbuffer.DefaultBuffer, os.Stdout)
	log.SetOutput(logWriter)

	// Load persistent configuration
	configSvc := config.NewConfigService()
	savedCfg := configSvc.Get()

	// Parse CLI flags and environment variables
	portFlag := flag.Int("port", getEnvInt("PORT", savedCfg.Port), "Server port")
	storageFlag := flag.String("storage", getEnv("STORAGE_DIR", savedCfg.StoragePath), "Base storage directory")
	dbFlag := flag.String("db", getEnv("DB_PATH", savedCfg.DBPath), "Path to SQLite database file")
	mdnsNameFlag := flag.String("mdns-name", getEnv("MDNS_NAME", "SamConnectedStorage"), "mDNS instance broadcast name")
	headlessFlag := flag.Bool("headless", false, "Run in headless mode without desktop GUI")
	cliFlag := flag.Bool("cli", false, "Alias for -headless")
	flag.Parse()

	isHeadless := *headlessFlag || *cliFlag || savedCfg.Headless
	if !isHeadless {
		// Immediately hide black console window in GUI mode
		gui.HideConsoleWindow()
	}

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
	storageSvc.BackfillMissingThumbnails()

	// 3. Initialize Discovery Services: mDNS (_photobackup._tcp) & UDP Beacon (Port 8088)
	mdnsSvc := discovery.NewMDNSService(*mdnsNameFlag, *portFlag)
	if err := mdnsSvc.Start(); err != nil {
		log.Printf("[WARN] mDNS broadcast could not start (non-fatal): %v", err)
	}
	defer mdnsSvc.Stop()

	beaconSvc := discovery.NewBeaconService(*mdnsNameFlag, *portFlag, 8088)
	if err := beaconSvc.Start(); err != nil {
		log.Printf("[WARN] UDP discovery beacon could not start (non-fatal): %v", err)
	}
	defer beaconSvc.Stop()

	localLANIP := discovery.GetBestLocalIPv4()
	log.Printf("[DISCOVERY] Server local IP: %s | API: http://%s:%d/api/v1", localLANIP, localLANIP, *portFlag)

	// 4. Initialize Fiber App (4GB BodyLimit for video files)
	app := fiber.New(fiber.Config{
		BodyLimit:             4 * 1024 * 1024 * 1024, // 4 Gigabytes
		ReadTimeout:           30 * time.Minute,       // Generous timeout for large video uploads
		WriteTimeout:          30 * time.Minute,
		ServerHeader:          "SamConnected-BackupEngine/1.0",
		DisableStartupMessage: true,
	})

	// Global Middlewares
	app.Use(recover.New())
	app.Use(logger.New(logger.Config{
		Output:     logWriter,
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
	systemHandler := handler.NewSystemHandler(configSvc, storageSvc, healthHandler, db, func(newPath string) {
		log.Printf("[STORAGE] Storage location updated to: %s", newPath)
	})

	// 6. Register API Routes
	api := app.Group("/api/v1")
	{
		// Ping & Disk usage
		api.Get("/ping", healthHandler.Ping)

		// System & GUI integration endpoints
		systemGroup := api.Group("/system")
		{
			systemGroup.Get("/config", systemHandler.GetConfig)
			systemGroup.Post("/choose-folder", systemHandler.ChooseFolder)
			systemGroup.Post("/set-folder", systemHandler.SetFolder)
			systemGroup.Post("/open-folder", systemHandler.OpenFolder)
			systemGroup.Get("/logs", systemHandler.GetLogs)
			systemGroup.Post("/clear-logs", systemHandler.ClearLogs)
		}

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
			mediaGroup.Get("/timeline", mediaHandler.GetTimeline)
			mediaGroup.Get("/:id", mediaHandler.GetByID)
			mediaGroup.Post("/:id/favorite", mediaHandler.ToggleFavorite)
			mediaGroup.Delete("/:id", mediaHandler.Delete)
			mediaGroup.Get("/:id/thumb", mediaHandler.GetThumbnail)
			mediaGroup.Get("/:id/raw", mediaHandler.GetRaw)
			mediaGroup.Get("/:id/raw/*", mediaHandler.GetRaw)
			mediaGroup.Get("/:id/raw*", mediaHandler.GetRaw)
		}

		// Device listing & multi-client discovery
		api.Get("/devices", mediaHandler.GetDevices)
		api.Post("/devices/:id/name", mediaHandler.SetDeviceName)
		api.Put("/devices/:id/name", mediaHandler.SetDeviceName)
		app.Get("/devices", mediaHandler.GetDevices)
		app.Get("/api/devices", mediaHandler.GetDevices)
		app.Post("/api/v1/devices/:id/name", mediaHandler.SetDeviceName)
		app.Get("/api/v1/media/:id/thumb", mediaHandler.GetThumbnail)
		app.Get("/api/v1/media/:id/raw", mediaHandler.GetRaw)
		app.Get("/api/v1/media/:id/raw/*", mediaHandler.GetRaw)
		app.Get("/api/v1/media/:id/raw*", mediaHandler.GetRaw)
		app.Get("/media/:id/thumb", mediaHandler.GetThumbnail)
		app.Get("/media/:id/raw", mediaHandler.GetRaw)
		app.Get("/media/:id/raw/*", mediaHandler.GetRaw)
		app.Get("/media/:id/raw*", mediaHandler.GetRaw)
	}

	// 7. Serve Embedded Desktop Web UI at root (/)
	app.Use("/", filesystem.New(filesystem.Config{
		Root:   web.GetStaticFileSystem(),
		Index:  "index.html",
		Browse: false,
	}))

	// 8. Setup Graceful Shutdown channel
	shutdownChan := make(chan os.Signal, 1)
	signal.Notify(shutdownChan, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	serverAddr := fmt.Sprintf("127.0.0.1:%d", *portFlag)
	guiURL := fmt.Sprintf("http://127.0.0.1:%d", *portFlag)

	go func() {
		bindAddr := fmt.Sprintf("0.0.0.0:%d", *portFlag)
		log.Printf("[SERVER] Listening on http://%s", bindAddr)
		if err := app.Listen(bindAddr); err != nil {
			log.Printf("[SERVER] Server closed: %v", err)
		}
	}()

	// Give the server a brief moment to bind before starting GUI
	time.Sleep(350 * time.Millisecond)

	// 9. Launch Native Desktop GUI Window on Windows (if not headless)
	if !isHeadless {
		log.Printf("[GUI] Launching native Windows Host Dashboard window (%s)...", guiURL)
		runtime.LockOSThread()
		guiLaunched := gui.LaunchGUI(
			guiURL,
			*storageFlag,
			func() string {
				p, _ := gui.PickFolderDialog(*storageFlag)
				return p
			},
			func(path string) {
				_ = gui.OpenFolderInExplorer(path)
			},
			func() {
				log.Printf("[GUI] Native window closed by user. Exiting application...")
			},
		)
		if !guiLaunched {
			log.Printf("[INFO] Running in background server mode. Dashboard available at: %s", guiURL)
			sig := <-shutdownChan
			log.Printf("[SHUTDOWN] Received signal: %s. Initiating graceful termination...", sig)
		}
	} else {
		log.Printf("[INFO] Running in headless/CLI mode. Dashboard available at: %s", serverAddr)
		// Wait for shutdown signal
		sig := <-shutdownChan
		log.Printf("[SHUTDOWN] Received signal: %s. Initiating graceful termination...", sig)
	}

	// Stop discovery services first so clients immediately know server is closing
	beaconSvc.Stop()
	mdnsSvc.Stop()

	// Shutdown Fiber web engine with 5s deadline
	if err := app.ShutdownWithTimeout(5 * time.Second); err != nil {
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

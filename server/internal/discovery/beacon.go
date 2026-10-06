package discovery

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"strings"
	"sync"
	"time"
)

// BeaconPayload represents the server metadata advertised over UDP
type BeaconPayload struct {
	Service   string    `json:"service"`   // "sam-connected-backup"
	Name      string    `json:"name"`      // "Sam Connected Server (Windows)"
	Version   string    `json:"version"`   // "1.0.0"
	Port      int       `json:"port"`      // HTTP port e.g. 8080
	IP        string    `json:"ip"`        // Local LAN IP e.g. "192.168.1.35"
	Path      string    `json:"path"`      // "/api/v1"
	Status    string    `json:"status"`    // "online" | "offline"
	Timestamp time.Time `json:"timestamp"`
}

// BeaconService manages UDP beacon broadcasting and responsive query handling
type BeaconService struct {
	instanceName string
	httpPort     int
	udpPort      int
	conn         *net.UDPConn
	stopChan     chan struct{}
	mu           sync.Mutex
	running      bool
}

// NewBeaconService creates a new BeaconService
func NewBeaconService(instanceName string, httpPort, udpPort int) *BeaconService {
	if udpPort <= 0 {
		udpPort = 8088
	}
	if instanceName == "" {
		instanceName = "Sam Connected Server"
	}
	return &BeaconService{
		instanceName: instanceName,
		httpPort:     httpPort,
		udpPort:      udpPort,
		stopChan:     make(chan struct{}),
	}
}

// Start binds the UDP port and starts both beacon broadcasting and query response loops
func (b *BeaconService) Start() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.running {
		return nil
	}

	addr := &net.UDPAddr{
		Port: b.udpPort,
		IP:   net.IPv4zero,
	}

	conn, err := net.ListenUDP("udp4", addr)
	if err != nil {
		return fmt.Errorf("could not bind UDP discovery port %d: %w", b.udpPort, err)
	}

	b.conn = conn
	b.running = true

	log.Printf("[BEACON] Local network UDP Discovery Beacon active on port %d", b.udpPort)

	// Goroutine 1: Respond to active discovery pings ("SAM_CONNECTED_DISCOVER")
	go b.listenForQueries()

	// Goroutine 2: Broadcast periodic beacon pulses into the LAN
	go b.broadcastLoop()

	return nil
}

func (b *BeaconService) listenForQueries() {
	buf := make([]byte, 1024)
	for {
		select {
		case <-b.stopChan:
			return
		default:
		}

		_ = b.conn.SetReadDeadline(time.Now().Add(1 * time.Second))
		n, remoteAddr, err := b.conn.ReadFrom(buf)
		if err != nil {
			continue
		}

		msg := strings.TrimSpace(string(buf[:n]))
		if strings.Contains(msg, "SAM_CONNECTED_DISCOVER") {
			b.sendResponse(remoteAddr)
		}
	}
}

func (b *BeaconService) sendResponse(remoteAddr net.Addr) {
	bestIP := GetBestLocalIPv4()
	payload := BeaconPayload{
		Service:   "sam-connected-backup",
		Name:      b.instanceName,
		Version:   "1.0.0",
		Port:      b.httpPort,
		IP:        bestIP,
		Path:      "/api/v1",
		Status:    "online",
		Timestamp: time.Now().UTC(),
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return
	}

	_, _ = b.conn.WriteTo(data, remoteAddr)
}

func (b *BeaconService) broadcastLoop() {
	// Rapid initial bursts on startup (0ms, 400ms, 800ms) for instant client detection
	for i := 0; i < 3; i++ {
		select {
		case <-b.stopChan:
			return
		default:
			b.broadcastOnce("online")
			time.Sleep(400 * time.Millisecond)
		}
	}

	ticker := time.NewTicker(2500 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-b.stopChan:
			return
		case <-ticker.C:
			b.broadcastOnce("online")
		}
	}
}

func (b *BeaconService) broadcastOnce(status string) {
	b.mu.Lock()
	conn := b.conn
	b.mu.Unlock()

	if conn == nil {
		return
	}

	bestIP := GetBestLocalIPv4()
	payload := BeaconPayload{
		Service:   "sam-connected-backup",
		Name:      b.instanceName,
		Version:   "1.0.0",
		Port:      b.httpPort,
		IP:        bestIP,
		Path:      "/api/v1",
		Status:    status,
		Timestamp: time.Now().UTC(),
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return
	}

	destinations := GetBroadcastAddresses()
	for _, dstIP := range destinations {
		dstAddr := &net.UDPAddr{
			IP:   net.ParseIP(dstIP),
			Port: b.udpPort,
		}
		_, _ = conn.WriteTo(data, dstAddr)
	}
}

// Stop terminates the beacon service and broadcasts an offline notification
func (b *BeaconService) Stop() {
	b.mu.Lock()
	if !b.running {
		b.mu.Unlock()
		return
	}
	b.running = false
	close(b.stopChan)

	if b.conn != nil {
		b.broadcastOnce("offline")
		_ = b.conn.Close()
		b.conn = nil
	}
	b.mu.Unlock()

	log.Println("[BEACON] UDP Discovery Beacon stopped gracefully.")
}

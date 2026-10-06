package discovery

import (
	"fmt"
	"log"
	"os"

	"github.com/grandcat/zeroconf"
)

// MDNSService manages the zeroconf mDNS advertisement.
type MDNSService struct {
	server *zeroconf.Server
	port   int
	name   string
}

// NewMDNSService creates a new mDNS broadcaster instance.
func NewMDNSService(instanceName string, port int) *MDNSService {
	if instanceName == "" {
		host, err := os.Hostname()
		if err != nil {
			instanceName = "SamConnectedHost"
		} else {
			instanceName = fmt.Sprintf("SamConnected-%s", host)
		}
	}
	return &MDNSService{
		name: instanceName,
		port: port,
	}
}

// Start begins advertising the service via mDNS (_photobackup._tcp).
func (m *MDNSService) Start() error {
	serviceType := "_photobackup._tcp"
	domain := "local."
	bestIP := GetBestLocalIPv4()
	txtRecords := []string{
		"version=1.0",
		"path=/api/v1",
		"app=sam-connected",
		fmt.Sprintf("ip=%s", bestIP),
		fmt.Sprintf("port=%d", m.port),
	}

	server, err := zeroconf.Register(
		m.name,
		serviceType,
		domain,
		m.port,
		txtRecords,
		nil, // all active network interfaces
	)
	if err != nil {
		return fmt.Errorf("failed to register zeroconf mDNS service: %w", err)
	}

	m.server = server
	log.Printf("[mDNS] Service registered: '%s' on %s:%d (%s)", m.name, domain, m.port, serviceType)
	return nil
}

// Stop terminates the mDNS broadcast.
func (m *MDNSService) Stop() {
	if m.server != nil {
		m.server.Shutdown()
		m.server = nil
		log.Println("[mDNS] Broadcast stopped gracefully.")
	}
}

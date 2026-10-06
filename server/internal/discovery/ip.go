package discovery

import (
	"net"
	"strings"
)

// GetBestLocalIPv4 finds the most suitable non-virtual IPv4 LAN address
// Prioritizes real Wi-Fi and Ethernet adapters, filtering out virtual adapters (WSL, Hyper-V, Docker, VPN).
func GetBestLocalIPv4() string {
	interfaces, err := net.Interfaces()
	if err != nil {
		return "127.0.0.1"
	}

	var candidates []string

	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}

		name := strings.ToLower(iface.Name)
		// Skip virtual, docker, wsl, vpn, and hypervisor adapters
		if strings.Contains(name, "vethernet") ||
			strings.Contains(name, "wsl") ||
			strings.Contains(name, "virtual") ||
			strings.Contains(name, "vmnet") ||
			strings.Contains(name, "vmware") ||
			strings.Contains(name, "docker") ||
			strings.Contains(name, "tailscale") ||
			strings.Contains(name, "zerotier") ||
			strings.Contains(name, "hyper-v") ||
			strings.Contains(name, "tap") ||
			strings.Contains(name, "tun") {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}

		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}

			if ip == nil || ip.IsLoopback() || ip.To4() == nil {
				continue
			}

			ipStr := ip.String()
			// Prioritize typical home/office Wi-Fi and LAN subnets (192.168.x.x, 10.x.x.x)
			if strings.HasPrefix(ipStr, "192.168.") || strings.HasPrefix(ipStr, "10.") {
				return ipStr
			}
			candidates = append(candidates, ipStr)
		}
	}

	if len(candidates) > 0 {
		return candidates[0]
	}

	return "127.0.0.1"
}

// GetBroadcastAddresses returns broadcast addresses for all active LAN interfaces (e.g. 192.168.1.255) plus 255.255.255.255
func GetBroadcastAddresses() []string {
	broadcasts := []string{"255.255.255.255"}

	interfaces, err := net.Interfaces()
	if err != nil {
		return broadcasts
	}

	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		name := strings.ToLower(iface.Name)
		if strings.Contains(name, "vethernet") ||
			strings.Contains(name, "wsl") ||
			strings.Contains(name, "virtual") ||
			strings.Contains(name, "docker") ||
			strings.Contains(name, "tailscale") {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}

		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if !ok || ipNet.IP.To4() == nil || ipNet.IP.IsLoopback() {
				continue
			}

			ip := ipNet.IP.To4()
			mask := ipNet.Mask
			if len(mask) == 4 {
				// Compute broadcast IP: ip | ^mask
				bcast := make(net.IP, 4)
				for i := 0; i < 4; i++ {
					bcast[i] = ip[i] | ^mask[i]
				}
				bcastStr := bcast.String()
				if bcastStr != "255.255.255.255" {
					broadcasts = append(broadcasts, bcastStr)
				}
			}
		}
	}

	return broadcasts
}

package validation

import (
	"errors"
	"net"
	"testing"
)

func TestValidateTargetDirectIP(t *testing.T) {
	tests := []struct {
		name         string
		target       string
		allowPrivate bool
		wantError    bool
	}{
		{
			name:      "public IPv4",
			target:    "8.8.8.8",
			wantError: false,
		},
		{
			name:      "public IPv6",
			target:    "2606:4700:4700::1111",
			wantError: false,
		},
		{
			name:      "loopback IPv4",
			target:    "127.0.0.1",
			wantError: true,
		},
		{
			name:      "loopback IPv6",
			target:    "::1",
			wantError: true,
		},
		{
			name:      "private IPv4",
			target:    "192.168.1.1",
			wantError: true,
		},
		{
			name:         "private IPv4 with development override",
			target:       "192.168.1.1",
			allowPrivate: true,
			wantError:    false,
		},
		{
			name:      "cloud metadata IPv4",
			target:    "169.254.169.254",
			wantError: true,
		},
		{
			name:      "unspecified IPv4",
			target:    "0.0.0.0",
			wantError: true,
		},
		{
			name:      "multicast IPv4",
			target:    "224.0.0.1",
			wantError: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := ValidateTarget(test.target, test.allowPrivate, nil)
			if test.wantError && err == nil {
				t.Fatal("expected an error, but received nil")
			}
			if test.wantError && !IsBlockedTargetError(err) {
				t.Fatalf("expected blocked-target classification, got %v", err)
			}

			if !test.wantError && err != nil {
				t.Fatalf("expected no error, but received: %v", err)
			}
		})
	}
}

func TestValidateTargetRejectsInvalidHostname(t *testing.T) {
	tests := []string{
		"bad host name",
		"http://example.com",
		"example.com:443",
		"example.com/path",
		"-example.com",
		"example-.com",
	}

	for _, target := range tests {
		t.Run(target, func(t *testing.T) {
			_, err := ValidateTarget(target, false, nil)
			if err == nil {
				t.Fatal("expected an error, but received nil")
			}
		})
	}
}

func TestValidateTargetResolvesHostnames(t *testing.T) {
	originalLookupIP := lookupIP
	t.Cleanup(func() {
		lookupIP = originalLookupIP
	})

	lookupIP = func(host string) ([]net.IP, error) {
		if host != "scanme.example" {
			return nil, errors.New("unexpected host")
		}
		return []net.IP{net.ParseIP("8.8.8.8")}, nil
	}

	target, err := ValidateTarget("scanme.example", false, nil)
	if err != nil {
		t.Fatalf("expected hostname to validate: %v", err)
	}

	if len(target.IPs) != 1 || !target.IPs[0].Equal(net.ParseIP("8.8.8.8")) {
		t.Fatalf("expected resolved public IP, got %#v", target.IPs)
	}
}

func TestValidateTargetRejectsHostnameWithBlockedResolvedIP(t *testing.T) {
	originalLookupIP := lookupIP
	t.Cleanup(func() {
		lookupIP = originalLookupIP
	})

	lookupIP = func(host string) ([]net.IP, error) {
		return []net.IP{
			net.ParseIP("8.8.8.8"),
			net.ParseIP("192.168.1.10"),
		}, nil
	}

	_, err := ValidateTarget("mixed.example", false, nil)
	if err == nil {
		t.Fatal("expected hostname resolving to private IP to be rejected")
	}
	if !IsBlockedTargetError(err) {
		t.Fatalf("expected blocked-target classification, got %v", err)
	}
}

func TestValidateTargetAllowlist(t *testing.T) {
	_, err := ValidateTarget("8.8.8.8", false, []string{"1.1.1.1"})
	if err == nil {
		t.Fatal("expected target outside allowlist to be rejected")
	}
	if !IsBlockedTargetError(err) {
		t.Fatalf("expected blocked-target classification, got %v", err)
	}

	_, err = ValidateTarget("8.8.8.8", false, []string{"8.8.8.8"})
	if err != nil {
		t.Fatalf("expected target inside allowlist to be accepted: %v", err)
	}
}

func TestValidatePortRange(t *testing.T) {
	tests := []struct {
		name      string
		startPort int
		endPort   int
		wantError bool
	}{
		{
			name:      "valid single port",
			startPort: 80,
			endPort:   80,
			wantError: false,
		},
		{
			name:      "valid small range",
			startPort: 20,
			endPort:   25,
			wantError: false,
		},
		{
			name:      "start port below minimum",
			startPort: 0,
			endPort:   80,
			wantError: true,
		},
		{
			name:      "end port above maximum",
			startPort: 80,
			endPort:   65536,
			wantError: true,
		},
		{
			name:      "reversed range",
			startPort: 100,
			endPort:   20,
			wantError: true,
		},
		{
			name:      "too many ports",
			startPort: 1,
			endPort:   1001,
			wantError: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			err := ValidatePortRange(
				test.startPort,
				test.endPort,
				MaximumPorts,
			)

			if test.wantError && err == nil {
				t.Fatal("expected an error, but received nil")
			}

			if !test.wantError && err != nil {
				t.Fatalf(
					"expected no error, but received: %v",
					err,
				)
			}
		})
	}
}

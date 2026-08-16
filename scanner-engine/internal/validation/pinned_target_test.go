package validation

import (
	"net"
	"strconv"
	"testing"
)

func TestPinnedTargetRejectsPublicToPrivateDNSChange(t *testing.T) {
	pinned, err := ValidatePinnedTarget("scan.example", []string{"8.8.8.8"}, false, nil)
	if err != nil {
		t.Fatalf("validate pin: %v", err)
	}
	withLookup(t, func(string) ([]net.IP, error) {
		return []net.IP{net.ParseIP("127.0.0.1")}, nil
	})
	if err := VerifyCurrentResolution(pinned); !IsBlockedTargetError(err) {
		t.Fatalf("expected changed private answer to be blocked, got %v", err)
	}
}

func TestPinnedTargetRejectsDifferentPublicDNSChange(t *testing.T) {
	pinned, err := ValidatePinnedTarget("scan.example", []string{"8.8.8.8"}, false, nil)
	if err != nil {
		t.Fatalf("validate pin: %v", err)
	}
	withLookup(t, func(string) ([]net.IP, error) {
		return []net.IP{net.ParseIP("1.1.1.1")}, nil
	})
	if err := VerifyCurrentResolution(pinned); !IsBlockedTargetError(err) {
		t.Fatalf("expected changed public answer to be blocked, got %v", err)
	}
}

func TestPinnedTargetAcceptsExactMultiAnswerSetInAnyOrder(t *testing.T) {
	pinned, err := ValidatePinnedTarget("scan.example",
		[]string{"8.8.8.8", "2606:4700:4700::1111"}, false, nil)
	if err != nil {
		t.Fatalf("validate pins: %v", err)
	}
	withLookup(t, func(string) ([]net.IP, error) {
		return []net.IP{net.ParseIP("2606:4700:4700::1111"), net.ParseIP("8.8.8.8")}, nil
	})
	if err := VerifyCurrentResolution(pinned); err != nil {
		t.Fatalf("expected exact multi-answer set to pass: %v", err)
	}
}

func TestPinnedTargetRejectsAbsentUnsafeAndDuplicateSets(t *testing.T) {
	tests := []struct {
		name      string
		addresses []string
	}{
		{name: "absent", addresses: nil},
		{name: "unsafe", addresses: []string{"127.0.0.1"}},
		{name: "duplicate", addresses: []string{"8.8.8.8", "8.8.8.8"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := ValidatePinnedTarget("scan.example", test.addresses, false, nil); err == nil {
				t.Fatal("expected address set to be rejected")
			}
		})
	}
}

func TestPinnedTargetCapsAddressPortAmplification(t *testing.T) {
	addresses := make([]string, 0, MaximumTargetAddresses+1)
	for index := 1; index <= MaximumTargetAddresses+1; index++ {
		addresses = append(addresses, "8.8.8."+strconv.Itoa(index))
	}
	if _, err := ValidatePinnedTarget("scan.example", addresses, false, nil); !IsBlockedTargetError(err) {
		t.Fatalf("expected oversized address set to be blocked, got %v", err)
	}
}

func TestPinnedTargetRejectsSpecialUseAndMappedUnsafeAddresses(t *testing.T) {
	addresses := []string{
		"100.64.0.1", "198.18.0.1", "192.0.2.1", "240.0.0.1",
		"2001:db8::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1",
	}
	for _, address := range addresses {
		t.Run(address, func(t *testing.T) {
			if _, err := ValidatePinnedTarget("scan.example", []string{address}, false, nil); !IsBlockedTargetError(err) {
				t.Fatalf("expected special-use address to be blocked, got %v", err)
			}
		})
	}
}

func withLookup(t *testing.T, lookup func(string) ([]net.IP, error)) {
	t.Helper()
	original := lookupIP
	lookupIP = lookup
	t.Cleanup(func() { lookupIP = original })
}

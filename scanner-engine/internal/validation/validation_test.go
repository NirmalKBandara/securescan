package validation

import "testing"

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

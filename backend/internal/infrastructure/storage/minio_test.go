package storage_test

import (
	"strings"
	"testing"

	"github.com/turfinn/backend/internal/infrastructure/storage"
)

func TestPublicURL(t *testing.T) {
	tests := []struct {
		endpoint string
		bucket   string
		key      string
		useSSL   bool
		want     string
	}{
		{
			endpoint: "localhost:9000",
			bucket:   "avatars",
			key:      "user-123.jpg",
			useSSL:   false,
			want:     "http://localhost:9000/avatars/user-123.jpg",
		},
		{
			endpoint: "minio.example.com",
			bucket:   "pitch-images",
			key:      "abc/photo.png",
			useSSL:   true,
			want:     "https://minio.example.com/pitch-images/abc/photo.png",
		},
	}
	for _, tt := range tests {
		got := storage.PublicURL(tt.endpoint, tt.bucket, tt.key, tt.useSSL)
		if got != tt.want {
			t.Errorf("PublicURL(%q, %q, %q, %v) = %q, want %q",
				tt.endpoint, tt.bucket, tt.key, tt.useSSL, got, tt.want)
		}
	}
}

func TestAllowedBuckets(t *testing.T) {
	allowed := []string{"avatars", "pitch-images", "kyc-documents"}
	notAllowed := []string{"../etc", "admin", ""}
	for _, b := range allowed {
		if !storage.IsAllowedBucket(b) {
			t.Errorf("expected %q to be allowed", b)
		}
	}
	for _, b := range notAllowed {
		if storage.IsAllowedBucket(b) {
			t.Errorf("expected %q to be denied", b)
		}
	}
}

func TestGenerateKey(t *testing.T) {
	key := storage.GenerateKey("user-abc", "photo.jpg")
	// Should be: user-abc/<uuid>-photo.jpg
	if !strings.HasPrefix(key, "user-abc/") {
		t.Errorf("key %q should start with user-abc/", key)
	}
	if !strings.HasSuffix(key, "photo.jpg") {
		t.Errorf("key %q should end with photo.jpg", key)
	}
	// UUID segment should be present (format: user-abc/<36-char-uuid>-photo.jpg)
	parts := strings.SplitN(key, "/", 2)
	if len(parts) != 2 {
		t.Fatalf("expected two parts, got %d", len(parts))
	}
	inner := parts[1] // "<uuid>-photo.jpg"
	dashIdx := strings.Index(inner, "-photo.jpg")
	if dashIdx < 0 {
		t.Fatalf("filename not found in %q", inner)
	}
	uuidPart := inner[:dashIdx]
	if len(uuidPart) != 36 {
		t.Errorf("expected 36-char UUID, got %q (len=%d)", uuidPart, len(uuidPart))
	}
}

package storage

import (
	"context"
	"fmt"
	"net/url"
	"time"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

var allowedBuckets = map[string]bool{
	"avatars":       true,
	"pitch-images":  true,
	"kyc-documents": true,
}

// IsAllowedBucket returns true if the bucket name is on the allow-list.
func IsAllowedBucket(bucket string) bool {
	return allowedBuckets[bucket]
}

// PublicURL builds the public-read URL for a stored object.
func PublicURL(endpoint, bucket, key string, useSSL bool) string {
	scheme := "http"
	if useSSL {
		scheme = "https"
	}
	return fmt.Sprintf("%s://%s/%s/%s", scheme, endpoint, bucket, key)
}

// Config holds MinIO connection parameters.
type Config struct {
	Endpoint  string
	AccessKey string
	SecretKey string
	UseSSL    bool
}

// Client wraps the MinIO SDK client with bucket auto-creation.
type Client struct {
	mc       *minio.Client
	endpoint string
	useSSL   bool
}

// NewClient creates a MinIO client from an explicit Config and ensures all required buckets exist.
func NewClient(ctx context.Context, cfg Config) (*Client, error) {
	mc, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("minio client: %w", err)
	}
	c := &Client{mc: mc, endpoint: cfg.Endpoint, useSSL: cfg.UseSSL}
	if err := c.ensureBuckets(ctx); err != nil {
		return nil, err
	}
	return c, nil
}

func (c *Client) ensureBuckets(ctx context.Context) error {
	for bucket := range allowedBuckets {
		exists, err := c.mc.BucketExists(ctx, bucket)
		if err != nil {
			return fmt.Errorf("check bucket %q: %w", bucket, err)
		}
		if !exists {
			if err := c.mc.MakeBucket(ctx, bucket, minio.MakeBucketOptions{}); err != nil {
				return fmt.Errorf("create bucket %q: %w", bucket, err)
			}
		}
	}
	return nil
}

// PresignPutURL returns a presigned PUT URL valid for ttl duration.
func (c *Client) PresignPutURL(ctx context.Context, bucket, key string, ttl time.Duration) (string, error) {
	u, err := c.mc.PresignedPutObject(ctx, bucket, key, ttl)
	if err != nil {
		return "", fmt.Errorf("presign: %w", err)
	}
	return u.String(), nil
}

// ObjectURL returns the public URL for a stored object.
func (c *Client) ObjectURL(bucket, key string) string {
	return PublicURL(c.endpoint, bucket, key, c.useSSL)
}

// GenerateKey builds a unique storage key from a user ID prefix and filename.
func GenerateKey(prefix, filename string) string {
	return fmt.Sprintf("%s/%s-%s", prefix, uuid.NewString(), url.PathEscape(filename))
}

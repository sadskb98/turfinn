package handler

import (
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/infrastructure/storage"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

const presignTTL = 15 * time.Minute

// UploadHandler handles presigned URL generation for object storage.
type UploadHandler struct {
	store *storage.Client
}

// NewUploadHandler creates a new UploadHandler backed by the given storage client.
func NewUploadHandler(store *storage.Client) *UploadHandler {
	return &UploadHandler{store: store}
}

// Presign handles POST /api/v1/upload/presign.
// It returns a presigned PUT URL the client can use to upload a file directly to MinIO.
func (h *UploadHandler) Presign(c echo.Context) error {
	userID, ok := c.Get(authmw.UserIDKey).(uuid.UUID)
	if !ok {
		return response.Unauthorized(c)
	}

	var req dto.PresignRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	if !storage.IsAllowedBucket(req.Bucket) {
		return response.BadRequest(c, fmt.Sprintf("bucket %q not allowed", req.Bucket))
	}

	key := storage.GenerateKey(userID.String(), req.Filename)
	presignedURL, err := h.store.PresignPutURL(c.Request().Context(), req.Bucket, key, presignTTL)
	if err != nil {
		return response.InternalError(c)
	}

	return response.OK(c, dto.PresignResponse{
		URL:       presignedURL,
		Key:       key,
		PublicURL: h.store.ObjectURL(req.Bucket, key),
		ExpiresIn: int(presignTTL.Seconds()),
	})
}

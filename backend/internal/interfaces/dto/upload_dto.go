package dto

// PresignRequest is sent to POST /api/v1/upload/presign
type PresignRequest struct {
	Bucket   string `json:"bucket"   validate:"required"`
	Filename string `json:"filename" validate:"required,min=1,max=255"`
}

// PresignResponse is returned with the presigned PUT URL.
type PresignResponse struct {
	URL       string `json:"url"`
	Key       string `json:"key"`
	PublicURL string `json:"public_url"`
	ExpiresIn int    `json:"expires_in"` // seconds
}

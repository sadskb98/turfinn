package service

// strPtr returns a pointer to s, or nil if s is empty.
// Used to convert optional string fields to nullable DB columns.
func strPtr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

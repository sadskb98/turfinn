package dto

type DisputeResponse struct {
	ID             string `json:"id"`
	BookingID      string `json:"booking_id"`
	RaisedByName   string `json:"raised_by_name"`
	RaisedByID     string `json:"raised_by_id"`
	AgainstUserID  string `json:"against_user_id"`
	Reason         string `json:"reason"`
	Description    string `json:"description"`
	EvidenceURLs   string `json:"evidence_urls"`
	Status         string `json:"status"`
	Resolution     string `json:"resolution,omitempty"`
	InternalNotes  string `json:"internal_notes,omitempty"`
	CreatedAt      string `json:"created_at"`
	ResolvedAt     string `json:"resolved_at,omitempty"`
}

type CreateDisputeRequest struct {
	BookingID     string `json:"booking_id" validate:"required"`
	AgainstUserID string `json:"against_user_id"`
	Reason        string `json:"reason" validate:"required,oneof=pitch_not_available different_from_description manager_cancelled_late player_no_show payment_issue other"`
	Description   string `json:"description"`
	EvidenceURLs  string `json:"evidence_urls"`
}

type ResolveDisputeRequest struct {
	Resolution   string  `json:"resolution" validate:"required,oneof=full_refund partial_refund no_refund warning_issued account_suspended"`
	Note         string  `json:"note"`
	RefundAmount float64 `json:"refund_amount"`
}

type TicketResponse struct {
	ID          string              `json:"id"`
	UserName    string              `json:"user_name"`
	UserID      string              `json:"user_id"`
	Category    string              `json:"category"`
	Subject     string              `json:"subject"`
	Description string              `json:"description"`
	Priority    string              `json:"priority"`
	Status      string              `json:"status"`
	AssignedTo  string              `json:"assigned_to,omitempty"`
	Messages    []TicketMsgResponse `json:"messages,omitempty"`
	CreatedAt   string              `json:"created_at"`
	ResolvedAt  string              `json:"resolved_at,omitempty"`
}

type TicketMsgResponse struct {
	ID         string `json:"id"`
	SenderName string `json:"sender_name"`
	SenderID   string `json:"sender_id"`
	Body       string `json:"body"`
	IsInternal bool   `json:"is_internal"`
	CreatedAt  string `json:"created_at"`
}

type CreateTicketRequest struct {
	Category    string `json:"category" validate:"required,oneof=booking payment account other"`
	Subject     string `json:"subject" validate:"required"`
	Description string `json:"description"`
}

type ReplyTicketRequest struct {
	Body       string `json:"body" validate:"required"`
	IsInternal bool   `json:"is_internal"`
}

type AssignTicketRequest struct {
	AssignedTo string `json:"assigned_to" validate:"required"`
}

type AdminReviewResponse struct {
	ID            string `json:"id"`
	BookingID     string `json:"booking_id"`
	PitchName     string `json:"pitch_name"`
	PitchID       string `json:"pitch_id"`
	UserName      string `json:"user_name"`
	UserID        string `json:"user_id"`
	Rating        int    `json:"rating"`
	Comment       string `json:"comment"`
	Status        string `json:"status"`
	FlaggedReason string `json:"flagged_reason,omitempty"`
	CreatedAt     string `json:"created_at"`
}

type ModerateReviewRequest struct {
	Action string `json:"action" validate:"required,oneof=approve remove"`
	Reason string `json:"reason"`
}

type WarnUserRequest struct {
	Reason string `json:"reason" validate:"required"`
}

type UserActionResponse struct {
	ID         string `json:"id"`
	ActionType string `json:"action_type"`
	Reason     string `json:"reason"`
	IssuedBy   string `json:"issued_by"`
	ExpiresAt  string `json:"expires_at,omitempty"`
	CreatedAt  string `json:"created_at"`
}

type KYCResponse struct {
	ID               string `json:"id"`
	UserID           string `json:"user_id"`
	UserName         string `json:"user_name"`
	UserPhone        string `json:"user_phone"`
	NIDNumber        string `json:"nid_number"`
	NIDPhotoFrontURL string `json:"nid_photo_front_url"`
	NIDPhotoBackURL  string `json:"nid_photo_back_url"`
	SelfieURL        string `json:"selfie_url"`
	BusinessName     string `json:"business_name"`
	PayoutAccount    string `json:"payout_account"`
	Status           string `json:"status"`
	ReviewNote       string `json:"review_note,omitempty"`
	SubmittedAt      string `json:"submitted_at,omitempty"`
	ReviewedAt       string `json:"reviewed_at,omitempty"`
}

type RejectKYCRequest struct {
	Reason string `json:"reason" validate:"required"`
}

type SubmitKYCRequest struct {
	BusinessName     string `json:"business_name"       validate:"required"`
	NIDNumber        string `json:"nid_number"          validate:"required"`
	NIDPhotoFrontURL string `json:"nid_photo_front_url" validate:"required"`
	NIDPhotoBackURL  string `json:"nid_photo_back_url"  validate:"required"`
	SelfieURL        string `json:"selfie_url"          validate:"required"`
	PayoutAccount    string `json:"payout_account"      validate:"required"`
}

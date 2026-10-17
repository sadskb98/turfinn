package dto

// --- Auth ---

type SendOTPRequest struct {
	Phone string `json:"phone" validate:"required,min=7,max=15"`
}

type VerifyOTPRequest struct {
	Phone string `json:"phone" validate:"required"`
	OTP   string `json:"otp"   validate:"required,len=6"`
}

type GoogleSignInRequest struct {
	IDToken string `json:"id_token" validate:"required"`
}

type AuthResponse struct {
	Token string       `json:"token"`
	User  UserResponse `json:"user"`
}

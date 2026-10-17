package dto

type UpdateProfileRequest struct {
	Name       string `json:"name"`
	AvatarURL  string `json:"avatar_url"`
	Position   string `json:"position"`
	SkillLevel string `json:"skill_level"`
}

type UserResponse struct {
	ID         string `json:"id"`
	Phone      string `json:"phone"`
	Name       string `json:"name"`
	AvatarURL  string `json:"avatar_url"`
	Position   string `json:"position"`
	SkillLevel string `json:"skill_level"`
	Role       string `json:"role"`
}

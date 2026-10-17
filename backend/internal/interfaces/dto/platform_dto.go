package dto

type SettingsResponse struct {
	Key         string `json:"key"`
	Value       string `json:"value"`
	Description string `json:"description"`
	UpdatedAt   string `json:"updated_at"`
}

type UpdateSettingsRequest struct {
	Settings map[string]string `json:"settings" validate:"required"`
}

type SettingsAuditResponse struct {
	ID         string `json:"id"`
	SettingKey string `json:"setting_key"`
	OldValue   string `json:"old_value"`
	NewValue   string `json:"new_value"`
	ChangedBy  string `json:"changed_by"`
	ChangedAt  string `json:"changed_at"`
}

type PricingRuleResponse struct {
	ID            string  `json:"id"`
	RuleType      string  `json:"rule_type"`
	Name          string  `json:"name"`
	Multiplier    float64 `json:"multiplier"`
	FixedAmount   float64 `json:"fixed_amount"`
	AppliesToDays string  `json:"applies_to_days"`
	TimeFrom      string  `json:"time_from"`
	TimeTo        string  `json:"time_to"`
	IsActive      bool    `json:"is_active"`
	CreatedAt     string  `json:"created_at"`
}

type CreatePricingRuleRequest struct {
	RuleType      string  `json:"rule_type" validate:"required,oneof=peak_hour_multiplier weekend_multiplier holiday_surcharge"`
	Name          string  `json:"name" validate:"required"`
	Multiplier    float64 `json:"multiplier"`
	FixedAmount   float64 `json:"fixed_amount"`
	AppliesToDays string  `json:"applies_to_days"`
	TimeFrom      string  `json:"time_from"`
	TimeTo        string  `json:"time_to"`
}

type FeatureFlagResponse struct {
	Key         string `json:"key"`
	Enabled     bool   `json:"enabled"`
	Description string `json:"description"`
	UpdatedAt   string `json:"updated_at"`
}

type UpdateFlagRequest struct {
	Enabled bool `json:"enabled"`
}

type NotificationTemplateResponse struct {
	ID        string `json:"id"`
	Type      string `json:"type"`
	Channel   string `json:"channel"`
	Subject   string `json:"subject"`
	Body      string `json:"body"`
	Variables string `json:"variables"`
	IsActive  bool   `json:"is_active"`
}

type CreateTemplateRequest struct {
	Type      string `json:"type" validate:"required"`
	Channel   string `json:"channel" validate:"required,oneof=sms push email"`
	Subject   string `json:"subject"`
	Body      string `json:"body" validate:"required"`
	Variables string `json:"variables"`
}

type PreviewTemplateRequest struct {
	Values map[string]string `json:"values" validate:"required"`
}

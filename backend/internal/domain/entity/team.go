package entity

import (
	"crypto/rand"
	"fmt"
	"time"

	"github.com/google/uuid"
)

type Team struct {
	ID          uuid.UUID    `gorm:"type:uuid;primaryKey"`
	Name        string       `gorm:"not null"`
	Code        string       `gorm:"uniqueIndex;not null"` // 6-char invite code
	Format      string       `gorm:"not null"`             // e.g. "7 vs 7"
	Formation   string       `gorm:"default:'2-3-1'"`
	CaptainID   uuid.UUID    `gorm:"type:uuid;not null"`
	Captain     *User        `gorm:"foreignKey:CaptainID"`
	MaxPlayers  int          `gorm:"not null"`
	Status      TeamStatus   `gorm:"type:varchar(20);default:'forming'"`
	Members     []TeamMember `gorm:"foreignKey:TeamID"`
	CreatedAt   time.Time
	UpdatedAt   time.Time
	DeletedAt   *time.Time   `gorm:"index"`
}

func (Team) TableName() string { return "teams" }

type TeamMember struct {
	ID        uuid.UUID        `gorm:"type:uuid;primaryKey"`
	TeamID    uuid.UUID        `gorm:"type:uuid;not null;index"`
	UserID    uuid.UUID        `gorm:"type:uuid;not null"`
	User      *User            `gorm:"foreignKey:UserID"`
	Role      TeamMemberRole   `gorm:"type:varchar(20);default:'player'"`
	Position  string           // position on the field
	Number    int
	JoinedAt  time.Time
	CreatedAt time.Time
	UpdatedAt time.Time
}

type TeamStatus string

const (
	TeamStatusForming TeamStatus = "forming"
	TeamStatusReady   TeamStatus = "ready"
	TeamStatusInMatch TeamStatus = "in_match"
)

type TeamMemberRole string

const (
	MemberRoleCaptain TeamMemberRole = "captain"
	MemberRolePlayer  TeamMemberRole = "player"
	MemberRoleSub     TeamMemberRole = "sub"
)

// ChatMessage for team chat (used by WebSocket handler)
type ChatMessage struct {
	ID       uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	TeamID   uuid.UUID `gorm:"column:team_id;index"`
	SenderID uuid.UUID `gorm:"column:sender_id"`
	Content  string    `gorm:"column:content"`
	SentAt   time.Time `gorm:"column:sent_at;autoCreateTime"`

	Sender *User `gorm:"foreignKey:SenderID"`
}

func (ChatMessage) TableName() string { return "chat_messages" }

type MatchChatMessage struct {
	ID       uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	MatchID  uuid.UUID `gorm:"column:match_id;index"`
	SenderID uuid.UUID `gorm:"column:sender_id"`
	Content  string    `gorm:"column:content"`
	SentAt   time.Time `gorm:"column:sent_at;autoCreateTime"`

	Sender *User `gorm:"foreignKey:SenderID"`
}

func (MatchChatMessage) TableName() string { return "match_chat_messages" }

// ─────────────────────────────────────────────────────────────────────────────
// Match — pairs two teams
// ─────────────────────────────────────────────────────────────────────────────
type Match struct {
	ID          uuid.UUID   `gorm:"type:uuid;primaryKey"`
	HomeTeamID  uuid.UUID   `gorm:"type:uuid;not null"`
	HomeTeam    *Team       `gorm:"foreignKey:HomeTeamID"`
	AwayTeamID  *uuid.UUID  `gorm:"type:uuid"`
	AwayTeam    *Team       `gorm:"foreignKey:AwayTeamID"`
	PitchID     *uuid.UUID  `gorm:"type:uuid"`
	Format      string      `gorm:"not null"`
	City        string      `gorm:"not null;default:''"`
	Latitude    float64     `gorm:"not null;default:0"`
	Longitude   float64     `gorm:"not null;default:0"`
	Status      MatchStatus `gorm:"type:varchar(20);default:'searching'"`
	ScheduledAt *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

type MatchStatus string

const (
	MatchSearching MatchStatus = "searching"
	MatchMatched   MatchStatus = "matched"
	MatchConfirmed MatchStatus = "confirmed"
	MatchPlaying   MatchStatus = "playing"
	MatchCompleted MatchStatus = "completed"
	MatchCancelled MatchStatus = "cancelled"
)

func GenerateTeamCode() string {
	b := make([]byte, 3)
	rand.Read(b)
	n := (int(b[0])<<16 | int(b[1])<<8 | int(b[2])) % 1000000
	return fmt.Sprintf("%06d", n)
}

func NewTeam(name, format string, captainID uuid.UUID, maxPlayers int) *Team {
	return &Team{
		ID:         uuid.New(),
		Name:       name,
		Code:       GenerateTeamCode(),
		Format:     format,
		CaptainID:  captainID,
		MaxPlayers: maxPlayers,
		Status:     TeamStatusForming,
	}
}

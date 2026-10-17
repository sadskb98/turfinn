package service

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"html"
	"math"
	"math/big"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"gorm.io/gorm"
)

// normalizeFormat converts format strings like "5 vs 5" to "5v5" for comparison.
func normalizeFormat(f string) string {
	return strings.ReplaceAll(strings.ReplaceAll(f, " vs ", "v"), " ", "")
}

var (
	ErrTournamentNotFound     = errors.New("tournament not found")
	ErrNotTournamentCreator   = errors.New("only the tournament creator can do this")
	ErrTournamentNotOpen      = errors.New("tournament is not open for registration")
	ErrTeamAlreadyRegistered  = errors.New("team is already registered")
	ErrTournamentFull         = errors.New("tournament is full")
	ErrFormatMismatch         = errors.New("team format does not match tournament format")
	ErrInsufficientBalance    = errors.New("insufficient wallet balance for entry fee")
	ErrTeamCoinsInsufficient  = errors.New("team does not meet minimum coins requirement")
	ErrInvalidInviteCode      = errors.New("invalid invite code")
	ErrNotEnoughTeams         = errors.New("need at least 2 teams to start")
	ErrMatchNotFound          = errors.New("tournament match not found")
	ErrNotMatchParticipant    = errors.New("you are not a captain of either team in this match")
	ErrMatchNotReadyToReport  = errors.New("match is not ready for score reporting")
	ErrMatchNotReported       = errors.New("match has not been reported yet")
	ErrCannotConfirmOwnReport = errors.New("the reporting captain cannot confirm their own report")
	ErrMatchAlreadyConfirmed      = errors.New("match result is already confirmed")
	ErrTournamentAlreadyStarted   = errors.New("tournament has already started")
)

type TournamentService struct {
	db        *gorm.DB
	walletSvc *WalletService
}

func NewTournamentService(db *gorm.DB, walletSvc *WalletService) *TournamentService {
	return &TournamentService{db: db, walletSvc: walletSvc}
}

// Create creates a new tournament. If entry_fee > 0, prize_pool = entry_fee * max_teams.
// Generates invite_code for private tournaments. Status starts as registration_open.
func (s *TournamentService) Create(ctx context.Context, userID uuid.UUID, name, description, format, visibility string, maxTeams, entryFee, minCoins int, startsAt *time.Time) (*entity.Tournament, error) {
	name = html.EscapeString(name)
	description = html.EscapeString(description)

	prizePool := 0
	if entryFee > 0 {
		prizePool = entryFee * maxTeams
	}

	var inviteCode *string
	if visibility == "private" {
		code := generateInviteCode()
		inviteCode = &code
	}

	t := entity.Tournament{
		ID:          uuid.New(),
		CreatorID:   userID,
		Name:        name,
		Description: description,
		Format:      format,
		MaxTeams:    maxTeams,
		EntryFee:    entryFee,
		MinCoins:    minCoins,
		PrizePool:   prizePool,
		Visibility:  visibility,
		InviteCode:  inviteCode,
		Status:      entity.TournamentRegistration,
		StartsAt:    startsAt,
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}

	if err := s.db.WithContext(ctx).Create(&t).Error; err != nil {
		return nil, err
	}
	return &t, nil
}

// Get returns a tournament with teams and matches preloaded.
func (s *TournamentService) Get(ctx context.Context, id uuid.UUID) (*entity.Tournament, error) {
	var t entity.Tournament
	err := s.db.WithContext(ctx).
		Preload("Creator").
		Preload("Teams").
		Preload("Teams.Team").
		Preload("Teams.Team.Members").
		Preload("Teams.Team.Members.User").
		Preload("Matches", func(db *gorm.DB) *gorm.DB {
			return db.Order("round ASC, match_order ASC")
		}).
		Preload("Matches.HomeTeam").
		Preload("Matches.AwayTeam").
		Preload("Matches.Winner").
		First(&t, "id = ?", id).Error
	if err != nil {
		return nil, ErrTournamentNotFound
	}
	return &t, nil
}

// List returns public tournaments that are open for registration or in progress.
func (s *TournamentService) List(ctx context.Context, page, limit int) ([]entity.Tournament, int64, error) {
	var total int64
	q := s.db.WithContext(ctx).Model(&entity.Tournament{}).
		Where("visibility = 'public' AND status IN ?", []string{
			string(entity.TournamentRegistration),
			string(entity.TournamentInProgress),
		})

	countQ := q.Session(&gorm.Session{})
	if err := countQ.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var tournaments []entity.Tournament
	if err := q.Preload("Creator").Preload("Teams").
		Order("created_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&tournaments).Error; err != nil {
		return nil, 0, err
	}
	return tournaments, total, nil
}

// Join registers a team into a tournament. Validates captain, status, format, capacity, and entry fee.
func (s *TournamentService) Join(ctx context.Context, userID uuid.UUID, tournamentID, teamID uuid.UUID, inviteCode string) error {
	var t entity.Tournament
	if err := s.db.WithContext(ctx).Preload("Teams").First(&t, "id = ?", tournamentID).Error; err != nil {
		return ErrTournamentNotFound
	}

	if t.Status != entity.TournamentRegistration {
		return ErrTournamentNotOpen
	}

	// Validate invite code for private tournaments
	if t.Visibility == "private" {
		if t.InviteCode == nil || inviteCode != *t.InviteCode {
			return ErrInvalidInviteCode
		}
	}

	// Check user is captain of the team
	var team entity.Team
	if err := s.db.WithContext(ctx).First(&team, "id = ?", teamID).Error; err != nil {
		return ErrTeamNotFound
	}
	if team.CaptainID != userID {
		return ErrNotCaptain
	}

	// Check format matches (normalize "5 vs 5" / "5v5" variants)
	if normalizeFormat(team.Format) != normalizeFormat(t.Format) {
		return ErrFormatMismatch
	}

	// Check team not already registered
	for _, tt := range t.Teams {
		if tt.TeamID == teamID {
			return ErrTeamAlreadyRegistered
		}
	}

	// Check capacity
	if len(t.Teams) >= t.MaxTeams {
		return ErrTournamentFull
	}

	// Check minimum coins requirement — sum of all team members' wallet balances
	if t.MinCoins > 0 {
		var totalCoins int64
		s.db.WithContext(ctx).Table("wallets").
			Joins("JOIN team_members ON team_members.user_id = wallets.user_id").
			Where("team_members.team_id = ?", teamID).
			Select("COALESCE(SUM(wallets.balance), 0)").Scan(&totalCoins)
		if int(totalCoins) < t.MinCoins {
			return ErrTeamCoinsInsufficient
		}
	}

	// Debit entry fee if applicable
	if t.EntryFee > 0 {
		if err := s.walletSvc.DebitCoins(ctx, userID, t.EntryFee, "tournament_entry", fmt.Sprintf("tournament:%s", tournamentID)); err != nil {
			return ErrInsufficientBalance
		}
	}

	tt := entity.TournamentTeam{
		ID:           uuid.New(),
		TournamentID: tournamentID,
		TeamID:       teamID,
		RegisteredAt: time.Now(),
	}
	return s.db.WithContext(ctx).Create(&tt).Error
}

// Cancel lets the creator cancel a tournament that hasn't started yet.
// Refunds entry fees to all registered teams.
func (s *TournamentService) Cancel(ctx context.Context, userID uuid.UUID, tournamentID uuid.UUID) error {
	var t entity.Tournament
	if err := s.db.WithContext(ctx).Preload("Teams").First(&t, "id = ?", tournamentID).Error; err != nil {
		return ErrTournamentNotFound
	}
	if t.CreatorID != userID {
		return ErrNotTournamentCreator
	}
	if t.Status != entity.TournamentRegistration && t.Status != entity.TournamentDraft {
		return ErrTournamentAlreadyStarted
	}

	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Refund entry fees
		if t.EntryFee > 0 {
			for _, tt := range t.Teams {
				var team entity.Team
				if tx.First(&team, "id = ?", tt.TeamID).Error == nil {
					s.walletSvc.CreditCoins(ctx, team.CaptainID, t.EntryFee, "tournament_refund", fmt.Sprintf("tournament:%s", tournamentID))
				}
			}
		}

		return tx.Model(&entity.Tournament{}).Where("id = ?", tournamentID).
			Updates(map[string]any{
				"status":     entity.TournamentCancelled,
				"updated_at": time.Now(),
			}).Error
	})
}

// Leave lets a team captain withdraw their team from a tournament before it starts.
// Refunds entry fee if applicable.
func (s *TournamentService) Leave(ctx context.Context, userID uuid.UUID, tournamentID, teamID uuid.UUID) error {
	var t entity.Tournament
	if err := s.db.WithContext(ctx).First(&t, "id = ?", tournamentID).Error; err != nil {
		return ErrTournamentNotFound
	}
	if t.Status != entity.TournamentRegistration {
		return ErrTournamentAlreadyStarted
	}

	// Verify user is captain of the team
	var team entity.Team
	if err := s.db.WithContext(ctx).First(&team, "id = ?", teamID).Error; err != nil {
		return ErrTeamNotFound
	}
	if team.CaptainID != userID {
		return ErrNotCaptain
	}

	// Remove team from tournament
	result := s.db.WithContext(ctx).Where("tournament_id = ? AND team_id = ?", tournamentID, teamID).Delete(&entity.TournamentTeam{})
	if result.RowsAffected == 0 {
		return ErrTeamNotFound
	}

	// Refund entry fee
	if t.EntryFee > 0 {
		s.walletSvc.CreditCoins(ctx, userID, t.EntryFee, "tournament_refund", fmt.Sprintf("tournament:%s", tournamentID))
	}

	return nil
}

// Start closes registration and generates the bracket. Must have >= 2 teams.
func (s *TournamentService) Start(ctx context.Context, userID uuid.UUID, tournamentID uuid.UUID) error {
	var t entity.Tournament
	if err := s.db.WithContext(ctx).Preload("Teams").First(&t, "id = ?", tournamentID).Error; err != nil {
		return ErrTournamentNotFound
	}
	if t.CreatorID != userID {
		return ErrNotTournamentCreator
	}
	if t.Status != entity.TournamentRegistration {
		return ErrTournamentNotOpen
	}
	if len(t.Teams) < 2 {
		return ErrNotEnoughTeams
	}

	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Shuffle teams
		teams := make([]entity.TournamentTeam, len(t.Teams))
		copy(teams, t.Teams)
		shuffleTeams(teams)

		// Assign seeds
		for i := range teams {
			seed := i + 1
			teams[i].Seed = &seed
			if err := tx.Save(&teams[i]).Error; err != nil {
				return err
			}
		}

		numTeams := len(teams)
		bracketSize := nextPowerOf2(numTeams)
		numByes := bracketSize - numTeams
		totalRounds := int(math.Log2(float64(bracketSize)))

		// Build round 1 matches
		round1Matches := bracketSize / 2
		matchesCreated := make([]entity.TournamentMatch, 0, round1Matches)

		teamIdx := 0
		for i := 0; i < round1Matches; i++ {
			m := entity.TournamentMatch{
				ID:           uuid.New(),
				TournamentID: tournamentID,
				Round:        1,
				MatchOrder:   i,
				CreatedAt:    time.Now(),
			}

			if i < numByes {
				// Bye match: one team auto-advances
				tid := teams[teamIdx].TeamID
				m.HomeTeamID = &tid
				m.Status = entity.TMatchBye
				winnerID := tid
				m.WinnerID = &winnerID
				teamIdx++
			} else {
				// Real match: two teams
				tid1 := teams[teamIdx].TeamID
				m.HomeTeamID = &tid1
				teamIdx++
				tid2 := teams[teamIdx].TeamID
				m.AwayTeamID = &tid2
				m.Status = entity.TMatchReady
				teamIdx++
			}

			if err := tx.Create(&m).Error; err != nil {
				return err
			}
			matchesCreated = append(matchesCreated, m)
		}

		// Create subsequent round match slots
		prevRoundMatches := matchesCreated
		for round := 2; round <= totalRounds; round++ {
			numMatches := len(prevRoundMatches) / 2
			currentRoundMatches := make([]entity.TournamentMatch, 0, numMatches)

			for i := 0; i < numMatches; i++ {
				m := entity.TournamentMatch{
					ID:           uuid.New(),
					TournamentID: tournamentID,
					Round:        round,
					MatchOrder:   i,
					Status:       entity.TMatchPending,
					CreatedAt:    time.Now(),
				}
				if err := tx.Create(&m).Error; err != nil {
					return err
				}
				currentRoundMatches = append(currentRoundMatches, m)
			}

			// Advance byes from previous round into this round
			for i, pm := range prevRoundMatches {
				if pm.Status == entity.TMatchBye && pm.WinnerID != nil {
					nextMatchIdx := i / 2
					if nextMatchIdx < len(currentRoundMatches) {
						nextMatch := &currentRoundMatches[nextMatchIdx]
						if i%2 == 0 {
							nextMatch.HomeTeamID = pm.WinnerID
						} else {
							nextMatch.AwayTeamID = pm.WinnerID
						}
						// Check if both slots are now filled
						if nextMatch.HomeTeamID != nil && nextMatch.AwayTeamID != nil {
							nextMatch.Status = entity.TMatchReady
						}
						if err := tx.Save(nextMatch).Error; err != nil {
							return err
						}
					}
				}
			}

			prevRoundMatches = currentRoundMatches
		}

		// Update tournament status
		return tx.Model(&entity.Tournament{}).Where("id = ?", tournamentID).
			Updates(map[string]interface{}{
				"status":     entity.TournamentInProgress,
				"updated_at": time.Now(),
			}).Error
	})
}

// ReportScore lets a captain of either team report the match result.
func (s *TournamentService) ReportScore(ctx context.Context, userID uuid.UUID, tournamentID, matchID uuid.UUID, homeScore, awayScore int) error {
	var m entity.TournamentMatch
	if err := s.db.WithContext(ctx).First(&m, "id = ? AND tournament_id = ?", matchID, tournamentID).Error; err != nil {
		return ErrMatchNotFound
	}

	if m.Status != entity.TMatchReady {
		return ErrMatchNotReadyToReport
	}

	// Validate that user is captain of one of the teams
	if err := s.validateMatchCaptain(ctx, userID, &m); err != nil {
		return err
	}

	now := time.Now()
	m.HomeScore = &homeScore
	m.AwayScore = &awayScore
	m.ReportedBy = &userID
	m.ReportedAt = &now
	m.Status = entity.TMatchReported

	// Determine winner
	if homeScore > awayScore {
		m.WinnerID = m.HomeTeamID
	} else if awayScore > homeScore {
		m.WinnerID = m.AwayTeamID
	}
	// Draws are left without a winner; the opposing captain can dispute or confirm

	return s.db.WithContext(ctx).Save(&m).Error
}

// ConfirmScore lets the opposing captain confirm the reported result.
func (s *TournamentService) ConfirmScore(ctx context.Context, userID uuid.UUID, tournamentID, matchID uuid.UUID) error {
	var m entity.TournamentMatch
	if err := s.db.WithContext(ctx).First(&m, "id = ? AND tournament_id = ?", matchID, tournamentID).Error; err != nil {
		return ErrMatchNotFound
	}

	if m.Status != entity.TMatchReported {
		return ErrMatchNotReported
	}

	// Validate that user is captain of one of the teams
	if err := s.validateMatchCaptain(ctx, userID, &m); err != nil {
		return err
	}

	// Cannot confirm own report
	if m.ReportedBy != nil && *m.ReportedBy == userID {
		return ErrCannotConfirmOwnReport
	}

	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		m.ConfirmedBy = &userID
		m.ConfirmedAt = &now
		m.Status = entity.TMatchConfirmed

		if err := tx.Save(&m).Error; err != nil {
			return err
		}

		// Mark loser as eliminated
		if m.WinnerID != nil {
			loserID := m.HomeTeamID
			if *m.WinnerID == *m.HomeTeamID {
				loserID = m.AwayTeamID
			}
			if loserID != nil {
				tx.Model(&entity.TournamentTeam{}).
					Where("tournament_id = ? AND team_id = ?", tournamentID, *loserID).
					Update("eliminated", true)
			}
		}

		// Advance winner to next round
		if m.WinnerID != nil {
			if err := advanceWinner(tx, ctx, tournamentID, &m); err != nil {
				return err
			}
		}

		// Check if this was the final match
		return s.checkTournamentComplete(tx, ctx, tournamentID)
	})
}

// DisputeScore lets the opposing captain dispute a reported result.
func (s *TournamentService) DisputeScore(ctx context.Context, userID uuid.UUID, tournamentID, matchID uuid.UUID, reason string) error {
	var m entity.TournamentMatch
	if err := s.db.WithContext(ctx).First(&m, "id = ? AND tournament_id = ?", matchID, tournamentID).Error; err != nil {
		return ErrMatchNotFound
	}

	if m.Status != entity.TMatchReported {
		return ErrMatchNotReported
	}

	// Validate that user is captain of one of the teams
	if err := s.validateMatchCaptain(ctx, userID, &m); err != nil {
		return err
	}

	// Cannot dispute own report
	if m.ReportedBy != nil && *m.ReportedBy == userID {
		return ErrCannotConfirmOwnReport
	}

	reason = html.EscapeString(reason)

	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		m.Status = entity.TMatchDisputed
		if err := tx.Save(&m).Error; err != nil {
			return err
		}

		dispute := entity.TournamentDispute{
			ID:                uuid.New(),
			TournamentMatchID: matchID,
			DisputerID:        userID,
			Reason:            reason,
			Status:            "open",
			CreatedAt:         time.Now(),
		}
		return tx.Create(&dispute).Error
	})
}

// validateMatchCaptain checks that the user is captain of one of the teams in the match.
func (s *TournamentService) validateMatchCaptain(ctx context.Context, userID uuid.UUID, m *entity.TournamentMatch) error {
	isCaptain := false
	if m.HomeTeamID != nil {
		var homeTeam entity.Team
		if err := s.db.WithContext(ctx).First(&homeTeam, "id = ?", *m.HomeTeamID).Error; err == nil {
			if homeTeam.CaptainID == userID {
				isCaptain = true
			}
		}
	}
	if !isCaptain && m.AwayTeamID != nil {
		var awayTeam entity.Team
		if err := s.db.WithContext(ctx).First(&awayTeam, "id = ?", *m.AwayTeamID).Error; err == nil {
			if awayTeam.CaptainID == userID {
				isCaptain = true
			}
		}
	}
	if !isCaptain {
		return ErrNotMatchParticipant
	}
	return nil
}

// advanceWinner places the winner into the next round's match slot.
func advanceWinner(tx *gorm.DB, ctx context.Context, tournamentID uuid.UUID, m *entity.TournamentMatch) error {
	// Find the next round match: match_order 0,1 -> next round match 0; 2,3 -> match 1; etc.
	nextRound := m.Round + 1
	nextMatchOrder := m.MatchOrder / 2

	var nextMatch entity.TournamentMatch
	err := tx.WithContext(ctx).
		Where("tournament_id = ? AND round = ? AND match_order = ?", tournamentID, nextRound, nextMatchOrder).
		First(&nextMatch).Error
	if err != nil {
		// No next round (this was the final) — nothing to do
		return nil
	}

	// Even match_order feeds into home slot, odd into away slot
	if m.MatchOrder%2 == 0 {
		nextMatch.HomeTeamID = m.WinnerID
	} else {
		nextMatch.AwayTeamID = m.WinnerID
	}

	// If both slots filled, mark as ready
	if nextMatch.HomeTeamID != nil && nextMatch.AwayTeamID != nil {
		nextMatch.Status = entity.TMatchReady
	}

	return tx.WithContext(ctx).Save(&nextMatch).Error
}

// checkTournamentComplete checks if the tournament final has been confirmed.
// If so, marks the tournament as completed and distributes the prize pool.
func (s *TournamentService) checkTournamentComplete(tx *gorm.DB, ctx context.Context, tournamentID uuid.UUID) error {
	// Find the highest round
	var maxRound int
	if err := tx.WithContext(ctx).Model(&entity.TournamentMatch{}).
		Where("tournament_id = ?", tournamentID).
		Select("COALESCE(MAX(round), 0)").Scan(&maxRound).Error; err != nil {
		return err
	}
	if maxRound == 0 {
		return nil
	}

	// Check if the final match is confirmed
	var finalMatch entity.TournamentMatch
	if err := tx.WithContext(ctx).
		Where("tournament_id = ? AND round = ? AND match_order = 0", tournamentID, maxRound).
		First(&finalMatch).Error; err != nil {
		return nil
	}

	if finalMatch.Status != entity.TMatchConfirmed || finalMatch.WinnerID == nil {
		return nil
	}

	// Tournament is complete
	if err := tx.Model(&entity.Tournament{}).Where("id = ?", tournamentID).
		Updates(map[string]interface{}{
			"status":     entity.TournamentCompleted,
			"updated_at": time.Now(),
		}).Error; err != nil {
		return err
	}

	// Distribute prize pool to winning team's captain
	var tournament entity.Tournament
	if err := tx.WithContext(ctx).First(&tournament, "id = ?", tournamentID).Error; err != nil {
		return err
	}

	if tournament.PrizePool > 0 {
		var winnerTeam entity.Team
		if err := tx.WithContext(ctx).First(&winnerTeam, "id = ?", *finalMatch.WinnerID).Error; err != nil {
			return err
		}
		// Fire-and-forget prize distribution; use a fresh context since we're inside a tx
		go s.walletSvc.CreditCoins(context.Background(), winnerTeam.CaptainID, tournament.PrizePool, "tournament_prize", fmt.Sprintf("tournament:%s", tournamentID)) //nolint:errcheck
	}

	return nil
}

// ── Helpers ──────────────────────────────────────────────────────────────────

func nextPowerOf2(n int) int {
	if n <= 1 {
		return 1
	}
	p := 1
	for p < n {
		p *= 2
	}
	return p
}

func shuffleTeams(teams []entity.TournamentTeam) {
	for i := len(teams) - 1; i > 0; i-- {
		nBig, err := rand.Int(rand.Reader, big.NewInt(int64(i+1)))
		if err != nil {
			continue
		}
		j := int(nBig.Int64())
		teams[i], teams[j] = teams[j], teams[i]
	}
}

func generateInviteCode() string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	code := make([]byte, 8)
	for i := range code {
		nBig, err := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		if err != nil {
			code[i] = 'X'
			continue
		}
		code[i] = chars[nBig.Int64()]
	}
	return string(code)
}

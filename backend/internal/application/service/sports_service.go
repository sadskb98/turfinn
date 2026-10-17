package service

import (
	"context"
	"fmt"
	"time"

	"github.com/rs/zerolog/log"

	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/infrastructure/sportsapi"
)

// Generic news query for the un-tagged firehose (still useful so the user
// sees content even when the per-league fetches haven't run yet).
const genericNewsQuery = `(football OR cricket) AND (bangladesh OR "world cup" OR premier league OR champions league)`

type SportsService struct {
	newsRepo     domain.NewsRepository
	matchRepo    domain.MatchEventRepository
	standingRepo domain.MatchStandingRepository
	footballAPI  *sportsapi.APIFootballClient
	gnews        *sportsapi.GNewsClient
}

func NewSportsService(
	newsRepo domain.NewsRepository,
	matchRepo domain.MatchEventRepository,
	standingRepo domain.MatchStandingRepository,
	footballAPI *sportsapi.APIFootballClient,
	gnews *sportsapi.GNewsClient,
) *SportsService {
	return &SportsService{
		newsRepo:     newsRepo,
		matchRepo:    matchRepo,
		standingRepo: standingRepo,
		footballAPI:  footballAPI,
		gnews:        gnews,
	}
}

// FetchAndStoreNews pulls articles from GNews — once per followed league
// (tagged with league_id) plus a generic mixed query. Total per cycle:
//
//	len(FollowedLeagues) + 1 GNews calls.
func (s *SportsService) FetchAndStoreNews(ctx context.Context) (int, error) {
	if s.gnews == nil {
		return 0, fmt.Errorf("gnews client not configured")
	}

	all := make([]entity.NewsItem, 0, 80)

	// Generic firehose
	if articles, err := s.gnews.Search(ctx, genericNewsQuery, "en", 10); err != nil {
		log.Warn().Err(err).Msg("gnews generic search failed")
	} else {
		all = append(all, toNewsEntities("gnews", articles, nil)...)
	}

	// Per-league
	for _, l := range sportsapi.FollowedLeagues {
		articles, err := s.gnews.Search(ctx, l.NewsQuery, "en", 10)
		if err != nil {
			log.Warn().Err(err).Int("league_id", l.ID).Msg("gnews league fetch failed")
			continue
		}
		lid := l.ID
		all = append(all, toNewsEntities("gnews", articles, &lid)...)
	}

	return s.newsRepo.UpsertMany(ctx, dedupeNews(all))
}

// FetchAndStoreMatches pulls live + today + tomorrow + per-league fixtures
// and upserts them.
func (s *SportsService) FetchAndStoreMatches(ctx context.Context) (int, error) {
	if s.footballAPI == nil {
		return 0, fmt.Errorf("api-football client not configured")
	}

	now := time.Now().UTC()
	all := make([]entity.MatchEvent, 0, 200)

	if live, err := s.footballAPI.FetchLiveFixtures(ctx); err != nil {
		log.Warn().Err(err).Msg("api-football live fetch failed")
	} else {
		all = append(all, toMatchEntities("api-football", live)...)
	}

	for i := 0; i < 2; i++ {
		date := now.AddDate(0, 0, i)
		if fxs, err := s.footballAPI.FetchFixturesForDate(ctx, date); err != nil {
			log.Warn().Err(err).Int("offset_days", i).Msg("api-football date fetch failed")
		} else {
			all = append(all, toMatchEntities("api-football", fxs)...)
		}
	}

	if fxs, err := s.footballAPI.FetchFollowedLeagueFixtures(ctx, now); err != nil {
		log.Warn().Err(err).Msg("api-football league fetch failed")
	} else {
		all = append(all, toMatchEntities("api-football", fxs)...)
	}

	return s.matchRepo.UpsertMany(ctx, dedupeMatches(all))
}

// PollLiveScores fetches just live fixtures (cheap, focused) and upserts.
// Designed for high-frequency polling (every ~15s) when the paid API-Football
// plan is active. On the free tier, the daily 100-call quota would be burned
// in ~25 minutes — so the caller (worker) gates this with a feature flag.
func (s *SportsService) PollLiveScores(ctx context.Context) (int, error) {
	if s.footballAPI == nil {
		return 0, fmt.Errorf("api-football client not configured")
	}
	live, err := s.footballAPI.FetchLiveFixtures(ctx)
	if err != nil {
		return 0, err
	}
	return s.matchRepo.UpsertMany(ctx, dedupeMatches(toMatchEntities("api-football", live)))
}

// FetchAndStoreStandings refreshes standings for all followed leagues.
// One API-Football call per league (~12/cycle).
func (s *SportsService) FetchAndStoreStandings(ctx context.Context) (int, error) {
	if s.footballAPI == nil {
		return 0, fmt.Errorf("api-football client not configured")
	}
	now := time.Now().UTC()
	count := 0
	for i, l := range sportsapi.FollowedLeagues {
		// Stay under the per-minute rate limit on the free tier (~10 req/min).
		// 7 sec spacing × 12 leagues = ~84 sec for the whole pass.
		if i > 0 {
			select {
			case <-ctx.Done():
				return count, ctx.Err()
			case <-time.After(7 * time.Second):
			}
		}
		season := sportsapi.SeasonForLeague(l, now)
		std, err := s.footballAPI.FetchStandings(ctx, l.ID, season)
		if err != nil {
			log.Warn().Err(err).Int("league_id", l.ID).Msg("standings fetch failed")
			continue
		}
		if std == nil {
			continue
		}
		actualSeason := season
		if std.Season != 0 {
			actualSeason = std.Season
		}
		err = s.standingRepo.Upsert(ctx, &entity.MatchStanding{
			LeagueID:   l.ID,
			Season:     actualSeason,
			LeagueName: std.LeagueName,
			LeagueLogo: std.LeagueLogo,
			Payload:    std.Payload,
		})
		if err != nil {
			log.Warn().Err(err).Int("league_id", l.ID).Msg("standings upsert failed")
			continue
		}
		count++
	}
	return count, nil
}

// EnsureStanding returns a cached standing for (leagueID, season). If missing,
// fetches it on demand. Used by the read endpoint when the cron hasn't yet
// populated the cache for a fresh league.
func (s *SportsService) EnsureStanding(ctx context.Context, leagueID, season int) (*entity.MatchStanding, error) {
	cached, err := s.standingRepo.Get(ctx, leagueID, season)
	if err != nil {
		return nil, err
	}
	if cached != nil {
		return cached, nil
	}
	std, err := s.footballAPI.FetchStandings(ctx, leagueID, season)
	if err != nil {
		return nil, err
	}
	if std == nil {
		return nil, nil
	}
	actualSeason := season
	if std.Season != 0 {
		actualSeason = std.Season
	}
	out := &entity.MatchStanding{
		LeagueID:   leagueID,
		Season:     actualSeason,
		LeagueName: std.LeagueName,
		LeagueLogo: std.LeagueLogo,
		Payload:    std.Payload,
	}
	if err := s.standingRepo.Upsert(ctx, out); err != nil {
		return nil, err
	}
	return out, nil
}

// ── Dedupe ───────────────────────────────────────────────────────────────────

func dedupeMatches(in []entity.MatchEvent) []entity.MatchEvent {
	seen := make(map[string]int, len(in))
	for i, m := range in {
		key := m.Source + ":" + m.SourceID
		seen[key] = i
	}
	out := make([]entity.MatchEvent, 0, len(seen))
	for i, m := range in {
		key := m.Source + ":" + m.SourceID
		if seen[key] == i {
			out = append(out, m)
		}
	}
	return out
}

func dedupeNews(in []entity.NewsItem) []entity.NewsItem {
	// Keep the first occurrence so a league-tagged article wins over a
	// generic-firehose duplicate (both carry the same source_id).
	seen := make(map[string]int, len(in))
	for i, n := range in {
		key := n.Source + ":" + n.SourceID
		if _, ok := seen[key]; !ok {
			seen[key] = i
		}
	}
	out := make([]entity.NewsItem, 0, len(seen))
	for i, n := range in {
		key := n.Source + ":" + n.SourceID
		if seen[key] == i {
			out = append(out, n)
		}
	}
	return out
}

// ── Mappers ──────────────────────────────────────────────────────────────────

func toNewsEntities(source string, arts []sportsapi.NewsArticle, leagueID *int) []entity.NewsItem {
	out := make([]entity.NewsItem, 0, len(arts))
	for _, a := range arts {
		if a.Title == "" || a.URL == "" {
			continue
		}
		out = append(out, entity.NewsItem{
			Source:      source,
			SourceID:    a.SourceID,
			Category:    a.Category,
			LeagueID:    leagueID,
			Title:       a.Title,
			Summary:     a.Summary,
			URL:         a.URL,
			ImageURL:    a.ImageURL,
			SourceName:  a.SourceName,
			PublishedAt: a.PublishedAt,
			Payload:     a.Payload,
		})
	}
	return out
}

func toMatchEntities(source string, fxs []sportsapi.FootballFixture) []entity.MatchEvent {
	out := make([]entity.MatchEvent, 0, len(fxs))
	for _, f := range fxs {
		if f.SourceID == "" || f.HomeTeam == "" || f.AwayTeam == "" {
			continue
		}
		var lid *int
		if f.LeagueID != 0 {
			id := f.LeagueID
			lid = &id
		}
		out = append(out, entity.MatchEvent{
			Source:       source,
			SourceID:     f.SourceID,
			LeagueID:     lid,
			League:       f.League,
			LeagueLogo:   f.LeagueLogo,
			HomeTeam:     f.HomeTeam,
			HomeLogo:     f.HomeLogo,
			AwayTeam:     f.AwayTeam,
			AwayLogo:     f.AwayLogo,
			HomeScore:    f.HomeScore,
			AwayScore:    f.AwayScore,
			KickoffAt:    f.KickoffAt,
			Status:       f.Status,
			MinutePlayed: f.MinutePlayed,
			Payload:      f.Payload,
		})
	}
	return out
}

package handler

import (
	"sort"
	"strconv"
	"time"

	"github.com/labstack/echo/v4"

	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/infrastructure/sportsapi"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"github.com/turfinn/backend/internal/pkg/response"
)

type SportsHandler struct {
	newsRepo  domain.NewsRepository
	matchRepo domain.MatchEventRepository
	svc       *service.SportsService
}

func NewSportsHandler(
	news domain.NewsRepository,
	match domain.MatchEventRepository,
	svc *service.SportsService,
) *SportsHandler {
	return &SportsHandler{newsRepo: news, matchRepo: match, svc: svc}
}

// GET /api/v1/sports/leagues
//
// Static catalog of followed leagues. Used by the Flutter chip row so it
// doesn't have to hardcode the list.
func (h *SportsHandler) ListLeagues(c echo.Context) error {
	out := make([]dto.LeagueResponse, 0, len(sportsapi.FollowedLeagues))
	for _, l := range sportsapi.FollowedLeagues {
		out = append(out, dto.LeagueResponse{
			ID:        l.ID,
			Name:      l.Name,
			ShortName: l.ShortName,
		})
	}
	return response.OK(c, out)
}

// GET /api/v1/sports/news?category=&search=&league_id=&page=&limit=
func (h *SportsHandler) ListNews(c echo.Context) error {
	page, limit := parsePaging(c)
	items, total, err := h.newsRepo.List(c.Request().Context(), domain.NewsFilter{
		Category: c.QueryParam("category"),
		Search:   c.QueryParam("search"),
		LeagueID: parseLeagueID(c),
		Page:     page,
		Limit:    limit,
	})
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.NewsItemResponse, 0, len(items))
	for _, n := range items {
		resp = append(resp, newsItemToDTO(n))
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

// GET /api/v1/sports/matches?status=&league_id=&page=&limit=
func (h *SportsHandler) ListMatches(c echo.Context) error {
	page, limit := parsePaging(c)
	events, total, err := h.matchRepo.List(c.Request().Context(), domain.MatchEventFilter{
		Status:   c.QueryParam("status"),
		LeagueID: parseLeagueID(c),
		Page:     page,
		Limit:    limit,
	})
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.MatchEventResponse, 0, len(events))
	for _, e := range events {
		resp = append(resp, matchEventToDTO(e))
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

// GET /api/v1/sports/feed?league_id=&page=&limit=
//
// Merged chronological view: news + matches sorted by their effective time
// (published_at for news, kickoff_at for matches) descending.
func (h *SportsHandler) ListFeed(c echo.Context) error {
	page, limit := parsePaging(c)
	leagueID := parseLeagueID(c)

	overFetch := limit * 3
	news, _, err := h.newsRepo.List(c.Request().Context(), domain.NewsFilter{
		LeagueID: leagueID,
		Page:     1,
		Limit:    overFetch,
	})
	if err != nil {
		return response.InternalError(c)
	}
	matches, _, err := h.matchRepo.List(c.Request().Context(), domain.MatchEventFilter{
		LeagueID: leagueID,
		Page:     1,
		Limit:    overFetch,
	})
	if err != nil {
		return response.InternalError(c)
	}

	merged := make([]dto.SportsFeedItem, 0, len(news)+len(matches))
	for _, n := range news {
		nn := newsItemToDTO(n)
		merged = append(merged, dto.SportsFeedItem{Kind: "news", News: &nn})
	}
	for _, e := range matches {
		mm := matchEventToDTO(e)
		merged = append(merged, dto.SportsFeedItem{Kind: "match", Match: &mm})
	}

	sort.Slice(merged, func(i, j int) bool {
		return effectiveTime(merged[i]).After(effectiveTime(merged[j]))
	})

	start := (page - 1) * limit
	end := start + limit
	if start > len(merged) {
		start = len(merged)
	}
	if end > len(merged) {
		end = len(merged)
	}
	out := merged[start:end]
	return response.OKPaginated(c, out, response.Meta{
		Page: page, Limit: limit, Total: int64(len(merged)),
	})
}

// GET /api/v1/sports/standings?league_id=39
//
// Returns the cached standings for the league + current season. If the cache
// is empty, fetches on-demand and stores.
func (h *SportsHandler) GetStandings(c echo.Context) error {
	leagueIDPtr := parseLeagueID(c)
	if leagueIDPtr == nil {
		return response.BadRequest(c, "league_id is required")
	}
	leagueID := *leagueIDPtr
	league, ok := sportsapi.LookupLeague(leagueID)
	if !ok {
		return response.BadRequest(c, "league_id not in followed catalog")
	}
	season := sportsapi.SeasonForLeague(league, time.Now().UTC())
	if s := c.QueryParam("season"); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v > 1900 && v < 2100 {
			season = v
		}
	}

	std, err := h.svc.EnsureStanding(c.Request().Context(), leagueID, season)
	if err != nil {
		return response.InternalError(c)
	}
	if std == nil {
		return response.OK(c, dto.StandingsResponse{
			LeagueID:   leagueID,
			Season:     season,
			LeagueName: league.Name,
			Standings:  []byte("[]"),
		})
	}
	return response.OK(c, dto.StandingsResponse{
		LeagueID:   std.LeagueID,
		Season:     std.Season,
		LeagueName: std.LeagueName,
		LeagueLogo: std.LeagueLogo,
		FetchedAt:  std.FetchedAt.Format(time.RFC3339),
		Standings:  std.Payload,
	})
}

// ── Helpers ──────────────────────────────────────────────────────────────────

func parsePaging(c echo.Context) (page, limit int) {
	page, limit = 1, 20
	if p := c.QueryParam("page"); p != "" {
		if v, err := strconv.Atoi(p); err == nil && v > 0 {
			page = v
		}
	}
	if l := c.QueryParam("limit"); l != "" {
		if v, err := strconv.Atoi(l); err == nil && v > 0 && v <= 100 {
			limit = v
		}
	}
	return
}

func parseLeagueID(c echo.Context) *int {
	raw := c.QueryParam("league_id")
	if raw == "" {
		return nil
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return nil
	}
	return &v
}

func newsItemToDTO(n entity.NewsItem) dto.NewsItemResponse {
	return dto.NewsItemResponse{
		ID:          n.ID.String(),
		Source:      n.Source,
		Category:    n.Category,
		LeagueID:    n.LeagueID,
		Title:       n.Title,
		Summary:     n.Summary,
		URL:         n.URL,
		ImageURL:    n.ImageURL,
		SourceName:  n.SourceName,
		PublishedAt: n.PublishedAt.Format(time.RFC3339),
	}
}

func matchEventToDTO(e entity.MatchEvent) dto.MatchEventResponse {
	return dto.MatchEventResponse{
		ID:           e.ID.String(),
		Source:       e.Source,
		LeagueID:     e.LeagueID,
		League:       e.League,
		LeagueLogo:   e.LeagueLogo,
		HomeTeam:     e.HomeTeam,
		HomeLogo:     e.HomeLogo,
		AwayTeam:     e.AwayTeam,
		AwayLogo:     e.AwayLogo,
		HomeScore:    e.HomeScore,
		AwayScore:    e.AwayScore,
		KickoffAt:    e.KickoffAt.Format(time.RFC3339),
		Status:       e.Status,
		MinutePlayed: e.MinutePlayed,
	}
}

func effectiveTime(it dto.SportsFeedItem) time.Time {
	if it.News != nil {
		t, _ := time.Parse(time.RFC3339, it.News.PublishedAt)
		return t
	}
	if it.Match != nil {
		t, _ := time.Parse(time.RFC3339, it.Match.KickoffAt)
		return t
	}
	return time.Time{}
}

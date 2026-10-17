package sportsapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

const apiFootballBaseURL = "https://v3.football.api-sports.io"

type APIFootballClient struct {
	apiKey string
	http   *http.Client
}

func NewAPIFootballClient(apiKey string) *APIFootballClient {
	return &APIFootballClient{
		apiKey: apiKey,
		http:   &http.Client{Timeout: 15 * time.Second},
	}
}

// FootballFixture is the normalized shape we return to the service layer.
type FootballFixture struct {
	SourceID     string
	LeagueID     int
	League       string
	LeagueLogo   string
	HomeTeam     string
	HomeLogo     string
	AwayTeam     string
	AwayLogo     string
	HomeScore    *int
	AwayScore    *int
	KickoffAt    time.Time
	Status       string // 'live','scheduled','finished'
	MinutePlayed *int
	Payload      []byte
}

// FetchFixturesForDate returns fixtures (live + scheduled + finished) for the given date.
func (c *APIFootballClient) FetchFixturesForDate(ctx context.Context, date time.Time) ([]FootballFixture, error) {
	q := fmt.Sprintf("date=%s", date.Format("2006-01-02"))
	return c.fetchFixtures(ctx, q)
}

// FetchLiveFixtures returns currently live fixtures across all leagues.
func (c *APIFootballClient) FetchLiveFixtures(ctx context.Context) ([]FootballFixture, error) {
	return c.fetchFixtures(ctx, "live=all")
}

// FetchFollowedLeagueFixtures returns next-10 fixtures for each followed league
// (uses the season computed per league to handle calendar-year leagues correctly).
func (c *APIFootballClient) FetchFollowedLeagueFixtures(ctx context.Context, now time.Time) ([]FootballFixture, error) {
	var out []FootballFixture
	for _, l := range FollowedLeagues {
		season := SeasonForLeague(l, now)
		q := fmt.Sprintf("league=%d&season=%d&next=10", l.ID, season)
		fxs, err := c.fetchFixtures(ctx, q)
		if err != nil {
			// Soft-fail per league — keep going.
			continue
		}
		out = append(out, fxs...)
	}
	return out, nil
}

func (c *APIFootballClient) fetchFixtures(ctx context.Context, queryString string) ([]FootballFixture, error) {
	url := fmt.Sprintf("%s/fixtures?%s", apiFootballBaseURL, queryString)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("x-apisports-key", c.apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("api-football request: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("api-football status %d: %s", resp.StatusCode, string(body))
	}

	var raw struct {
		Response []struct {
			Fixture struct {
				ID     int    `json:"id"`
				Date   string `json:"date"`
				Status struct {
					Short   string `json:"short"`
					Elapsed *int   `json:"elapsed"`
				} `json:"status"`
			} `json:"fixture"`
			League struct {
				ID   int    `json:"id"`
				Name string `json:"name"`
				Logo string `json:"logo"`
			} `json:"league"`
			Teams struct {
				Home struct {
					Name string `json:"name"`
					Logo string `json:"logo"`
				} `json:"home"`
				Away struct {
					Name string `json:"name"`
					Logo string `json:"logo"`
				} `json:"away"`
			} `json:"teams"`
			Goals struct {
				Home *int `json:"home"`
				Away *int `json:"away"`
			} `json:"goals"`
		} `json:"response"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, fmt.Errorf("api-football decode: %w", err)
	}

	out := make([]FootballFixture, 0, len(raw.Response))
	for _, r := range raw.Response {
		ts, _ := time.Parse(time.RFC3339, r.Fixture.Date)
		status := normalizeStatus(r.Fixture.Status.Short)
		entry, _ := json.Marshal(r)
		out = append(out, FootballFixture{
			SourceID:     strconv.Itoa(r.Fixture.ID),
			LeagueID:     r.League.ID,
			League:       r.League.Name,
			LeagueLogo:   r.League.Logo,
			HomeTeam:     r.Teams.Home.Name,
			HomeLogo:     r.Teams.Home.Logo,
			AwayTeam:     r.Teams.Away.Name,
			AwayLogo:     r.Teams.Away.Logo,
			HomeScore:    r.Goals.Home,
			AwayScore:    r.Goals.Away,
			KickoffAt:    ts,
			Status:       status,
			MinutePlayed: r.Fixture.Status.Elapsed,
			Payload:      entry,
		})
	}
	return out, nil
}

// normalizeStatus collapses API-Football short codes into 3 buckets we care about.
//
// scheduled: TBD, NS, PST, CANC, ABD, AWD, WO
// live:      1H, HT, 2H, ET, BT, P, INT
// finished:  FT, AET, PEN
func normalizeStatus(short string) string {
	switch short {
	case "1H", "HT", "2H", "ET", "BT", "P", "INT", "LIVE":
		return "live"
	case "FT", "AET", "PEN":
		return "finished"
	default:
		return "scheduled"
	}
}

// StandingResponse is the raw league name + logo + payload bytes.
// We pass the raw `response` slice as JSON to the DB so the frontend can render
// any extra fields without us having to model the full schema in Go.
type StandingResponse struct {
	Season     int // populated by FetchStandings — may differ from requested if fallback hit
	LeagueName string
	LeagueLogo string
	Payload    []byte
}

// FetchStandings returns the standings (league table) for a league + season.
//
// If the free-tier plan rejects the requested season, falls back to the most
// recent accessible season (2024). Sleeps between attempts to stay under the
// per-minute rate limit (10 req/min on free tier).
func (c *APIFootballClient) FetchStandings(ctx context.Context, leagueID, season int) (*StandingResponse, error) {
	s, planRestricted, err := c.fetchStandingsOnce(ctx, leagueID, season)
	if err != nil {
		return nil, err
	}
	if s != nil {
		s.Season = season
		return s, nil
	}
	if !planRestricted {
		return nil, nil
	}
	// Free-tier fallback — 7-second wait keeps us under 10 req/min if a
	// caller is iterating leagues back-to-back.
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(7 * time.Second):
	}
	const fallbackSeason = 2024
	s, _, err = c.fetchStandingsOnce(ctx, leagueID, fallbackSeason)
	if err != nil {
		return nil, err
	}
	if s != nil {
		s.Season = fallbackSeason
	}
	return s, nil
}

func (c *APIFootballClient) fetchStandingsOnce(ctx context.Context, leagueID, season int) (*StandingResponse, bool, error) {
	url := fmt.Sprintf("%s/standings?league=%d&season=%d", apiFootballBaseURL, leagueID, season)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("x-apisports-key", c.apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, false, fmt.Errorf("api-football standings request: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return nil, false, fmt.Errorf("api-football standings status %d: %s", resp.StatusCode, string(body))
	}

	var raw struct {
		Errors   any `json:"errors"`
		Response []struct {
			League struct {
				Name      string          `json:"name"`
				Logo      string          `json:"logo"`
				Standings json.RawMessage `json:"standings"`
			} `json:"league"`
		} `json:"response"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, false, fmt.Errorf("api-football standings decode: %w", err)
	}

	if len(raw.Response) > 0 {
		first := raw.Response[0]
		out, _ := json.Marshal(first.League.Standings)
		return &StandingResponse{
			LeagueName: first.League.Name,
			LeagueLogo: first.League.Logo,
			Payload:    out,
		}, false, nil
	}

	// Empty response — distinguish "plan restricted" from genuine no-data so
	// the caller can retry with an older season.
	planRestricted := false
	if errMap, ok := raw.Errors.(map[string]any); ok {
		if _, hasPlan := errMap["plan"]; hasPlan {
			planRestricted = true
		}
	}
	return nil, planRestricted, nil
}

package dto

import "encoding/json"

type NewsItemResponse struct {
	ID          string `json:"id"`
	Source      string `json:"source"`
	Category    string `json:"category,omitempty"`
	LeagueID    *int   `json:"league_id,omitempty"`
	Title       string `json:"title"`
	Summary     string `json:"summary,omitempty"`
	URL         string `json:"url"`
	ImageURL    string `json:"image_url,omitempty"`
	SourceName  string `json:"source_name,omitempty"`
	PublishedAt string `json:"published_at"`
}

type MatchEventResponse struct {
	ID           string `json:"id"`
	Source       string `json:"source"`
	LeagueID     *int   `json:"league_id,omitempty"`
	League       string `json:"league,omitempty"`
	LeagueLogo   string `json:"league_logo,omitempty"`
	HomeTeam     string `json:"home_team"`
	HomeLogo     string `json:"home_logo,omitempty"`
	AwayTeam     string `json:"away_team"`
	AwayLogo     string `json:"away_logo,omitempty"`
	HomeScore    *int   `json:"home_score,omitempty"`
	AwayScore    *int   `json:"away_score,omitempty"`
	KickoffAt    string `json:"kickoff_at"`
	Status       string `json:"status"`
	MinutePlayed *int   `json:"minute_played,omitempty"`
}

type LeagueResponse struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	ShortName string `json:"short_name"`
}

type StandingsResponse struct {
	LeagueID   int             `json:"league_id"`
	Season     int             `json:"season"`
	LeagueName string          `json:"league_name"`
	LeagueLogo string          `json:"league_logo,omitempty"`
	FetchedAt  string          `json:"fetched_at"`
	Standings  json.RawMessage `json:"standings"`
}

// SportsFeedItem is a polymorphic envelope used by the merged feed endpoint.
// `kind` is "news" or "match"; exactly one of `news`/`match` is populated.
type SportsFeedItem struct {
	Kind  string              `json:"kind"`
	News  *NewsItemResponse   `json:"news,omitempty"`
	Match *MatchEventResponse `json:"match,omitempty"`
}

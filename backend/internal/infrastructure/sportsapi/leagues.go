package sportsapi

import "time"

// League is a followed competition. The ID matches API-Football's catalog.
type League struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	ShortName string `json:"short_name"` // for chips
	NewsQuery string `json:"-"`          // GNews search query (kept richer than name)
	// CalendarYearSeason: true means season number == calendar year (Brazil/Argentina/MLS).
	// false means European-style season (Aug–May), where season == start year.
	CalendarYearSeason bool `json:"-"`
}

// FollowedLeagues — keep the order: this is what the chip row will render.
var FollowedLeagues = []League{
	{ID: 39, Name: "Premier League", ShortName: "EPL", NewsQuery: "Premier League football"},
	{ID: 2, Name: "UEFA Champions League", ShortName: "UCL", NewsQuery: "Champions League"},
	{ID: 1, Name: "FIFA World Cup", ShortName: "World Cup", NewsQuery: "FIFA World Cup"},
	{ID: 3, Name: "UEFA Europa League", ShortName: "Europa", NewsQuery: "Europa League"},
	{ID: 848, Name: "UEFA Conference League", ShortName: "Conference", NewsQuery: "Europa Conference League"},
	{ID: 140, Name: "La Liga", ShortName: "La Liga", NewsQuery: "La Liga"},
	{ID: 78, Name: "Bundesliga", ShortName: "Bundesliga", NewsQuery: "Bundesliga"},
	{ID: 135, Name: "Serie A", ShortName: "Serie A", NewsQuery: "Serie A football"},
	{ID: 61, Name: "Ligue 1", ShortName: "Ligue 1", NewsQuery: "Ligue 1 football"},
	{ID: 17, Name: "AFC Asian Cup", ShortName: "Asian Cup", NewsQuery: "AFC Asian Cup"},
	{ID: 332, Name: "Bangladesh Premier League", ShortName: "BPL", NewsQuery: "Bangladesh Premier League football"},
	{ID: 323, Name: "Indian Super League", ShortName: "ISL", NewsQuery: "Indian Super League football"},
}

// SeasonForLeague returns the API-Football season number to query.
//
// European leagues (Aug–May): season is the start year.
// Calendar-year leagues: season is the current calendar year.
func SeasonForLeague(l League, now time.Time) int {
	if l.CalendarYearSeason {
		return now.Year()
	}
	// European-style: Aug–Dec → current year; Jan–Jul → previous year start.
	if int(now.Month()) >= 7 {
		return now.Year()
	}
	return now.Year() - 1
}

// LookupLeague returns the league with the given ID, or false if unknown.
func LookupLeague(id int) (League, bool) {
	for _, l := range FollowedLeagues {
		if l.ID == id {
			return l, true
		}
	}
	return League{}, false
}

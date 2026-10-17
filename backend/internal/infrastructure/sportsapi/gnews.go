package sportsapi

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

const gnewsBaseURL = "https://gnews.io/api/v4"

type GNewsClient struct {
	apiKey string
	http   *http.Client
}

func NewGNewsClient(apiKey string) *GNewsClient {
	return &GNewsClient{
		apiKey: apiKey,
		http:   &http.Client{Timeout: 15 * time.Second},
	}
}

// NewsArticle is the normalized shape returned to the service layer.
type NewsArticle struct {
	SourceID    string // sha1 of url to ensure stable dedupe
	Category    string
	Title       string
	Summary     string
	URL         string
	ImageURL    string
	SourceName  string
	PublishedAt time.Time
	Payload     []byte
}

// Search runs a GNews search query.
//
// `q` is the search query (URL-escaped here). `lang` defaults to "en" when empty.
// `max` capped at 10 by GNews free tier.
func (c *GNewsClient) Search(ctx context.Context, q, lang string, max int) ([]NewsArticle, error) {
	if lang == "" {
		lang = "en"
	}
	if max <= 0 || max > 10 {
		max = 10
	}
	u := fmt.Sprintf("%s/search?q=%s&lang=%s&max=%d&apikey=%s",
		gnewsBaseURL, url.QueryEscape(q), lang, max, url.QueryEscape(c.apiKey))
	return c.fetch(ctx, u, "football")
}

// TopHeadlines hits the sports category top-headlines endpoint.
func (c *GNewsClient) TopHeadlines(ctx context.Context, lang string, max int) ([]NewsArticle, error) {
	if lang == "" {
		lang = "en"
	}
	if max <= 0 || max > 10 {
		max = 10
	}
	u := fmt.Sprintf("%s/top-headlines?category=sports&lang=%s&max=%d&apikey=%s",
		gnewsBaseURL, lang, max, url.QueryEscape(c.apiKey))
	return c.fetch(ctx, u, "sports")
}

func (c *GNewsClient) fetch(ctx context.Context, fullURL, category string) ([]NewsArticle, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", fullURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gnews request: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("gnews status %d: %s", resp.StatusCode, string(body))
	}

	var raw struct {
		Articles []struct {
			Title       string `json:"title"`
			Description string `json:"description"`
			URL         string `json:"url"`
			Image       string `json:"image"`
			PublishedAt string `json:"publishedAt"`
			Source      struct {
				Name string `json:"name"`
			} `json:"source"`
		} `json:"articles"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, fmt.Errorf("gnews decode: %w", err)
	}

	out := make([]NewsArticle, 0, len(raw.Articles))
	for _, a := range raw.Articles {
		ts, _ := time.Parse(time.RFC3339, a.PublishedAt)
		entry, _ := json.Marshal(a)
		sum := sha1.Sum([]byte(a.URL))
		out = append(out, NewsArticle{
			SourceID:    hex.EncodeToString(sum[:]),
			Category:    category,
			Title:       a.Title,
			Summary:     a.Description,
			URL:         a.URL,
			ImageURL:    a.Image,
			SourceName:  a.Source.Name,
			PublishedAt: ts,
			Payload:     entry,
		})
	}
	return out, nil
}

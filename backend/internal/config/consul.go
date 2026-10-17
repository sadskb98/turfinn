package config

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
)

// LoadConsul fetches all keys under CONSUL_PREFIX from Consul KV store
// and sets them as environment variables. Call this before viper.AutomaticEnv().
//
// Required env vars:
//   - CONSUL_URL: e.g., http://consul:8500
//   - CONSUL_TOKEN: ACL token (optional)
//   - CONSUL_PREFIX: key prefix, default "turfinn"
//
// Keys in Consul like "turfinn/db_host" become env var "DB_HOST".
func LoadConsul() {
	consulURL := strings.TrimSpace(os.Getenv("CONSUL_URL"))
	if consulURL == "" {
		return // No Consul configured, use regular env vars
	}

	prefix := os.Getenv("CONSUL_PREFIX")
	if prefix == "" {
		prefix = "turfinn"
	}
	token := os.Getenv("CONSUL_TOKEN")

	client := &http.Client{Timeout: 5 * time.Second}

	// Get all keys under prefix
	keysURL := fmt.Sprintf("%s/v1/kv/%s/?keys", consulURL, prefix)
	req, _ := http.NewRequest("GET", keysURL, nil)
	if token != "" {
		req.Header.Set("X-Consul-Token", token)
	}

	resp, err := client.Do(req)
	if err != nil {
		log.Warn().Err(err).Msg("[Consul] failed to connect")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Warn().Int("status", resp.StatusCode).Msgf("[Consul] no keys found at %s/", prefix)
		return
	}

	var keys []string
	if err := json.NewDecoder(resp.Body).Decode(&keys); err != nil {
		log.Warn().Err(err).Msg("[Consul] failed to decode keys")
		return
	}

	loaded := 0
	for _, key := range keys {
		// Strip prefix: "turfinn/db_host" → "DB_HOST"
		envName := strings.TrimPrefix(key, prefix+"/")
		if envName == "" || strings.HasSuffix(envName, "/") {
			continue // skip folder keys
		}
		envName = strings.ToUpper(envName)

		// Fetch raw value
		valURL := fmt.Sprintf("%s/v1/kv/%s?raw", consulURL, key)
		valReq, _ := http.NewRequest("GET", valURL, nil)
		if token != "" {
			valReq.Header.Set("X-Consul-Token", token)
		}

		valResp, err := client.Do(valReq)
		if err != nil {
			log.Warn().Err(err).Str("key", key).Msg("[Consul] failed to fetch")
			continue
		}

		body, _ := io.ReadAll(valResp.Body)
		valResp.Body.Close()

		os.Setenv(envName, strings.TrimSpace(string(body)))
		loaded++
		log.Debug().Str("key", envName).Msg("[Consul] loaded")
	}

	log.Info().Int("count", loaded).Str("prefix", prefix).Msg("[Consul] config loaded")
}

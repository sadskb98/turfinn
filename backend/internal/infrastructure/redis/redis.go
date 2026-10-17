package redisdb

import (
	"context"
	"fmt"

	"github.com/redis/go-redis/v9"
	"github.com/spf13/viper"
)

func NewRedisClient() (*redis.Client, error) {
	addr := viper.GetString("REDIS_ADDR")
	if addr == "" {
		addr = "localhost:6379"
	}
	client := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: viper.GetString("REDIS_PASSWORD"),
	})
	if err := client.Ping(context.Background()).Err(); err != nil {
		return nil, fmt.Errorf("redis ping failed: %w", err)
	}
	return client, nil
}

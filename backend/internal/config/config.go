package config

import (
	"github.com/spf13/viper"
)

type Config struct {
	AppPort string
	DBHost  string
	DBUser  string
	DBPass  string
	DBName  string
	DBPort  string
	RedisAddr string
	JWTSecret string
	AsynqRedisAddr string
}

func Load() (*Config, error) {
	viper.SetConfigFile(".env")
	viper.AutomaticEnv()
	_ = viper.ReadInConfig() // ok if missing — env vars take precedence

	return &Config{
		AppPort:        viper.GetString("APP_PORT"),
		DBHost:         viper.GetString("DB_HOST"),
		DBUser:         viper.GetString("DB_USER"),
		DBPass:         viper.GetString("DB_PASSWORD"),
		DBName:         viper.GetString("DB_NAME"),
		DBPort:         viper.GetString("DB_PORT"),
		RedisAddr:      viper.GetString("REDIS_ADDR"),
		JWTSecret:      viper.GetString("JWT_SECRET"),
		AsynqRedisAddr: viper.GetString("ASYNQ_REDIS_ADDR"),
	}, nil
}

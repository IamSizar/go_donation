package config

import (
	"fmt"
	"os"
)

type Config struct {
	DatabaseURL string
	HTTPPort    string
	AppEnv      string
}

func Load() (*Config, error) {
	c := &Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		HTTPPort:    getEnvDefault("HTTP_PORT", "8080"),
		AppEnv:      getEnvDefault("APP_ENV", "development"),
	}
	if c.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required (copy backend/.env.example to backend/.env)")
	}
	return c, nil
}

func getEnvDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

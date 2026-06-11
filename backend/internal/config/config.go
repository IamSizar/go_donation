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
	// Railway (and most PaaS) inject the listen port as $PORT. Prefer it; fall
	// back to HTTP_PORT, then 8080 for local dev.
	port := os.Getenv("PORT")
	if port == "" {
		port = getEnvDefault("HTTP_PORT", "8080")
	}
	c := &Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		HTTPPort:    port,
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

// GetEnvDefault is the exported form of getEnvDefault for other packages.
func GetEnvDefault(key, fallback string) string { return getEnvDefault(key, fallback) }

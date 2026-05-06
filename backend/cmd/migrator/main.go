package main

import (
	"context"
	"log"

	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/platform/db"
)

func main() {
	ctx := context.Background()
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	pool, err := db.Connect(ctx, cfg.Database.URL)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	if err := db.RunMigrations(ctx, pool, "migrations"); err != nil {
		log.Fatalf("run migrations: %v", err)
	}

	log.Printf("migrations applied successfully")
}

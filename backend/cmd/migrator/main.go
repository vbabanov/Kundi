package main

import (
	"context"
	"log"

	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/platform/db"
)

func main() {
	ctx := context.Background()
	cfg := config.LoadDatabase()

	pool, err := db.Connect(ctx, cfg.URL)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	if err := db.RunMigrations(ctx, pool, "migrations"); err != nil {
		log.Fatalf("run migrations: %v", err)
	}

	log.Printf("migrations applied successfully")
}

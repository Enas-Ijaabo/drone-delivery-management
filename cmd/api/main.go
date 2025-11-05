package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	iface "github.com/Enas-Ijaabo/drone-delivery-management/internal/interface"
	"github.com/Enas-Ijaabo/drone-delivery-management/internal/repo"
)

func main() {
	fmt.Println("Starting Drone Delivery Management System...")

	cfg := repo.NewDBConfig(
		getenv("DB_HOST", "localhost"),
		getenv("DB_PORT", "3306"),
		getenv("DB_USER", "root"),
		getenv("DB_PASSWORD", ""),
		getenv("DB_NAME", "drone"),
	)

	// Wait for DB and run migrations if needed
	db, err := repo.WaitForDB(cfg, 60, 2*time.Second)
	if err != nil {
		log.Fatalf("database not ready: %v", err)
	}
	defer db.Close()

	if err := repo.MigrateIfEmpty(db, "/migrations/schema.sql"); err != nil {
		log.Fatalf("migration failed: %v", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/health", iface.NewHealthHandler())

	log.Println("Ready. Health: http://0.0.0.0:8080/health")
	log.Fatal(http.ListenAndServe(":8080", mux))
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

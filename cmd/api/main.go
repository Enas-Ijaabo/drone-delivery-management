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

	db, err := repo.WaitForDB(cfg, 60, 2*time.Second)
	if err != nil {
		log.Fatalf("database not ready: %v", err)
	}
	defer db.Close()

	if err := repo.MigrateIfEmpty(db, "/migrations/schema.sql"); err != nil {
		log.Fatalf("migration failed: %v", err)
	}

	// Gin router
	r := iface.NewRouter()

	srv := &http.Server{
		Addr:    ":8080",
		Handler: r,
	}
	log.Println("Ready. Health: http://0.0.0.0:8080/health")
	log.Fatal(srv.ListenAndServe())
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

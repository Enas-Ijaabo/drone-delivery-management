package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	iface "github.com/Enas-Ijaabo/drone-delivery-management/internal/interface"
	"github.com/Enas-Ijaabo/drone-delivery-management/internal/repo"
	"github.com/Enas-Ijaabo/drone-delivery-management/internal/usecase"
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

	// Initialize repositories
	usersRepo := repo.NewUsersRepo(db)

	// Auth config from env
	jwtSecret := []byte(getenv("JWT_SECRET", "dev-secret"))
	jwtTTLStr := getenv("JWT_TTL", "1h")
	jwtTTL, err := time.ParseDuration(jwtTTLStr)
	if err != nil {
		log.Printf("invalid JWT_TTL %q, defaulting to 1h: %v", jwtTTLStr, err)
		jwtTTL = time.Hour
	}
	jwtIssuer := getenv("JWT_ISSUER", "drone-delivery")
	jwtAudience := getenv("JWT_AUDIENCE", "drone-delivery")

	// Initialize usecases
	authUC := usecase.NewAuthUsecase(usersRepo, jwtSecret, jwtTTL, jwtIssuer, jwtAudience)

	// Initialize interfaces/handlers
	authHandler := iface.NewAuthHandler(authUC)

	// Gin router
	r := iface.NewRouter(authHandler)

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

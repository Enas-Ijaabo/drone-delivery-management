// @title Drone Delivery Management API
// @version 1.0.0
// @description REST + WebSocket APIs that power the Drone Delivery Management platform.
// @description
// @description * Authentication: Bearer JWT tokens acquired from `POST /auth/token`.
// @description * Authorization: Role based (enduser, drone, admin) – documented per route.

// @contact.name API Support
// @contact.email
// @license.name
// @license.url
// @host localhost:8080
// @BasePath /
// @schemes http

// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
// @description Type "Bearer" followed by a space and JWT token.

package main

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/Enas-Ijaabo/drone-delivery-management/docs" // Import generated docs
	_ "github.com/go-sql-driver/mysql"
)

func main() {
	fmt.Println("Starting Drone Delivery Management System...")

	cfg := dbConfigFromEnv()

	// Wait for DB and run migrations if needed
	db, err := waitForDB(cfg, 60, 2*time.Second)
	if err != nil {
		log.Fatalf("database not ready: %v", err)
	}
	defer db.Close()

	if err := migrateIfEmpty(db, "/migrations/schema.sql"); err != nil {
		log.Fatalf("migration failed: %v", err)
	}

	// Minimal health endpoint to keep container running
	http.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})
	log.Println("Ready. Health: http://0.0.0.0:8080/health")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

type dbConfig struct {
	host     string
	port     string
	user     string
	password string
	dbname   string
}

func dbConfigFromEnv() dbConfig {
	return dbConfig{
		host:     getenv("DB_HOST", "localhost"),
		port:     getenv("DB_PORT", "3306"),
		user:     getenv("DB_USER", "root"),
		password: getenv("DB_PASSWORD", ""),
		dbname:   getenv("DB_NAME", "drone"),
	}
}

func (c dbConfig) dsn() string {
	// DSN format: user:pass@tcp(host:port)/dbname?params
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&multiStatements=true", c.user, c.password, c.host, c.port, c.dbname)
}

func waitForDB(cfg dbConfig, attempts int, delay time.Duration) (*sql.DB, error) {
	var lastErr error
	for i := 0; i < attempts; i++ {
		db, err := sql.Open("mysql", cfg.dsn())
		if err != nil {
			lastErr = err
			time.Sleep(delay)
			continue
		}
		if err := db.Ping(); err == nil {
			return db, nil
		}
		lastErr = err
		db.Close()
		time.Sleep(delay)
	}
	return nil, fmt.Errorf("db not reachable after %d attempts: %w", attempts, lastErr)
}

func migrateIfEmpty(db *sql.DB, path string) error {
	var count int
	row := db.QueryRow("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")
	if err := row.Scan(&count); err != nil {
		return fmt.Errorf("count tables: %w", err)
	}
	if count > 0 {
		log.Printf("database already has %d tables; skipping migration", count)
		return nil
	}

	sqlBytes, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read migration file: %w", err)
	}
	sqlText := strings.TrimSpace(string(sqlBytes))
	if sqlText == "" {
		return errors.New("migration file is empty; no schema to apply")
	}

	// Execute possibly multiple statements (multiStatements=true in DSN)
	if _, err := db.Exec(sqlText); err != nil {
		return fmt.Errorf("apply schema: %w", err)
	}
	log.Println("schema applied from:", path)
	return nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

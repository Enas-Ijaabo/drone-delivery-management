package repo

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

type DBConfig struct {
	host     string
	port     string
	user     string
	password string
	dbname   string
}

// NewDBConfig constructs a DBConfig; composition root should supply values (e.g., from env).
func NewDBConfig(host, port, user, password, dbname string) DBConfig {
	return DBConfig{host: host, port: port, user: user, password: password, dbname: dbname}
}

func (c DBConfig) dsn() string {
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&multiStatements=true", c.user, c.password, c.host, c.port, c.dbname)
}

func WaitForDB(cfg DBConfig, attempts int, delay time.Duration) (*sql.DB, error) {
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

func MigrateUp(db *sql.DB, migrationsDir string) error {
	entries, err := os.ReadDir(migrationsDir)
	if err != nil {
		return fmt.Errorf("read migrations dir: %w", err)
	}

	var upFiles []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".up.sql") {
			upFiles = append(upFiles, e.Name())
		}
	}
	sort.Strings(upFiles)

	if len(upFiles) == 0 {
		return errors.New("no .up.sql migration files found")
	}

	for _, filename := range upFiles {
		path := filepath.Join(migrationsDir, filename)
		sqlBytes, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read %s: %w", filename, err)
		}
		sqlText := strings.TrimSpace(string(sqlBytes))
		if sqlText == "" {
			log.Printf("skipping empty migration: %s", filename)
			continue
		}
		if _, err := db.Exec(sqlText); err != nil {
			return fmt.Errorf("apply %s: %w", filename, err)
		}
		log.Printf("migration applied: %s", filename)
	}
	return nil
}

func MigrateIfEmpty(db *sql.DB, migrationsDir string) error {
	var count int
	row := db.QueryRow("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")
	if err := row.Scan(&count); err != nil {
		return fmt.Errorf("count tables: %w", err)
	}
	if count > 0 {
		log.Printf("database already has %d tables; skipping migration", count)
		return nil
	}

	log.Println("database is empty; running migrations...")
	return MigrateUp(db, migrationsDir)
}

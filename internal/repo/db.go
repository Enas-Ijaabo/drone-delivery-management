package repo

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"os"
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

func MigrateIfEmpty(db *sql.DB, path string) error {
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

	if _, err := db.Exec(sqlText); err != nil {
		return fmt.Errorf("apply schema: %w", err)
	}
	log.Println("schema applied from:", path)
	return nil
}

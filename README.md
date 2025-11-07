# Drone Delivery Management – Local Dev

## Structure (DDD)
- `cmd/api` – wiring/bootstrap (main)
- `internal/model` – entities, value objects, domain logic
- `internal/usecase` – application services (business flows)
- `internal/interface` – HTTP handlers, middleware, DTOs
- `internal/repo` – repository interfaces + MySQL impl
- `migrations` – SQL schema + seed

## Prerequisites
- Docker Desktop
- Go (optional for other workflows)

## Run with Docker Compose
```bash
docker compose up -d --build
```
- Status: `docker compose ps`
- Logs: `docker compose logs -f app`
- Health: http://localhost:8080/health

## Reset DB and re-apply migrations
```bash
docker compose down -v
docker compose up -d --build
```

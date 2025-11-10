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

## API Documentation (Swagger/OpenAPI)

The API includes comprehensive Swagger/OpenAPI documentation for all endpoints.

### Access Swagger UI
Once the application is running, access the interactive API documentation at:
- **Swagger UI**: http://localhost:8080/swagger/index.html
- **OpenAPI JSON**: http://localhost:8080/swagger/doc.json
- **OpenAPI YAML**: `docs/swagger.yaml`

### Documented Endpoints

| Category | Endpoint | Method | Description |
|----------|----------|--------|-------------|
| **Health** | `/health` | GET | Service health check |
| **Auth** | `/auth/token` | POST | User authentication (returns JWT) |
| **Orders** | `/orders` | POST | Create new delivery order |
| | `/orders/{id}` | GET | Get order details |
| | `/orders/{id}/cancel` | POST | Cancel an order |
| **Drone Actions** | `/drone/orders/{id}/reserve` | POST | Reserve order for delivery |
| | `/drone/orders/{id}/pickup` | POST | Mark order as picked up |
| | `/drone/orders/{id}/deliver` | POST | Mark order as delivered |
| | `/drone/orders/{id}/fail` | POST | Mark order as failed |
| **Admin - Orders** | `/admin/orders` | GET | List all orders (with filters) |
| | `/admin/orders/{id}` | PATCH | Update order route |
| **Admin - Drones** | `/admin/drones` | GET | List all drones |
| | `/admin/drones/{id}/fixed` | POST | Mark drone as fixed |
| **Drones** | `/drone/drones/{id}/broken` | POST | Report drone as broken |
| **WebSocket** | `/drone/heartbeat` | WS | Real-time drone heartbeat & assignments |

### WebSocket Messages

The `/drone/heartbeat` WebSocket endpoint supports the following message types:

**1. Heartbeat (Drone → Server)**
```json
{
  "type": "heartbeat",
  "lat": 40.7128,
  "lng": -74.0060
}
```

**2. Heartbeat Response (Server → Drone)**
```json
{
  "type": "heartbeat",
  "message": "heartbeat received",
  "timestamp": "2025-11-10T12:00:00Z"
}
```

**3. Assignment (Server → Drone)**
```json
{
  "type": "assignment",
  "drone_id": 1,
  "order_id": 123,
  "pickup_lat": 40.7128,
  "pickup_lng": -74.0060,
  "dropoff_lat": 40.7580,
  "dropoff_lng": -73.9855,
  "enduser_id": 456,
  "order_status": "reserved",
  "created_at": "2025-11-10T12:00:00Z"
}
```

**4. Assignment Acknowledgment (Drone → Server)**
```json
{
  "type": "assignment_ack",
  "order_id": 123,
  "status": "accepted"
}
```

### Authentication

Most endpoints require authentication with a Bearer JWT token:

1. **Login to get token:**
```bash
curl -X POST http://localhost:8080/auth/token \
  -H "Content-Type: application/json" \
  -d '{"name": "enduser1", "password": "password123"}'
```

2. **Use token in requests:**
```bash
curl -X GET http://localhost:8080/orders/1 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Regenerate Swagger Docs

If you modify API handlers and need to regenerate documentation:

```bash
make swagger
```

Or manually:
```bash
~/go/bin/swag init -g cmd/api/main.go -o docs
```

## Makefile Commands

The project includes a Makefile with common development tasks:

```bash
make swagger    # Generate Swagger/OpenAPI documentation
make build      # Build the application binary
make run        # Run the application locally
make test       # Run all acceptance tests
make clean      # Clean build artifacts
make deps       # Download Go dependencies
make tools      # Install development tools (swag)
```

## Testing

The project includes comprehensive acceptance tests in the `tests/at/` directory:

```bash
# Run all tests
make test

# Or run manually
cd tests/at && ./api_smoke.sh
```

**Test Coverage:**
- 422 total acceptance tests
- 100% pass rate
- Tests cover all API endpoints, authentication, authorization, state management, and WebSocket functionality

## Default Users (Seeded in Database)

| Username | Password | Role | User ID |
|----------|----------|------|---------|
| `enduser1` | `password123` | enduser | 1 |
| `enduser2` | `password123` | enduser | 2 |
| `drone1` | `password123` | drone | 3 |
| `drone2` | `password123` | drone | 4 |
| `admin1` | `password123` | admin | 5 |

## Technology Stack

- **Language**: Go 1.24
- **Web Framework**: Gin
- **Database**: MySQL 8.0
- **WebSocket**: gorilla/websocket
- **Authentication**: JWT (golang-jwt/jwt)
- **API Documentation**: Swagger/OpenAPI 2.0
- **Containerization**: Docker & Docker Compose

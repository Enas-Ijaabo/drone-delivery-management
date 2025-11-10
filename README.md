# Drone Delivery Management Backend


Authenticated REST + WebSocket API that powers drone deliveries: endusers place/track orders, drones execute them, admins monitor/override. Built with DDD separation (model/usecase/interface/repo), JWT auth, MySQL, polished Swagger docs, and comprehensive tests.

---

## Quick Start

| Action | Command / URL |
|--------|---------------|
| Start stack | `docker compose up -d --build` |
| Health check | http://localhost:8080/health |
| Swagger UI | http://localhost:8080/swagger/index.html |
| OpenAPI spec | http://localhost:8080/swagger/doc.json |
| Logs | `docker compose logs -f app` |
| Tests | `make test` |

Default seeded accounts:

| Role | Username | Password |
|------|----------|----------|
| Enduser | enduser1, enduser2 | password |
| Drone | drone1, drone2 | password |
| Admin | admin | password |

Auth token sample:
```bash
curl -X POST http://localhost:8080/auth/token \
  -H "Content-Type: application/json" \
  -d '{"name":"enduser1","password":"password"}'
```
Use the returned token as `Authorization: Bearer <token>`.

---

## Acceptance Criteria Coverage

| Persona | Requirement | API |
|---------|-------------|-----|
| **Drone** | Reserve job | `POST /orders/{id}/reserve` (drone role) |
| | Grab order (origin / handoff) | `POST /orders/{id}/pickup` |
| | Deliver / fail | `POST /orders/{id}/deliver` / `POST /orders/{id}/fail` |
| | Mark broken (handoff trigger) | `POST /drones/{id}/broken` |
| | Mark fixed | `POST /drones/{id}/fixed` |
| | Heartbeat + location | WebSocket `/ws/heartbeat` (`heartbeat` message) |
| | Receive assignments + ack | WebSocket `assignment` / `assignment_ack` |
| | See current order | `GET /orders/{id}` (requires ownership or assignment) |
| **Enduser** | Submit order | `POST /orders` |
| | Cancel before pickup | `POST /orders/{id}/cancel` |
| | Track progress/location/ETA | `GET /orders/{id}` |
| **Admin** | List orders (filters + pagination) | `GET /admin/orders` |
| | Update origin/destination (pending only) | `PATCH /admin/orders/{id}` |
| | List drones | `GET /admin/drones` |
| | Mark drone broken/fixed | `POST /admin/drones/{id}/broken` / `/fixed` |
---

## Architecture Overview

This project follows **Domain-Driven Design (DDD)** principles with clear separation of concerns:

- **cmd/api** - wiring/bootstrap (inject repos, usecases, handlers)
- **internal/model** - entities (Order, Drone), value objects, domain invariants
- **internal/usecase** - application services (auth, orders, drone ops, scheduler)
- **internal/interface** - HTTP routes (Gin), middleware, DTOs, WebSocket handler
- **internal/repo** - MySQL repos with spatial coordinates + pagination
- **migrations** - schema + seed users
- **tests/at** - acceptance suites (bash + curl + websocket helpers)

The domain layer (`internal/model`) contains business entities and rules, while infrastructure concerns (HTTP, database, WebSocket) are isolated in outer layers. This makes the codebase testable, maintainable, and easy to extend.

Tech stack: Go 1.24, Gin, gorilla/websocket, MySQL 8 (with spatial), JWT (golang-jwt), Docker Compose. Swagger docs generated with `swag`.

---

## Makefile & Tooling

```
make build        # go build ./cmd/api
make run          # go run ./cmd/api
make test         # run acceptance suites in tests/at
make swagger      # regenerate docs (requires swag CLI)
make clean/tools  # housekeeping + install dev tools
```

Swagger artifacts live in `docs/` and are served via `/swagger.yaml` and `/docs`.

---

## Testing

Acceptance tests in `tests/at/` cover:
- Auth (JWT issuance + role enforcement)
- Enduser order lifecycle (create, cancel, track ETA/location)
- Drone workflows (reserve/pickup/deliver/fail, broken/fixed handoff)
- WebSocket heartbeat + assignment flow
- Admin order/drones endpoints (filters, pagination, route updates)

Run all: `make test` (or `cd tests/at && ./api_smoke.sh`).

**CI/CD:** GitHub Actions workflows automatically run all tests on push/PR (see `.github/workflows/`).

---

## WebSocket Reference (`/ws/heartbeat`)

| Direction | Message | Sample |
|-----------|---------|--------|
| Drone -> Server | Heartbeat | `{"type":"heartbeat","lat":31.0,"lng":35.0}` |
| Server -> Drone | Heartbeat ack | `{"type":"heartbeat","message":"ok","timestamp":"..."}` |
| Server -> Drone | Assignment | `{"type":"assignment","order_id":123,"description":"handoff|new_order",...}` |
| Drone -> Server | Assignment ack | `{"type":"assignment_ack","order_id":123,"status":"accepted|declined"}` |

---

## Future Improvements

The current implementation meets the assessment scope; if this became a production service, I would focus next on:

- **Horizontal WebSocket Scaling**: Add Redis Pub/Sub or NATS to route assignment notifications across multiple backend instances
- **Background Assignment Scheduler**: Implement retry logic with exponential backoff for failed assignments
- **Unit & Integration Testing**: Add Go unit tests for domain logic and integration tests with test containers
- **Database Read Replicas**: Split connection pools for read/write operations to scale throughput
- **Observability**: Structured logging with correlation IDs, Prometheus metrics, distributed tracing
- **Operational**: Graceful shutdown for WebSockets, rate limiting, JWT refresh tokens, database migration tooling

---

## Notes for Reviewers

- JWT middleware enforces issuer/audience + role (`RequireRoles(...)`).
- Order route updates locked to `pending` state to protect assignments/ETAs.
- Drone broken workflow updates handoff coordinates, clears assignments, and requeues orders via scheduler.
- Assignment logic uses MySQL spatial indexing (`ST_Distance_Sphere` with `POINT SRID 4326`) to find the nearest idle drone for each order.
- Pagination + filters for admin list endpoints reuse domain helpers (consistent defaults and caps).
- Swagger UI hosted via `/swagger/index.html`; raw spec at `/swagger/doc.json`.

Everything needed to run, inspect, and test the system is above—reach out if any detail would help the review!

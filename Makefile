.PHONY: swagger build run test clean up down logs

# Generate Swagger documentation
swagger:
	@echo "Generating Swagger documentation..."
	$(shell go env GOPATH)/bin/swag init -g cmd/api/main.go -o ./docs --parseDependency --parseInternal
	@echo "Swagger docs generated at ./docs/swagger.json and ./docs/swagger.yaml"

# Build the application (local, without Docker)
build:
	@echo "Building application..."
	go build -o bin/api ./cmd/api

# Run the application (local, without Docker)
run:
	@echo "Running application..."
	go run ./cmd/api

# Docker: Start the stack
up:
	@echo "Starting Docker stack..."
	docker compose up -d --build

# Docker: Stop the stack
down:
	@echo "Stopping Docker stack..."
	docker compose down

# Docker: View logs
logs:
	@echo "Showing Docker logs..."
	docker compose logs -f app

# Run tests
test:
	@echo "Installing acceptance test dependencies..."
	python3 -m pip install --user -r tests/requirements.txt >/dev/null
	@echo "Running pytest acceptance tests..."
	python3 -m pytest

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -rf bin/
	rm -rf docs/docs.go docs/swagger.json docs/swagger.yaml

# Install dependencies
deps:
	@echo "Installing dependencies..."
	go mod download
	go mod tidy

# Install development tools
tools:
	@echo "Installing development tools..."
	go install github.com/swaggo/swag/cmd/swag@latest

# Help
help:
	@echo "Available targets:"
	@echo ""
	@echo "Docker commands (no Go required):"
	@echo "  up       - Start Docker stack (docker compose up -d --build)"
	@echo "  down     - Stop Docker stack (docker compose down)"
	@echo "  logs     - Show Docker logs (docker compose logs -f app)"
	@echo "  test     - Run pytest acceptance tests (requires Python + requests + websocket-client)"
	@echo ""
	@echo "Local development (requires Go 1.24+):"
	@echo "  swagger  - Generate Swagger documentation"
	@echo "  build    - Build application locally (without Docker)"
	@echo "  run      - Run application locally (without Docker)"
	@echo "  deps     - Install Go dependencies"
	@echo "  tools    - Install development tools (swag)"
	@echo ""
	@echo "Other:"
	@echo "  clean    - Clean build artifacts"

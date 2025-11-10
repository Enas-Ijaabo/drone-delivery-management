.PHONY: swagger build run test clean

# Generate Swagger documentation
swagger:
	@echo "Generating Swagger documentation..."
	swag init -g main.go -o ./docs --parseDependency --parseInternal
	@echo "Swagger docs generated at ./docs/swagger.json and ./docs/swagger.yaml"

# Build the application
build:
	@echo "Building application..."
	go build -o bin/api main.go

# Run the application
run:
	@echo "Running application..."
	go run main.go

# Run tests
test:
	@echo "Running tests..."
	cd tests/at && ./api_smoke.sh

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
	@echo "  swagger  - Generate Swagger documentation"
	@echo "  build    - Build the application"
	@echo "  run      - Run the application"
	@echo "  test     - Run acceptance tests"
	@echo "  clean    - Clean build artifacts"
	@echo "  deps     - Install Go dependencies"
	@echo "  tools    - Install development tools (swag)"
	@echo "  help     - Show this help message"

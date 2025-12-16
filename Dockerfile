# Build stage
FROM golang:1.24 AS builder
WORKDIR /app

# Enable Go modules and caching
COPY go.mod .
COPY go.sum .
RUN --mount=type=cache,target=/go/pkg/mod go mod download

# Copy source
COPY . .

# Build API
RUN --mount=type=cache,target=/root/.cache/go-build CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /app/app ./cmd/api

# Acceptance test runner (pytest)
FROM python:3.12-slim AS acceptance-tests
WORKDIR /tests
COPY tests/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY pytest.ini .
COPY tests ./tests
ENV PYTHONUNBUFFERED=1
ENV BASE_URL=http://localhost:8080
CMD ["pytest"]

# Runtime stage
FROM gcr.io/distroless/base-debian12
WORKDIR /app
COPY --from=builder /app/app /app/app
COPY migrations /migrations
COPY docs /app/docs

EXPOSE 8080
ENTRYPOINT ["/app/app"]

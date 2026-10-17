run:
	go run ./cmd/api/...

build:
	go build -o bin/turfinn ./cmd/api/...

tidy:
	go mod tidy

lint:
	golangci-lint run ./...

docker-up:
	docker compose up -d postgres redis

docker-down:
	docker compose down

migrate:
	psql "postgres://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$(DB_NAME)?sslmode=disable" \
		-f migrations/001_initial.sql

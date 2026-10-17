.PHONY: build run stop clean logs

# Build all 3 Flutter web apps + Go backend
build:
	flutter build web --dart-define=API_BASE_URL=/api/v1 -o build/web_app
	flutter build web --target lib/main_manage.dart --dart-define=API_BASE_URL=/api/v1 -o build/web_manage
	flutter build web --target lib/main_superadmin.dart --dart-define=API_BASE_URL=/api/v1 -o build/web_superadmin

# Start everything
run: build
	docker compose up --build -d

# Stop everything
stop:
	docker compose down

# Full reset (wipes DB)
clean:
	docker compose down -v

# Tail logs
logs:
	docker compose logs -f

# Turfinn — Turf Booking & Sports Community Platform

**Turfinn** is a multi-role turf-booking and sports-community platform built around three connected experiences: a player-facing Flutter app, a turf-manager dashboard, and a super-admin console. A Go backend exposes REST APIs and coordinates bookings, teams, match discovery, tournaments, wallets, analytics, and platform administration.

> **Project status:** The repository contains a substantial implementation of the core apps and backend, along with Docker Compose infrastructure and end-to-end tests. Some external integrations are intentionally incomplete or deferred; see [Current limitations](#current-limitations).

## Highlights

### Player experience
- Browse and search turf listings, view details, check available slots, and create bookings.
- Explore nearby turfs on a map, with location preferences, distance/radius controls, and price markers.
- Manage bookings and eligible cancellations.
- Create and join teams, discover matches, and participate in tournaments.
- Use a match feed to create or join posts.
- View player profiles, XP/levels, badges, challenges, leaderboards, referrals, and wallet transaction history.

### Turf-manager dashboard
- Manage turf listings and pitch details, including map-based location selection and service radius.
- Review bookings and support walk-in bookings.
- View revenue and booking analytics, daily ledger and pitch-level financial views.
- Configure smart-pricing rules and manager promo codes.

### Super-admin console
- Administer users, turfs, bookings, teams, matches, and platform configuration.
- Manage marketing tools such as promotions, campaigns, featured turfs, and banners.
- Review KYC applications, disputes, support tickets, and flagged reviews.
- Access business intelligence, financial/audit views, system controls, zones, partners, and turf onboarding.

### Backend and infrastructure
- REST API with role-based authorization.
- Booking validation and time-conflict checks.
- Configurable pricing rules and cancellation policies.
- PostgreSQL persistence, Redis caching/queues, and MinIO object storage.
- Docker Compose setup for local multi-service development.

## Architecture

```text
Flutter Player App ─────────────┐
Flutter Web Manager Dashboard ──┼── Go API (Echo) ── PostgreSQL
Flutter Web Super-admin ────────┘         ├──────── Redis
                                          ├──────── MinIO
                                          └──────── Asynq worker
```

The Flutter codebase has separate entry points for the player app, manager panel, and super-admin panel. The backend is organized into application services, domain entities, repositories, HTTP handlers, and database migrations.

## Technology stack

| Area | Technologies |
|---|---|
| Mobile application | Flutter, Dart |
| Web dashboards | Flutter Web |
| State management | Riverpod, `riverpod_annotation` |
| Navigation and networking | GoRouter, Dio |
| Backend | Go, Echo, GORM |
| Database | PostgreSQL |
| Cache and background jobs | Redis, Asynq |
| Object storage | MinIO (S3-compatible) |
| Maps and geocoding | `flutter_map`, OpenStreetMap-based tiles, Nominatim |
| Containers | Docker Compose |
| End-to-end tests | Playwright |

## Repository layout

```text
.
├── lib/
│   ├── main.dart                 # Player app entry point
│   ├── main_manage.dart          # Turf-manager web panel
│   ├── main_superadmin.dart      # Super-admin web panel
│   ├── core/                     # Shared app/core functionality
│   ├── data/                     # Models, remote sources, providers
│   └── presentation/             # Screens and widgets
├── backend/
│   ├── cmd/api/                  # API entry point
│   ├── cmd/worker/               # Background worker entry point
│   ├── internal/                 # Domain, services, repositories, handlers
│   └── migrations/               # SQL schema migrations
├── e2e/                          # Playwright end-to-end tests
├── docker-compose.yml
├── pubspec.yaml
└── README.md
```

## Run locally with Docker Compose

### Prerequisites

- Docker Engine and Docker Compose
- Git, if cloning the repository

### Start the services

1. Clone the repository and open the project directory.
2. Review the provided environment examples and Docker Compose configuration. Set secure values for secrets before any non-local deployment.
3. Start the stack:

   ```bash
   docker compose up -d --build
   ```

The repository's progress notes document these local service endpoints:

| Service | Local address / port |
|---|---|
| Player web app | `http://localhost:3000` |
| Manager web panel | `http://localhost:3002` |
| Super-admin web panel | `http://localhost:3003` |
| Go API | `http://localhost:8080` |
| API health check | `http://localhost:8080/health` |
| MinIO console | `http://localhost:9001` |

Ports and availability depend on the current Docker Compose configuration and whether the services start successfully.

> **Warning:** The repository includes development-oriented default credentials and secret fallbacks. Do not expose a development deployment publicly without changing secrets, reviewing access controls, and configuring external services securely.

## Run the Flutter app locally

Install a compatible Flutter SDK, then run from the project root:

```bash
flutter pub get
flutter run
```

To build the three web entry points with the API base path used by the Docker setup:

```bash
flutter build web --target lib/main.dart --output build/web_app --dart-define=API_BASE_URL=/api/v1
flutter build web --target lib/main_manage.dart --output build/web_manage --dart-define=API_BASE_URL=/api/v1
flutter build web --target lib/main_superadmin.dart --output build/web_superadmin --dart-define=API_BASE_URL=/api/v1
```

## Run the Go backend locally

The backend uses Go modules. Start the required dependencies (PostgreSQL, Redis, and MinIO), configure the backend environment, and run:

```bash
cd backend
go mod download
go run cmd/api/main.go
```

For the full local stack, Docker Compose is the simpler starting point because it also configures supporting services and the worker.

## Tests and code quality

Useful commands documented in the repository:

```bash
# Backend tests
cd backend && go test ./...

# Flutter static analysis (from project root)
flutter analyze

# Generate code after model/provider changes (from project root)
dart run build_runner build --delete-conflicting-outputs

# End-to-end tests
cd e2e && npx playwright test tests/full-stack-audit.spec.ts --reporter=list
```

The project progress report records a 108-test end-to-end audit. Re-run the tests in your current environment to confirm the present state before relying on that result.

## Current limitations

The repository's progress notes identify the following incomplete or deferred integrations:

- **Payment gateway:** A live bKash/payment-gateway flow is not connected. Wallet top-up functionality is not a completed real-money payment flow, and booking creation does not currently deduct wallet coins.
- **OTP delivery:** OTP generation/storage is implemented for development, but delivery through a live SMS provider is not wired up; development responses may expose an OTP field.
- **Push notifications:** FCM token storage exists, but actual push delivery still requires service-account configuration and worker/provider integration.
- **Social sign-in:** Google Sign-In and Apple Sign-In UI elements are present, but the repository notes that the full mobile OAuth flow is not connected.
- **Offline support and deep links:** The progress notes list offline mode/local caching and deep-link configuration as not implemented.

Treat this list as a snapshot of the repository's project notes; verify each integration against the target deployment before release.

## Security and deployment notes

- Replace all default passwords, JWT secrets, object-storage credentials, and local tokens.
- Configure production CORS, TLS, database access, and service credentials.
- Connect and test real SMS, push-notification, and payment providers before advertising those capabilities as live.
- Review privacy, retention, authorization, and operational monitoring for user, booking, wallet, and identity-verification data.

## Project purpose

Turfinn aims to bring turf discovery and booking together with player coordination and sports-community features, while giving turf operators and platform administrators dedicated tools for operations and oversight.

---

**Maintainer / project contributor:** Shadman Sakib

*This README describes the repository and its documented project status. Feature availability can differ by build and deployment configuration.*

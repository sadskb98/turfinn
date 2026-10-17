#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Turfinn — Build Script
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   ./build.sh              — build everything (all web apps + backend)
#   ./build.sh run          — build everything + start docker compose
#   ./build.sh web          — build all 3 web apps only
#   ./build.sh mobile       — build mobile app (Android APK + iOS if on macOS)
#   ./build.sh android      — build Android APK only
#   ./build.sh ios          — build iOS only (macOS required)
#   ./build.sh backend      — build Go backend only
#   ./build.sh codegen      — run build_runner (freezed/riverpod code gen)
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# API URL for web builds (proxied through nginx in Docker)
WEB_API_URL="${WEB_API_URL:-/api/v1}"

# API URL for mobile builds (point to your server)
MOBILE_API_URL="${MOBILE_API_URL:-http://localhost:8080/api/v1}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[build]${NC} $*"; }
ok()   { echo -e "${GREEN}[done]${NC} $*"; }
fail() { echo -e "${RED}[fail]${NC} $*"; exit 1; }

# ── Code Generation ─────────────────────────────────────────────────────────
build_codegen() {
  log "Running build_runner (freezed + riverpod codegen)..."
  flutter pub get
  dart run build_runner build --delete-conflicting-outputs
  ok "Code generation complete"
}

# ── Web Builds ──────────────────────────────────────────────────────────────
build_web_app() {
  log "Building Player App (web)..."
  flutter build web \
    --dart-define=API_BASE_URL="$WEB_API_URL" \
    -o build/web_app
  ok "Player App → build/web_app/"
}

build_web_manage() {
  log "Building Manager Panel (web)..."
  flutter build web \
    --target lib/main_manage.dart \
    --dart-define=API_BASE_URL="$WEB_API_URL" \
    -o build/web_manage
  ok "Manager Panel → build/web_manage/"
}

build_web_superadmin() {
  log "Building Super Admin Panel (web)..."
  flutter build web \
    --target lib/main_superadmin.dart \
    --dart-define=API_BASE_URL="$WEB_API_URL" \
    -o build/web_superadmin
  ok "Super Admin Panel → build/web_superadmin/"
}

build_all_web() {
  build_web_app
  build_web_manage
  build_web_superadmin
  ok "All 3 web apps built"
}

# ── Mobile Builds ───────────────────────────────────────────────────────────
build_android() {
  log "Building Android APK..."
  flutter build apk \
    --release \
    --dart-define=API_BASE_URL="$MOBILE_API_URL"
  ok "Android APK → build/app/outputs/flutter-apk/app-release.apk"

  log "Building Android App Bundle (for Play Store)..."
  flutter build appbundle \
    --release \
    --dart-define=API_BASE_URL="$MOBILE_API_URL"
  ok "Android AAB → build/app/outputs/bundle/release/app-release.aab"
}

build_ios() {
  if [[ "$(uname)" != "Darwin" ]]; then
    fail "iOS builds require macOS"
  fi
  log "Building iOS..."
  flutter build ios \
    --release \
    --no-codesign \
    --dart-define=API_BASE_URL="$MOBILE_API_URL"
  ok "iOS build → build/ios/iphoneos/Runner.app"
  echo ""
  log "To create an IPA for App Store / TestFlight:"
  log "  1. Open ios/Runner.xcworkspace in Xcode"
  log "  2. Select your signing team"
  log "  3. Product → Archive → Distribute App"
}

build_mobile() {
  build_android
  if [[ "$(uname)" == "Darwin" ]]; then
    build_ios
  else
    log "Skipping iOS (not on macOS)"
  fi
}

# ── Backend Build ───────────────────────────────────────────────────────────
build_backend() {
  log "Building Go backend..."
  cd backend
  go build -o ../build/turfinn-api ./cmd/api
  cd ..
  ok "Backend → build/turfinn-api"
}

# ── Full Build ──────────────────────────────────────────────────────────────
build_all() {
  build_codegen
  build_all_web
  build_backend
  echo ""
  ok "Full build complete. Run './build.sh run' or 'docker compose up --build -d' to start."
}

# ── Build + Run ─────────────────────────────────────────────────────────────
build_and_run() {
  build_all
  log "Starting docker compose..."
  docker compose up --build -d
  echo ""
  ok "All services running:"
  echo "  Player App       http://localhost:3000"
  echo "  Turf Manager     http://localhost:3002"
  echo "  Super Admin      http://localhost:3003"
  echo "  API              http://localhost:8080/health"
  echo "  MinIO Console    http://localhost:9001"
}

# ── Main ────────────────────────────────────────────────────────────────────
case "${1:-all}" in
  all)        build_all ;;
  run)        build_and_run ;;
  web)        build_all_web ;;
  mobile)     build_mobile ;;
  android)    build_android ;;
  ios)        build_ios ;;
  backend)    build_backend ;;
  codegen)    build_codegen ;;
  *)
    echo "Usage: ./build.sh [all|run|web|mobile|android|ios|backend|codegen]"
    exit 1
    ;;
esac

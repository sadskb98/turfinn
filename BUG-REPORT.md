# Turfinn E2E Bug Report

**Date:** 2026-04-17
**Tested by:** Playwright E2E — full-stack-audit.spec.ts
**Environment:** Docker Compose (localhost)
**Scope:** Player App + Turf Manager + Super Admin + Cross-App

**Total bugs found:** 1 — ALL FIXED

---

## ~~HIGH (1)~~

### ~~BUG-1: `POST /manage/pitches` [Manager]~~ — FIXED 2026-04-18

- **Root cause:** `banner_url` column missing from `pitches` table — migration `022_pitch_banner.sql` not applied to running DB
- **Fix:** Applied `ALTER TABLE pitches ADD COLUMN IF NOT EXISTS banner_url TEXT NOT NULL DEFAULT ''` to live DB; migration runs on next `docker compose down -v && up --build`

---

## Summary

| Severity | Count |
|----------|-------|
| HIGH | 0 |
| **Total** | **0** |

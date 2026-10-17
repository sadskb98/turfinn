-- Migration 001: initial schema

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone       VARCHAR(20)  NOT NULL UNIQUE,
    name        VARCHAR(100),
    avatar_url  TEXT,
    role        VARCHAR(20)  NOT NULL DEFAULT 'player',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX idx_users_deleted_at ON users(deleted_at);

CREATE TABLE IF NOT EXISTS pitches (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(150)  NOT NULL,
    description     TEXT,
    address         TEXT          NOT NULL,
    city            VARCHAR(100)  NOT NULL,
    latitude        DOUBLE PRECISION,
    longitude       DOUBLE PRECISION,
    price_per_hour  NUMERIC(10,2) NOT NULL,
    surface         VARCHAR(50),
    capacity        INT,
    image_urls      TEXT,
    owner_id        UUID          NOT NULL REFERENCES users(id),
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pitches_city      ON pitches(city);
CREATE INDEX idx_pitches_owner_id  ON pitches(owner_id);
CREATE INDEX idx_pitches_is_active ON pitches(is_active);

CREATE TABLE IF NOT EXISTS bookings (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pitch_id    UUID          NOT NULL REFERENCES pitches(id),
    user_id     UUID          NOT NULL REFERENCES users(id),
    starts_at   TIMESTAMPTZ   NOT NULL,
    ends_at     TIMESTAMPTZ   NOT NULL,
    total_cost  NUMERIC(10,2) NOT NULL,
    status      VARCHAR(20)   NOT NULL DEFAULT 'pending',
    notes       TEXT,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bookings_pitch_id  ON bookings(pitch_id);
CREATE INDEX idx_bookings_user_id   ON bookings(user_id);
CREATE INDEX idx_bookings_starts_at ON bookings(starts_at);
CREATE INDEX idx_bookings_status    ON bookings(status);

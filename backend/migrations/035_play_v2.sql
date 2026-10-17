-- Play v2: external pitches, join fee economics, reporting + cancellation tracking,
-- DOB for age gate.

-- ── External (non-Turfinn) pitches that users can post matches at. ─────────
-- Sales-conversion lead source: high ref_count = onboard this turf next.
CREATE TABLE IF NOT EXISTS external_pitches (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(160) NOT NULL,
    normalized_name VARCHAR(160) NOT NULL,
    address         TEXT,
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    created_by      UUID REFERENCES users(id),
    ref_count       INT NOT NULL DEFAULT 1,
    verified        BOOLEAN NOT NULL DEFAULT FALSE, -- promoted after 3+ successful matches
    claimed_at      TIMESTAMPTZ, -- non-null = an admin/manager claimed this for onboarding
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Fuzzy-match dedupe: same normalized_name within ~500m collapses to one row.
CREATE INDEX IF NOT EXISTS idx_external_pitches_normalized
    ON external_pitches (normalized_name);
CREATE INDEX IF NOT EXISTS idx_external_pitches_location
    ON external_pitches (latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_external_pitches_ref_count
    ON external_pitches (ref_count DESC);

-- ── Match-post additions for v2 economics + lifecycle. ────────────────────
ALTER TABLE match_posts
    ADD COLUMN IF NOT EXISTS external_pitch_id UUID REFERENCES external_pitches(id),
    ADD COLUMN IF NOT EXISTS join_fee_bdt INT NOT NULL DEFAULT 20,
    ADD COLUMN IF NOT EXISTS per_head_cost_bdt INT, -- player's share of pitch (host fills in)
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ; -- typically match_date + duration

CREATE INDEX IF NOT EXISTS idx_match_posts_expires_at
    ON match_posts (expires_at);

-- ── Reports — anyone can report a post / pitch / host. Auto-suspension at N. ──
CREATE TABLE IF NOT EXISTS match_reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id     UUID NOT NULL REFERENCES users(id),
    match_post_id   UUID NOT NULL REFERENCES match_posts(id) ON DELETE CASCADE,
    target_kind     VARCHAR(20) NOT NULL, -- 'post','venue','host'
    reason          VARCHAR(40) NOT NULL, -- 'unsafe_location','no_show','fake','spam','other'
    note            TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (reporter_id, match_post_id, target_kind)
);

CREATE INDEX IF NOT EXISTS idx_match_reports_post
    ON match_reports (match_post_id);

-- ── Cancellation strikes — host repeats late-cancels = hosting suspension. ──
CREATE TABLE IF NOT EXISTS match_cancellations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id),
    match_post_id   UUID NOT NULL REFERENCES match_posts(id) ON DELETE CASCADE,
    role            VARCHAR(10) NOT NULL, -- 'host','joiner'
    cancelled_at    TIMESTAMPTZ DEFAULT NOW(),
    hours_before    INT NOT NULL, -- how many hours before kickoff
    fee_forfeited   BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_match_cancellations_user
    ON match_cancellations (user_id, cancelled_at DESC);

-- ── Users — DOB for age gate (required for matchmaking 16+). ────────────────
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS dob DATE,
    ADD COLUMN IF NOT EXISTS tos_external_match_accepted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS hosting_suspended_until TIMESTAMPTZ;

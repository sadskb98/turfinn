CREATE TABLE IF NOT EXISTS reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pitch_id UUID NOT NULL REFERENCES pitches(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (booking_id, user_id)  -- one review per booking per user
);
CREATE INDEX IF NOT EXISTS idx_reviews_pitch_id ON reviews(pitch_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);

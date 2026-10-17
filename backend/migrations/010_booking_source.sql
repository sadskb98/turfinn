ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS source         VARCHAR(20)    NOT NULL DEFAULT 'turfinn'
        CHECK (source IN ('turfinn', 'walk_in')),
    ADD COLUMN IF NOT EXISTS payment_method VARCHAR(20)
        CHECK (payment_method IN ('cash', 'card', 'transfer')),
    ADD COLUMN IF NOT EXISTS payment_amount NUMERIC(10,2);

CREATE INDEX IF NOT EXISTS idx_bookings_source ON bookings(source);

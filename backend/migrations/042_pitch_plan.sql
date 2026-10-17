-- Pitch plans + per-source commission. Drives the dual-tier business
-- model: marketplace pitches pay 10% on app-driven bookings + 3% on
-- walk-ins; ERP-only pitches stay out of the player app entirely and
-- pay 3% on their walk-ins for using Turfinn ERP.
--
-- Rates are stored in basis points (bps) so 1000 = 10%, 300 = 3%. Per
-- pitch overrides let high-volume turfs negotiate down.

ALTER TABLE pitches
    ADD COLUMN IF NOT EXISTS plan VARCHAR(20) NOT NULL DEFAULT 'marketplace',
    ADD COLUMN IF NOT EXISTS marketplace_fee_bps INT NOT NULL DEFAULT 1000,
    ADD COLUMN IF NOT EXISTS walkin_fee_bps INT NOT NULL DEFAULT 300;

CREATE INDEX IF NOT EXISTS idx_pitches_plan
    ON pitches(plan);

ALTER TABLE pitches
    ADD CONSTRAINT pitches_plan_check
    CHECK (plan IN ('marketplace', 'erp_only'));

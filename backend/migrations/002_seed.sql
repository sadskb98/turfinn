-- Migration 002: add profile fields + seed data

ALTER TABLE users ADD COLUMN IF NOT EXISTS position VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS skill_level VARCHAR(50);

-- Seed admin user (owner of pitches)
INSERT INTO users (id, phone, name, role, position, skill_level, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  '+8801000000000',
  'Turfinn Admin',
  'admin',
  'Flexible',
  'Pro',
  NOW(), NOW()
) ON CONFLICT (phone) DO NOTHING;

-- Seed pitches
INSERT INTO pitches (id, name, description, address, city, latitude, longitude, price_per_hour, surface, capacity, image_urls, owner_id, is_active, created_at, updated_at)
VALUES
(
  '10000000-0000-0000-0000-000000000001',
  'GreenField Arena',
  'Premium 7v7 turf with floodlights and changing rooms. FIFA quality artificial grass.',
  'House 12, Road 4, Banani', 'Dhaka',
  23.7945, 90.4042, 3000, 'artificial', 14,
  'https://images.unsplash.com/photo-1551958219-acbc630e2914?w=800',
  '00000000-0000-0000-0000-000000000001', true, NOW(), NOW()
),
(
  '10000000-0000-0000-0000-000000000002',
  'Urban Arena — 7v7 Turf',
  'State-of-the-art indoor turf with air conditioning. Perfect for evening matches.',
  'Plot 45, Gulshan 2, Gulshan', 'Dhaka',
  23.7960, 90.4125, 2500, 'futsal', 14,
  'https://images.unsplash.com/photo-1459865264687-595d652de67e?w=800',
  '00000000-0000-0000-0000-000000000001', true, NOW(), NOW()
),
(
  '10000000-0000-0000-0000-000000000003',
  'Dhanmondi Sports Complex',
  'Large 11v11 natural grass pitch. Host of several local tournaments.',
  'Road 27, Dhanmondi', 'Dhaka',
  23.7461, 90.3742, 4000, 'grass', 22,
  'https://images.unsplash.com/photo-1575361204480-aadea25e6e68?w=800',
  '00000000-0000-0000-0000-000000000001', true, NOW(), NOW()
),
(
  '10000000-0000-0000-0000-000000000004',
  'Mirpur Turf Zone',
  'Affordable 5v5 futsal court near BKSP. Great for quick evening sessions.',
  'Section 12, Mirpur', 'Dhaka',
  23.8081, 90.3601, 1500, 'futsal', 10,
  'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=800',
  '00000000-0000-0000-0000-000000000001', true, NOW(), NOW()
),
(
  '10000000-0000-0000-0000-000000000005',
  'Bashundhara Arena',
  'Modern 7v7 turf with spectator seating. Best pitch in Bashundhara area.',
  'Block B, Bashundhara R/A', 'Dhaka',
  23.8179, 90.4330, 3500, 'artificial', 14,
  'https://images.unsplash.com/photo-1553778263-73a83bab9b0c?w=800',
  '00000000-0000-0000-0000-000000000001', true, NOW(), NOW()
),
(
  '10000000-0000-0000-0000-000000000006',
  'Uttara Sports Hub',
  'Budget-friendly 5v5 turf with parking. Open 6 AM to midnight.',
  'Sector 7, Uttara', 'Dhaka',
  23.8759, 90.3795, 1200, 'futsal', 10,
  'https://images.unsplash.com/photo-1556056504-5c7696c4c28d?w=800',
  '00000000-0000-0000-0000-000000000001', true, NOW(), NOW()
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- Migration 009: Branch Working Hours & Saloon Uploads Storage
-- Run this in Supabase Dashboard → SQL Editor. Idempotent.
-- ============================================================

-- 1. Add workingHours JSONB column to Branch table
ALTER TABLE "public"."Branch"
ADD COLUMN IF NOT EXISTS "workingHours" JSONB DEFAULT NULL;

COMMENT ON COLUMN "public"."Branch"."workingHours" IS 'Weekly schedule array (dayOfWeek 0-6) with isOpen, open, close, dayNameAr';

-- 2. Populate default working hours for existing branches if null (1:00 PM to 10:00 PM)
UPDATE "public"."Branch"
SET "workingHours" = '[
  {"dayOfWeek": 6, "dayNameAr": "السبت", "isOpen": true, "open": "13:00", "close": "22:00"},
  {"dayOfWeek": 0, "dayNameAr": "الأحد", "isOpen": true, "open": "13:00", "close": "22:00"},
  {"dayOfWeek": 1, "dayNameAr": "الإثنين", "isOpen": true, "open": "13:00", "close": "22:00"},
  {"dayOfWeek": 2, "dayNameAr": "الثلاثاء", "isOpen": true, "open": "13:00", "close": "22:00"},
  {"dayOfWeek": 3, "dayNameAr": "الأربعاء", "isOpen": true, "open": "13:00", "close": "22:00"},
  {"dayOfWeek": 4, "dayNameAr": "الخميس", "isOpen": true, "open": "13:00", "close": "22:00"},
  {"dayOfWeek": 5, "dayNameAr": "الجمعة", "isOpen": true, "open": "13:00", "close": "22:00"}
]'::jsonb
WHERE "workingHours" IS NULL;

-- 3. Ensure 'saloon_uploads' storage bucket exists and has public read + upload policies
INSERT INTO storage.buckets (id, name, public)
VALUES ('saloon_uploads', 'saloon_uploads', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "saloon_uploads_public_read" ON storage.objects;
DROP POLICY IF EXISTS "saloon_uploads_allow_insert" ON storage.objects;
DROP POLICY IF EXISTS "saloon_uploads_allow_update" ON storage.objects;
DROP POLICY IF EXISTS "saloon_uploads_allow_delete" ON storage.objects;

CREATE POLICY "saloon_uploads_public_read" ON storage.objects FOR
SELECT USING (bucket_id = 'saloon_uploads');

CREATE POLICY "saloon_uploads_allow_insert" ON storage.objects FOR
INSERT WITH CHECK (bucket_id = 'saloon_uploads');

CREATE POLICY "saloon_uploads_allow_update" ON storage.objects FOR
UPDATE USING (bucket_id = 'saloon_uploads');

CREATE POLICY "saloon_uploads_allow_delete" ON storage.objects FOR
DELETE USING (bucket_id = 'saloon_uploads');

-- ====================================================================
-- SALOON DASHBOARD MASTER SCHEMA (Final Production Version)
-- Optimized for Single-Tenant Environment with Autonomous Chat Logic
-- ====================================================================

-- 1. Core Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE EXTENSION IF NOT EXISTS "moddatetime";

-- --------------------------------------------------------
-- Table: Channel (e.g. WhatsApp, Facebook, Instagram configurations)
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."Channel" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "name" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "isActive" BOOLEAN DEFAULT FALSE,
    "credentials" JSONB DEFAULT '[]'::jsonb,
    "variables" JSONB DEFAULT '{}'::jsonb,
    "imageSets" JSONB DEFAULT '[]'::jsonb,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Channel";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Channel" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- --------------------------------------------------------
-- Table: Product (Services/Items)
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."Product" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "name" TEXT NOT NULL,
    "nameAr" TEXT DEFAULT '',
    "description" TEXT DEFAULT '',
    "descriptionAr" TEXT DEFAULT '',
    "price" DOUBLE PRECISION DEFAULT 0,
    "image" TEXT DEFAULT '',
    "isAvailable" BOOLEAN DEFAULT TRUE,
    "category" TEXT DEFAULT '',
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Product";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Product" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- --------------------------------------------------------
-- Table: Booking
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."Booking" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "clientName" TEXT NOT NULL,
    "clientPhone" TEXT DEFAULT '',
    "clientAddress" TEXT DEFAULT '',
    "serviceSummary" TEXT NOT NULL,
    "channelType" TEXT NOT NULL,
    "bookingDate" TIMESTAMPTZ DEFAULT NOW(),
    "status" TEXT DEFAULT 'pending',
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Booking";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Booking" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- --------------------------------------------------------
-- Table: Client (CRM CRM Profiles)
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."Client" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "name" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "address" TEXT DEFAULT '',
    "notes" TEXT DEFAULT '',
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Client";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Client" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- --------------------------------------------------------
-- Table: BlacklistEntry
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."BlacklistEntry" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "identifier" TEXT NOT NULL,
    "identifierType" TEXT DEFAULT 'phone',
    "reason" TEXT DEFAULT '',
    "createdAt" TIMESTAMPTZ DEFAULT NOW()
);

-- --------------------------------------------------------
-- Table: DashboardStat
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."DashboardStat" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "activeChannels" INTEGER DEFAULT 0,
    "totalMessages" INTEGER DEFAULT 0,
    "totalBookings" INTEGER DEFAULT 0,
    "conversionRate" DOUBLE PRECISION DEFAULT 0,
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."DashboardStat";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."DashboardStat" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- ====================================================================
-- CHAT MODULE (Contact & Message with Triggers)
-- ====================================================================

-- --------------------------------------------------------
-- Table: Contact
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."Contact" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "channel_id" UUID REFERENCES "public"."Channel"("id") ON DELETE CASCADE,
    "platform" TEXT NOT NULL,
    "platform_user_id" TEXT NOT NULL,
    "name" TEXT,
    "avatar_url" TEXT,
    "last_interaction_at" TIMESTAMPTZ DEFAULT NOW(),
    "last_message_preview" TEXT,
    "unread_count" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT DEFAULT 'active',
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_contact_per_channel UNIQUE ("channel_id", "platform_user_id")
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Contact";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Contact" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- --------------------------------------------------------
-- Table: Message
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."Message" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "channel_id" UUID REFERENCES "public"."Channel"("id") ON DELETE CASCADE,
    "contact_id" UUID NOT NULL REFERENCES "public"."Contact"("id") ON DELETE CASCADE,
    "message_platform_id" TEXT,
    "sender_type" TEXT NOT NULL CHECK ("sender_type" IN ('user', 'agent', 'bot', 'system')),
    "content_type" TEXT NOT NULL DEFAULT 'text',
    "text_content" TEXT,
    "attachment_url" TEXT,
    "is_read_by_agent" BOOLEAN NOT NULL DEFAULT FALSE,
    "sent_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "platform_timestamp" TIMESTAMPTZ
);

-- --------------------------------------------------------
-- Automated Triggers for Chat Logic
-- --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_contact_summary_on_message()
RETURNS TRIGGER AS $$
DECLARE
    v_contact_id UUID;
BEGIN
    v_contact_id := COALESCE(NEW.contact_id, OLD.contact_id);

    UPDATE public."Contact"
    SET 
        "last_interaction_at" = (SELECT MAX(m.sent_at) FROM public."Message" m WHERE m.contact_id = v_contact_id),
        "last_message_preview" = (
            SELECT CASE 
                WHEN sub.content_type = 'text' THEN LEFT(sub.text_content, 70)
                ELSE '[' || sub.content_type || ']'
            END
            FROM public."Message" sub WHERE sub.contact_id = v_contact_id ORDER BY sub.sent_at DESC LIMIT 1
        ),
        "unread_count" = (
            SELECT COUNT(*) FROM public."Message" m
            WHERE m.contact_id = v_contact_id AND m.sender_type = 'user' AND m.is_read_by_agent = FALSE
        )
    WHERE id = v_contact_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Clear any existing trigger before creating a new one
DROP TRIGGER IF EXISTS messages_summary_trigger ON public."Message";

CREATE TRIGGER messages_summary_trigger
AFTER INSERT OR UPDATE OR DELETE ON public."Message"
FOR EACH ROW EXECUTE FUNCTION public.update_contact_summary_on_message();

-- ====================================================================
-- SECURITY (Row Level Security)
-- ====================================================================
-- Note: RLS is disabled by default. If your Next.js API uses the
-- Service Role key, it will bypass RLS. If you plan to expose the
-- Anon key to the client side, you MUST enable RLS and write policies.

-- ====================================================================
-- SALOON DASHBOARD MIGRATION SCRIPT
-- Transitions the current database to the Unified Client + Message Schema
-- Safely applies updates without deleting existing basic data.
-- ====================================================================

-- 1. CLEANUP PREVIOUS ATTEMPTS
-- This will wipe the broken tables you were struggling with,
-- as well as the old JSONB Conversation table.
DROP TRIGGER IF EXISTS messages_summary_trigger ON public."Message";

DROP FUNCTION IF EXISTS public.update_contact_summary_on_message ();

DROP FUNCTION IF EXISTS public.update_client_summary_on_message ();

DROP TABLE IF EXISTS "public"."Message" CASCADE;

DROP TABLE IF EXISTS "public"."Contact" CASCADE;

DROP TABLE IF EXISTS "public"."Conversation" CASCADE;

-- 2. UPGRADE EXISTING CLIENT TABLE
-- Adds the new chat-related columns to your existing CRM Client table.
ALTER TABLE "public"."Client"
    ADD COLUMN IF NOT EXISTS "channel_id" UUID REFERENCES "public"."Channel"("id") ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS "platform" TEXT DEFAULT 'whatsapp',
    ADD COLUMN IF NOT EXISTS "platform_user_id" TEXT,
    ADD COLUMN IF NOT EXISTS "avatar_url" TEXT,
    ADD COLUMN IF NOT EXISTS "last_interaction_at" TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS "last_message_preview" TEXT,
    ADD COLUMN IF NOT EXISTS "unread_count" INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS "status" TEXT DEFAULT 'active';

-- Add unique constraint for platform routing, wrapping it to prevent "already exists" errors
DO $$ 
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'unique_client_per_channel'
  ) THEN
      ALTER TABLE "public"."Client" ADD CONSTRAINT unique_client_per_channel UNIQUE ("channel_id", "platform_user_id");
  END IF;
END $$;

-- 3. RECREATE MESSAGE TABLE
-- Properly referencing the newly unified Client table.
CREATE TABLE "public"."Message" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "channel_id" UUID REFERENCES "public"."Channel"("id") ON DELETE CASCADE,
    "client_id" UUID NOT NULL REFERENCES "public"."Client"("id") ON DELETE CASCADE,
    "message_platform_id" TEXT,
    "sender_type" TEXT NOT NULL CHECK ("sender_type" IN ('user', 'agent', 'bot', 'system')),
    "content_type" TEXT NOT NULL DEFAULT 'text',
    "text_content" TEXT,
    "attachment_url" TEXT,
    "is_read_by_agent" BOOLEAN NOT NULL DEFAULT FALSE,
    "sent_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "platform_timestamp" TIMESTAMPTZ
);

-- 4. INSTALL UNIFIED TRIGGER
-- Calculates unread counts directly onto the Client row.
CREATE OR REPLACE FUNCTION public.update_client_summary_on_message()
RETURNS TRIGGER AS $$
DECLARE
    v_client_id UUID;
BEGIN
    v_client_id := COALESCE(NEW.client_id, OLD.client_id);

    UPDATE public."Client"
    SET 
        "last_interaction_at" = (SELECT MAX(m.sent_at) FROM public."Message" m WHERE m.client_id = v_client_id),
        "last_message_preview" = (
            SELECT CASE 
                WHEN sub.content_type = 'text' THEN LEFT(sub.text_content, 70)
                ELSE '[' || sub.content_type || ']'
            END
            FROM public."Message" sub WHERE sub.client_id = v_client_id ORDER BY sub.sent_at DESC LIMIT 1
        ),
        "unread_count" = (
            SELECT COUNT(*) FROM public."Message" m
            WHERE m.client_id = v_client_id AND m.sender_type = 'user' AND m.is_read_by_agent = FALSE
        )
    WHERE id = v_client_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER messages_summary_trigger
AFTER INSERT OR UPDATE OR DELETE ON public."Message"
FOR EACH ROW EXECUTE FUNCTION public.update_client_summary_on_message();

-- ====================================================================
-- SALOON DASHBOARD MIGRATION SCRIPT
-- Transitions from Blacklist table to ai_enabled Client column
-- ====================================================================

-- 1. Add ai_enabled to Client
ALTER TABLE "public"."Client"
    ADD COLUMN IF NOT EXISTS "ai_enabled" BOOLEAN NOT NULL DEFAULT TRUE;

-- 2. Drop the old BlacklistEntry table
DROP TABLE IF EXISTS "public"."BlacklistEntry" CASCADE;

-- Migration to Link Bookings to Clients

-- 1. Wipe existing bookings (safe for dev) to avoid constraint violations
TRUNCATE TABLE "public"."Booking";

-- 2. Modify the Booking table
ALTER TABLE "public"."Booking" 
  DROP COLUMN IF EXISTS "clientName",
  DROP COLUMN IF EXISTS "clientPhone",
  DROP COLUMN IF EXISTS "clientAddress",
  ADD COLUMN IF NOT EXISTS "client_id" UUID NOT NULL REFERENCES "public"."Client"("id") ON DELETE CASCADE;

-- Migration to Link Bookings to Clients

-- 1. Wipe existing bookings (safe for dev) to avoid constraint violations
TRUNCATE TABLE "public"."Booking";

-- 2. Modify the Booking table
ALTER TABLE "public"."Booking" 
  DROP COLUMN IF EXISTS "clientName",
  DROP COLUMN IF EXISTS "clientPhone",
  DROP COLUMN IF EXISTS "clientAddress",
  ADD COLUMN IF NOT EXISTS "client_id" UUID NOT NULL REFERENCES "public"."Client"("id") ON DELETE CASCADE;

-- 3. Make Client name nullable
ALTER TABLE "public"."Client" ALTER COLUMN "name" DROP NOT NULL;

-- Migration: Products Overhaul, Settings, Roles, and Storage

-- ====================================================================
-- 1. Product Table Overhaul
-- ====================================================================
-- Note: We assume it's safe to drop the old English columns in this development phase.
-- We rename the Arabic ones to be the primary ones.

ALTER TABLE "public"."Product"
  DROP COLUMN IF EXISTS "name",
  DROP COLUMN IF EXISTS "description";

ALTER TABLE "public"."Product" RENAME COLUMN "nameAr" TO "name";

ALTER TABLE "public"."Product"
  RENAME COLUMN "descriptionAr" TO "description";

-- Change image from TEXT to JSONB to store an array of URLs
ALTER TABLE "public"."Product"
  DROP COLUMN IF EXISTS "image",
  ADD COLUMN IF NOT EXISTS "images" JSONB DEFAULT '[]'::jsonb;

-- Ensure name is NOT NULL now that it is the primary name
-- First we update any nulls to empty string
UPDATE "public"."Product" SET "name" = '' WHERE "name" IS NULL;

ALTER TABLE "public"."Product" ALTER COLUMN "name" SET NOT NULL;

-- ====================================================================
-- 2. System Settings Table
-- ====================================================================
CREATE TABLE IF NOT EXISTS "public"."SystemSetting" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "key" TEXT UNIQUE NOT NULL,
    "value" TEXT,
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at_settings ON "public"."SystemSetting";

CREATE TRIGGER handle_updated_at_settings BEFORE UPDATE ON "public"."SystemSetting" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- Insert default values
INSERT INTO "public"."SystemSetting" ("key", "value") VALUES 
  ('salon_address', ''),
  ('order_notification_whatsapp', '')
ON CONFLICT ("key") DO NOTHING;

-- ====================================================================
-- 3. App User Role Table
-- ====================================================================
CREATE TABLE IF NOT EXISTS "public"."AppUserRole" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "user_id" UUID UNIQUE, -- Can map to auth.users.id later
    "name" TEXT NOT NULL,
    "email" TEXT UNIQUE NOT NULL,
    "role" TEXT NOT NULL CHECK ("role" IN ('admin', 'team')),
    "permissions" JSONB DEFAULT '[]'::jsonb,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at_roles ON "public"."AppUserRole";

CREATE TRIGGER handle_updated_at_roles BEFORE UPDATE ON "public"."AppUserRole" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- ====================================================================
-- 4. Supabase Storage Bucket Setup
-- ====================================================================
-- Create the storage bucket
INSERT INTO
    storage.buckets (id, name, public)
VALUES (
        'saloon_uploads',
        'saloon_uploads',
        true
    ) ON CONFLICT (id) DO NOTHING;

-- Storage RLS Policies
-- Allow public access to read files
CREATE POLICY "Public Access" ON storage.objects FOR
SELECT USING (bucket_id = 'saloon_uploads');
-- Allow all authenticated users (or anon for this dev scope) to upload
CREATE POLICY "Upload Access" ON storage.objects FOR
INSERT
WITH
    CHECK (bucket_id = 'saloon_uploads');

CREATE POLICY "Delete Access" ON storage.objects FOR DELETE USING (bucket_id = 'saloon_uploads');

CREATE POLICY "Update Access" ON storage.objects FOR
UPDATE USING (bucket_id = 'saloon_uploads');

ALTER TABLE "public"."Product"
ADD COLUMN IF NOT EXISTS "notes" TEXT DEFAULT '';

ALTER TABLE "public"."Product" ADD COLUMN IF NOT EXISTS "notes" TEXT DEFAULT '';

-- Add webhookUrl to Channel table
ALTER TABLE "public"."Channel" ADD COLUMN IF NOT EXISTS "webhookUrl" TEXT DEFAULT '';

-- Category table for product/service classification
CREATE TABLE IF NOT EXISTS "public"."Category" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "label" TEXT NOT NULL,
    "color" TEXT DEFAULT 'sage',
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Category";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Category"
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- RLS policies
ALTER TABLE "public"."Category" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow service_role full access" ON "public"."Category" FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Allow anon read" ON "public"."Category" FOR SELECT TO anon USING (true);

CREATE POLICY "Allow anon write" ON "public"."Category" FOR ALL TO anon USING (true) WITH CHECK (true);

-- Migration: Change price to TEXT and add location options
ALTER TABLE "public"."Product" 
ALTER COLUMN "price" TYPE TEXT USING "price"::TEXT;

ALTER TABLE "public"."Product" ALTER COLUMN "price" SET DEFAULT '';

ALTER TABLE "public"."Product"
ADD COLUMN "availableAtHome" BOOLEAN DEFAULT FALSE,
ADD COLUMN "availableAtSalon" BOOLEAN DEFAULT TRUE;

-- Migration: Enable Supabase Realtime for Message and Client tables
-- Run this in Supabase SQL Editor

-- Add tables to the realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE "public"."Message";

ALTER PUBLICATION supabase_realtime ADD TABLE "public"."Client";

-- 2. Set REPLICA IDENTITY FULL so UPDATE events include all columns
ALTER TABLE "public"."Message" REPLICA IDENTITY FULL;

ALTER TABLE "public"."Client" REPLICA IDENTITY FULL;

-- 3. Enable RLS on both tables (required for Realtime to work with anon key)
ALTER TABLE "public"."Message" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."Client" ENABLE ROW LEVEL SECURITY;

-- 4. Create permissive SELECT policies for the anon role
--    (Realtime needs SELECT permission to broadcast changes)
CREATE POLICY "Allow anon select on Message" ON "public"."Message"
  FOR SELECT TO anon USING (true);

CREATE POLICY "Allow anon select on Client" ON "public"."Client"
  FOR SELECT TO anon USING (true);

-- 5. Allow service_role full access (used by API routes)
CREATE POLICY "Allow service_role full access on Message" ON "public"."Message"
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Allow service_role full access on Client" ON "public"."Client"
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- 6. Allow anon full CRUD (for dashboard operations via anon key)
CREATE POLICY "Allow anon insert on Message" ON "public"."Message"
  FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "Allow anon update on Message" ON "public"."Message"
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY "Allow anon delete on Message" ON "public"."Message"
  FOR DELETE TO anon USING (true);

CREATE POLICY "Allow anon insert on Client" ON "public"."Client"
  FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "Allow anon update on Client" ON "public"."Client"
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY "Allow anon delete on Client" ON "public"."Client"
  FOR DELETE TO anon USING (true);

-- Migration: Add sortOrder column to Product table for manual ordering
-- Run this in Supabase SQL Editor

ALTER TABLE "public"."Product"
ADD COLUMN IF NOT EXISTS "sortOrder" INTEGER DEFAULT 0;

-- Initialize sortOrder based on current createdAt order (newest = highest number)
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY "createdAt" ASC) AS rn
  FROM "public"."Product"
)
UPDATE "public"."Product" p
SET "sortOrder" = r.rn
FROM ranked r
WHERE p.id = r.id;

-- ====================================================================
-- GARDENIA SALON — PLATFORM UPGRADE MIGRATION (v2)
-- Run this in Supabase SQL Editor
-- ====================================================================

-- ====================================================================
-- 1. STAFF TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS "public"."Staff" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "name" TEXT NOT NULL,
    "phone" TEXT DEFAULT '',
    "role" TEXT DEFAULT 'stylist',
    "avatar" TEXT DEFAULT '',
    "isActive" BOOLEAN DEFAULT TRUE,
    "services" JSONB DEFAULT '[]'::jsonb,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Staff";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Staff"
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- ====================================================================
-- 2. STAFF SCHEDULE TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS "public"."StaffSchedule" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "staff_id" UUID NOT NULL REFERENCES "public"."Staff"("id") ON DELETE CASCADE,
    "dayOfWeek" INTEGER NOT NULL CHECK ("dayOfWeek" BETWEEN 0 AND 6),
    "startTime" TIME NOT NULL DEFAULT '09:00',
    "endTime" TIME NOT NULL DEFAULT '18:00',
    "isOff" BOOLEAN DEFAULT FALSE,
    UNIQUE("staff_id", "dayOfWeek")
);

-- ====================================================================
-- 3. LINK BOOKINGS TO STAFF
-- ====================================================================
ALTER TABLE "public"."Booking"
    ADD COLUMN IF NOT EXISTS "staff_id" UUID REFERENCES "public"."Staff"("id") ON DELETE SET NULL;

-- ====================================================================
-- 4. OFFER TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS "public"."Offer" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "product_id" UUID NOT NULL REFERENCES "public"."Product"("id") ON DELETE CASCADE,
    "discountType" TEXT NOT NULL CHECK ("discountType" IN ('percentage', 'fixed')),
    "discountValue" DOUBLE PRECISION NOT NULL,
    "startDate" TIMESTAMPTZ,
    "endDate" TIMESTAMPTZ,
    "isActive" BOOLEAN DEFAULT TRUE,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Offer";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Offer"
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- ====================================================================
-- 5. PRODUCT STOCK COLUMN
-- ====================================================================
ALTER TABLE "public"."Product"
    ADD COLUMN IF NOT EXISTS "stock" INTEGER DEFAULT NULL;

-- ====================================================================
-- 6. CLIENT ENHANCEMENTS
-- ====================================================================
ALTER TABLE "public"."Client"
    ADD COLUMN IF NOT EXISTS "tags" JSONB DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS "email" TEXT DEFAULT '';

-- ====================================================================
-- 7. GALLERY TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS "public"."Gallery" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "title" TEXT DEFAULT '',
    "imageUrl" TEXT NOT NULL,
    "category" TEXT DEFAULT '',
    "sortOrder" INTEGER DEFAULT 0,
    "createdAt" TIMESTAMPTZ DEFAULT NOW()
);

-- ====================================================================
-- 8. ORDER TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS "public"."Order" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "orderCode" TEXT NOT NULL UNIQUE DEFAULT '',
    "client_id" UUID REFERENCES "public"."Client"("id") ON DELETE SET NULL,
    "customerName" TEXT NOT NULL,
    "customerPhone" TEXT NOT NULL,
    "customerAddress" TEXT DEFAULT '',
    "items" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "subtotal" DOUBLE PRECISION DEFAULT 0,
    "deliveryFee" DOUBLE PRECISION DEFAULT 0,
    "total" DOUBLE PRECISION DEFAULT 0,
    "status" TEXT DEFAULT 'pending' CHECK ("status" IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled')),
    "paymentMethod" TEXT DEFAULT 'cash',
    "paymentStatus" TEXT DEFAULT 'unpaid' CHECK ("paymentStatus" IN ('unpaid', 'paid', 'refunded')),
    "notes" TEXT DEFAULT '',
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Order";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Order"
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- Auto-generate order code
CREATE OR REPLACE FUNCTION generate_order_code()
RETURNS TRIGGER AS $$
DECLARE
    today_count INTEGER;
    today_str TEXT;
BEGIN
    today_str := TO_CHAR(NOW(), 'YYYYMMDD');
    SELECT COUNT(*) + 1 INTO today_count FROM "public"."Order"
    WHERE "createdAt"::date = CURRENT_DATE;
    NEW."orderCode" := 'GRD-' || today_str || '-' || LPAD(today_count::TEXT, 3, '0');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_order_code ON "public"."Order";

CREATE TRIGGER set_order_code
BEFORE INSERT ON "public"."Order"
FOR EACH ROW EXECUTE FUNCTION generate_order_code();

-- ====================================================================
-- 9. CMS PAGES TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS "public"."CmsPage" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "slug" TEXT UNIQUE NOT NULL,
    "title" TEXT NOT NULL,
    "content" TEXT DEFAULT '',
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."CmsPage";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."CmsPage"
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

INSERT INTO "public"."CmsPage" ("slug", "title", "content") VALUES
    ('about', 'من نحن', ''),
    ('contact', 'تواصلي معنا', ''),
    ('privacy', 'سياسة الخصوصية', ''),
    ('terms', 'الشروط والأحكام', ''),
    ('booking-conditions', 'شروط الحجز', '')
ON CONFLICT ("slug") DO NOTHING;

-- ====================================================================
-- 10. ROW LEVEL SECURITY FOR ALL NEW TABLES
-- ====================================================================

-- Staff
ALTER TABLE "public"."Staff" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon full access on Staff" ON "public"."Staff" FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "Allow service_role full access on Staff" ON "public"."Staff" FOR ALL TO service_role USING (true) WITH CHECK (true);

-- StaffSchedule
ALTER TABLE "public"."StaffSchedule" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon full access on StaffSchedule" ON "public"."StaffSchedule" FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "Allow service_role full access on StaffSchedule" ON "public"."StaffSchedule" FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Offer
ALTER TABLE "public"."Offer" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon full access on Offer" ON "public"."Offer" FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "Allow service_role full access on Offer" ON "public"."Offer" FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Gallery
ALTER TABLE "public"."Gallery" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon full access on Gallery" ON "public"."Gallery" FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "Allow service_role full access on Gallery" ON "public"."Gallery" FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Order
ALTER TABLE "public"."Order" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon full access on Order" ON "public"."Order" FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "Allow service_role full access on Order" ON "public"."Order" FOR ALL TO service_role USING (true) WITH CHECK (true);

-- CmsPage
ALTER TABLE "public"."CmsPage" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon read on CmsPage" ON "public"."CmsPage" FOR SELECT TO anon USING (true);

CREATE POLICY "Allow service_role full access on CmsPage" ON "public"."CmsPage" FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ====================================================================
-- DONE! Run this entire script in Supabase SQL Editor.
-- ====================================================================

INSERT INTO "public"."AppUserRole" (user_id, email, name, role, permissions)
VALUES (
  'd9887e88-da7a-4dea-b62d-23e68ca53e35',
  'admin@gardenia.com',
  'المدير',
  'admin',
  '["all"]'::jsonb
);

-- ====================================================================
-- GARDENIA SALON — Split Catalog into Services + Products
-- Run this in Supabase SQL Editor
-- ====================================================================

-- 1. Add "type" column with CHECK constraint
ALTER TABLE "public"."Product"
  ADD COLUMN IF NOT EXISTS "type" TEXT DEFAULT 'service';

-- Add constraint safely
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'product_type_check'
  ) THEN
    ALTER TABLE "public"."Product"
      ADD CONSTRAINT product_type_check CHECK ("type" IN ('service', 'product'));
  END IF;
END $$;

-- 2. Auto-classify existing rows based on stock column
-- stock IS NOT NULL → product, otherwise → service
UPDATE "public"."Product"
SET "type" = CASE
  WHEN "stock" IS NOT NULL THEN 'product'
  ELSE 'service'
END
WHERE "type" IS NULL OR "type" = 'service';

-- ====================================================================
-- DONE! After running this, existing items will be auto-classified.
-- ====================================================================

-- ====================================================================
-- GARDENIA SALON — Split Catalog into Services + Products
-- Run this in Supabase SQL Editor
-- ====================================================================

-- 1. Add "type" column with CHECK constraint
ALTER TABLE "public"."Product"
  ADD COLUMN IF NOT EXISTS "type" TEXT DEFAULT 'service';

-- Add constraint safely
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'product_type_check'
  ) THEN
    ALTER TABLE "public"."Product"
      ADD CONSTRAINT product_type_check CHECK ("type" IN ('service', 'product'));
  END IF;
END $$;

-- 2. Auto-classify existing rows based on stock column
-- stock IS NOT NULL → product, otherwise → service
UPDATE "public"."Product"
SET "type" = CASE
  WHEN "stock" IS NOT NULL THEN 'product'
  ELSE 'service'
END
WHERE "type" IS NULL OR "type" = 'service';

-- ====================================================================
-- 3. Add "type" column to Category table
-- ====================================================================

ALTER TABLE "public"."Category"
  ADD COLUMN IF NOT EXISTS "type" TEXT DEFAULT 'service';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'category_type_check'
  ) THEN
    ALTER TABLE "public"."Category"
      ADD CONSTRAINT category_type_check CHECK ("type" IN ('service', 'product'));
  END IF;
END $$;

-- Auto-classify: existing categories default to 'service'
UPDATE "public"."Category"
SET "type" = 'service'
WHERE "type" IS NULL;

-- ====================================================================
-- DONE! After running this, existing items will be auto-classified.
-- ====================================================================

INSERT INTO "public"."SystemSetting" ("key", "value") VALUES
  ('salon_address', ''),
  ('order_notification_whatsapp', ''),
  ('delivery_fee', '2'),
  ('salon_phone', '962786753791'),
  ('whatsapp_number', '962786753791'),
  ('working_hours_weekdays', 'السبت - الخميس: 10:00 ص - 8:00 م'),
  ('working_hours_friday', 'الجمعة: مغلق'),
  ('instagram_url', ''),
  ('facebook_url', ''),
  ('tiktok_url', ''),
  ('google_maps_url', 'https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d217257.96330223998!2d35.72862505!3d31.9539494!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x151b5fb85d7981b1%3A0x631c30c0f8dc65e8!2sAmman%2C%20Jordan!5e0!3m2!1sar!2sus!4v1'),
  ('booking_start_time', '09:00'),
  ('booking_end_time', '20:00')
ON CONFLICT ("key") DO NOTHING;

-- ====================================================================
-- MIGRATION: Add Branches, Staff, and Branch Pricing
-- ====================================================================

-- --------------------------------------------------------
-- Table: Branch
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."Branch" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "name" TEXT NOT NULL,
    "nameAr" TEXT DEFAULT '',
    "address" TEXT DEFAULT '',
    "phone" TEXT DEFAULT '',
    "isActive" BOOLEAN DEFAULT TRUE,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Branch";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Branch" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- --------------------------------------------------------
-- Table: Staff (العاملات)
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."Staff" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "name" TEXT NOT NULL,
    "nameAr" TEXT DEFAULT '',
    "branchId" UUID REFERENCES "public"."Branch"("id") ON DELETE CASCADE,
    "role" TEXT DEFAULT 'staff',
    "isActive" BOOLEAN DEFAULT TRUE,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."Staff";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."Staff" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- --------------------------------------------------------
-- Table: ProductBranchPrice
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."ProductBranchPrice" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "productId" UUID NOT NULL REFERENCES "public"."Product"("id") ON DELETE CASCADE,
    "branchId" UUID NOT NULL REFERENCES "public"."Branch"("id") ON DELETE CASCADE,
    "price" DOUBLE PRECISION NOT NULL,
    "isAvailable" BOOLEAN DEFAULT TRUE,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_product_branch UNIQUE ("productId", "branchId")
);

DROP TRIGGER IF EXISTS handle_updated_at ON "public"."ProductBranchPrice";

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON "public"."ProductBranchPrice" 
FOR EACH ROW EXECUTE FUNCTION moddatetime("updatedAt");

-- --------------------------------------------------------
-- Alter Table: Booking
-- --------------------------------------------------------
ALTER TABLE "public"."Booking" 
ADD COLUMN IF NOT EXISTS "branchId" UUID REFERENCES "public"."Branch"("id") ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS "staffId" UUID REFERENCES "public"."Staff"("id") ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS "bookingType" TEXT DEFAULT 'in_branch';

-- --------------------------------------------------------
-- Seed: Disable At Home Service (SystemSetting)
-- --------------------------------------------------------
-- Create SystemSetting if it doesn't exist just in case
CREATE TABLE IF NOT EXISTS "public"."SystemSetting" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "key" TEXT UNIQUE NOT NULL,
    "value" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    "updatedAt" TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO "public"."SystemSetting" ("key", "value") 
VALUES ('at_home_service_enabled', 'false')
ON CONFLICT ("key") DO UPDATE SET "value" = 'false';

-- ====================================================================
-- MIGRATION FIX: Add missing columns to Staff
-- ====================================================================

-- Add columns that existed in the original API but were missed in the new table schema
ALTER TABLE "public"."Staff" 
ADD COLUMN IF NOT EXISTS "phone" TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS "avatar" TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS "services" TEXT[] DEFAULT '{}';

-- ====================================================================
-- MIGRATION: Add branchId to Product (Service/Product belongs to Branch)
-- Pattern: Same as Staff.branchId → Branch FK
-- ====================================================================

ALTER TABLE "public"."Product"
ADD COLUMN IF NOT EXISTS "branchId" UUID REFERENCES "public"."Branch"("id") ON DELETE CASCADE;

-- NOTE: Existing products will have branchId = NULL.
-- Assign them to branches manually via the dashboard.
-- The ProductBranchPrice table is left intact but is no longer used.

-- ====================================================================
-- MIGRATION: Add auth_user_id to Client for Customer Login
-- Links Supabase Auth users to the CRM Client table
-- ====================================================================

-- Add auth_user_id column (nullable — most clients are guests or WhatsApp)
ALTER TABLE "public"."Client"
ADD COLUMN IF NOT EXISTS "auth_user_id" UUID UNIQUE;

-- NOTE: We intentionally do NOT add a FK to auth.users because the
-- service_role client cannot always reference auth schema directly.
-- The link is maintained at the application level.

-- ====================================================================
-- FIX: Add missing FK constraint from Staff.branchId → Branch.id
-- The Staff table was created before the Branch table, so the FK
-- constraint was never applied by CREATE TABLE IF NOT EXISTS.
-- ====================================================================

-- 1. Add branchId column if it doesn't exist
ALTER TABLE "public"."Staff"
ADD COLUMN IF NOT EXISTS "branchId" UUID;

-- 2. Add the FK constraint (skip if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'staff_branchid_fkey'
  ) THEN
    ALTER TABLE "public"."Staff"
    ADD CONSTRAINT staff_branchid_fkey
    FOREIGN KEY ("branchId") REFERENCES "public"."Branch"("id") ON DELETE CASCADE;
  END IF;
END $$;

-- ====================================================================
-- MIGRATION: Smart Booking Engine
-- Adds service duration, deposit, publish timing, staff-service junction,
-- and enhanced booking columns for the availability engine.
-- ====================================================================

-- ────────────────────────────────────────────────────────────────────
-- 1. Product (Service) Enhancements
-- ────────────────────────────────────────────────────────────────────

-- Duration in minutes (e.g. 30, 60, 90)
ALTER TABLE "public"."Product"
ADD COLUMN IF NOT EXISTS "durationMinutes" INTEGER DEFAULT 30;

-- Duration mode: 'time' = customer picks a time slot, 'queue' = customer gets queue number
ALTER TABLE "public"."Product"
ADD COLUMN IF NOT EXISTS "durationMode" TEXT DEFAULT 'time';

-- Deposit amount (عربون) — paid via payment gateway
ALTER TABLE "public"."Product"
ADD COLUMN IF NOT EXISTS "depositAmount" DOUBLE PRECISION DEFAULT 0;

-- Publish timing — NULL = publish immediately, otherwise publish at this date
ALTER TABLE "public"."Product"
ADD COLUMN IF NOT EXISTS "publishAt" TIMESTAMPTZ;

-- ────────────────────────────────────────────────────────────────────
-- 2. StaffService Junction Table (which staff can perform which service)
-- ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."StaffService" (
    "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "staff_id" UUID NOT NULL REFERENCES "public"."Staff"("id") ON DELETE CASCADE,
    "product_id" UUID NOT NULL REFERENCES "public"."Product"("id") ON DELETE CASCADE,
    "createdAt" TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_staff_product UNIQUE ("staff_id", "product_id")
);

-- ────────────────────────────────────────────────────────────────────
-- 3. Booking Enhancements
-- ────────────────────────────────────────────────────────────────────

-- Link booking to specific service
ALTER TABLE "public"."Booking"
ADD COLUMN IF NOT EXISTS "serviceId" UUID REFERENCES "public"."Product"("id") ON DELETE SET NULL;

-- End time (calculated as bookingDate + durationMinutes)
ALTER TABLE "public"."Booking"
ADD COLUMN IF NOT EXISTS "endTime" TIMESTAMPTZ;

-- Deposit tracking
ALTER TABLE "public"."Booking"
ADD COLUMN IF NOT EXISTS "depositAmount" DOUBLE PRECISION DEFAULT 0;

ALTER TABLE "public"."Booking"
ADD COLUMN IF NOT EXISTS "depositStatus" TEXT DEFAULT 'unpaid';

-- Queue number (for queue-mode services)
ALTER TABLE "public"."Booking"
ADD COLUMN IF NOT EXISTS "queueNumber" INTEGER;

-- Payment method
ALTER TABLE "public"."Booking"
ADD COLUMN IF NOT EXISTS "paymentMethod" TEXT DEFAULT 'cash';

-- ────────────────────────────────────────────────────────────────────
-- 4. Row Level Security for StaffService
-- ────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."StaffService" ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'StaffService' AND policyname = 'Allow anon full access on StaffService'
  ) THEN
    CREATE POLICY "Allow anon full access on StaffService"
      ON "public"."StaffService" FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'StaffService' AND policyname = 'Allow service_role full access on StaffService'
  ) THEN
    CREATE POLICY "Allow service_role full access on StaffService"
      ON "public"."StaffService" FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ────────────────────────────────────────────────────────────────────
-- 5. SystemSetting Seeds (Terms & Conditions)
-- ────────────────────────────────────────────────────────────────────

INSERT INTO "public"."SystemSetting" ("key", "value") VALUES
  ('booking_terms', 'يرجى الالتزام بموعد الحجز. في حالة التأخر أكثر من 15 دقيقة، قد يتم إلغاء الحجز. العربون غير قابل للاسترداد في حالة الإلغاء قبل أقل من 24 ساعة من الموعد.'),
  ('terms_and_conditions', 'باستخدامك لخدمات صالون جاردينيا، فإنك توافق على شروط الخدمة وسياسة الخصوصية الخاصة بنا. جميع الأسعار قابلة للتغيير دون إشعار مسبق.')
ON CONFLICT ("key") DO NOTHING;

-- ────────────────────────────────────────────────────────────────────
-- 6. Deposit Status Constraint (safe add)
-- ────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'booking_deposit_status_check'
  ) THEN
    ALTER TABLE "public"."Booking"
      ADD CONSTRAINT booking_deposit_status_check
      CHECK ("depositStatus" IN ('unpaid', 'paid', 'refunded'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'booking_payment_method_check'
  ) THEN
    ALTER TABLE "public"."Booking"
      ADD CONSTRAINT booking_payment_method_check
      CHECK ("paymentMethod" IN ('cash', 'card', 'online'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'product_duration_mode_check'
  ) THEN
    ALTER TABLE "public"."Product"
      ADD CONSTRAINT product_duration_mode_check
      CHECK ("durationMode" IN ('time', 'queue'));
  END IF;
END $$;

-- Add image column to Category table for booking wizard display
ALTER TABLE "public"."Category"
ADD COLUMN IF NOT EXISTS "image" TEXT DEFAULT '';

INSERT INTO "CmsPage" ("slug", "title", "content")
VALUES (
  'booking-conditions',
  'شروط وأحكام الحجز',
  'نص الشروط والأحكام هنا...'
)
ON CONFLICT ("slug") DO UPDATE SET "content" = EXCLUDED."content";

UPDATE "CmsPage"
SET
    "content" = '1. يجب الحضور في الموعد المحدد
2. في حال التأخر أكثر من 15 دقيقة سيتم إلغاء الحجز
3. يرجى إلغاء الحجز قبل 24 ساعة على الأقل
4. العربون غير قابل للاسترداد في حال عدم الحضور'
WHERE
    "slug" = 'booking-conditions';

-- ============================================================
-- Salon CRM — Feature Migration 001
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================================

-- ─── Feature 1: Manual Booking Fields ─────────────────────────
ALTER TABLE "Booking"
ADD COLUMN IF NOT EXISTS "bookingTime" TEXT,
ADD COLUMN IF NOT EXISTS "location" TEXT DEFAULT 'salon',
ADD COLUMN IF NOT EXISTS "paymentMethod" TEXT DEFAULT 'cash',
ADD COLUMN IF NOT EXISTS "source" TEXT DEFAULT 'bot',
ADD COLUMN IF NOT EXISTS "notes" TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS "branchId" UUID REFERENCES "Branch" (id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS "slotNumber" INTEGER;

-- ─── Feature 2: Staff Blocked Dates ──────────────────────────
CREATE TABLE IF NOT EXISTS "StaffBlockedDate" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid (),
    "staff_id" UUID NOT NULL REFERENCES "Staff" (id) ON DELETE CASCADE,
    "blockedDate" DATE NOT NULL,
    "reason" TEXT DEFAULT '',
    "createdAt" TIMESTAMPTZ DEFAULT now(),
    UNIQUE ("staff_id", "blockedDate")
);

ALTER TABLE "StaffBlockedDate" ENABLE ROW LEVEL SECURITY;

-- ─── Feature 4: Branch Contact Info ──────────────────────────
ALTER TABLE "Branch"
ADD COLUMN IF NOT EXISTS "whatsapp" TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS "email" TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS "instagramUrl" TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS "facebookUrl" TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS "googleMapsUrl" TEXT DEFAULT '';

-- ─── Feature 6: Offer Channel ────────────────────────────────
ALTER TABLE "Offer"
ADD COLUMN IF NOT EXISTS "channel" TEXT DEFAULT 'website';

-- ─── Feature 8: Notifications ────────────────────────────────
CREATE TABLE IF NOT EXISTS "Notification" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid (),
    "type" TEXT NOT NULL DEFAULT 'customer_service',
    "title" TEXT NOT NULL,
    "body" TEXT DEFAULT '',
    "client_id" UUID REFERENCES "Client" (id) ON DELETE SET NULL,
    "isRead" BOOLEAN DEFAULT false,
    "createdAt" TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE "Notification" ENABLE ROW LEVEL SECURITY;

-- ─── Feature 9: Queue Slots ─────────────────────────────────
ALTER TABLE "Product"
ADD COLUMN IF NOT EXISTS "maxSlots" INTEGER DEFAULT NULL;

-- 1. Create the 'gallery' bucket and make it public
INSERT INTO
    storage.buckets (id, name, public)
VALUES ('gallery', 'gallery', true) ON CONFLICT (id) DO NOTHING;

-- 2. Allow everyone to view the images
CREATE POLICY "Public Read Access" ON storage.objects FOR
SELECT USING (bucket_id = 'gallery');

-- 3. Allow only authenticated admin users to upload images
CREATE POLICY "Auth Insert Access" ON storage.objects FOR
INSERT
WITH
    CHECK (
        bucket_id = 'gallery'
        AND auth.role () = 'authenticated'
    );

-- 4. Allow only authenticated admin users to delete images
CREATE POLICY "Auth Delete Access" ON storage.objects FOR DELETE USING (
    bucket_id = 'gallery'
    AND auth.role () = 'authenticated'
);

-- Drop any existing restrictive policies on storage.objects for gallery bucket
DROP POLICY IF EXISTS "Public Read Access" ON storage.objects;

DROP POLICY IF EXISTS "Auth Insert Access" ON storage.objects;

DROP POLICY IF EXISTS "Auth Delete Access" ON storage.objects;

-- Allow anyone to READ gallery images (public website needs this)
CREATE POLICY "gallery_public_read" ON storage.objects FOR
SELECT USING (bucket_id = 'gallery');

-- Allow anyone to UPLOAD to gallery (dashboard uses anon key client-side)
CREATE POLICY "gallery_allow_insert" ON storage.objects FOR
INSERT
WITH
    CHECK (bucket_id = 'gallery');

-- Allow anyone to UPDATE gallery images
CREATE POLICY "gallery_allow_update" ON storage.objects FOR
UPDATE USING (bucket_id = 'gallery');

-- Allow anyone to DELETE gallery images
CREATE POLICY "gallery_allow_delete" ON storage.objects FOR DELETE USING (bucket_id = 'gallery');

-- ============================================================
-- 002_contact_messages.sql
-- Creates ContactMessage table for website contact form submissions
-- ============================================================

CREATE TABLE IF NOT EXISTS public."ContactMessage" (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT DEFAULT '',
  message TEXT NOT NULL,
  "branchId" UUID REFERENCES public."Branch"(id) ON DELETE SET NULL,
  "isRead" BOOLEAN DEFAULT false,
  "createdAt" TIMESTAMPTZ DEFAULT now()
);

-- Index for dashboard queries (unread first, newest first)
CREATE INDEX IF NOT EXISTS idx_contact_message_read_date
  ON public."ContactMessage" ("isRead", "createdAt" DESC);

-- Allow service_role full access
ALTER TABLE public."ContactMessage" ENABLE ROW LEVEL SECURITY;

-- RLS: allow service_role to do everything (anon insert for public form)
CREATE POLICY "service_role_full_access" ON public."ContactMessage"
  FOR ALL USING (true) WITH CHECK (true);

-- Migration: Add bot_services_text SystemSetting
INSERT INTO "public"."SystemSetting" ("key", "value")
VALUES ('bot_services_text', '')
ON CONFLICT ("key") DO NOTHING;

-- ============================================================
-- Salon CRM — Feature Migration 004: Payment Booking Flow
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================================

-- ─── 1. Add payment/hold columns to Booking ─────────────────
ALTER TABLE "Booking"
ADD COLUMN IF NOT EXISTS "bookingCode" TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS "paymentExpiresAt" TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS "paymobIntentionId" TEXT,
ADD COLUMN IF NOT EXISTS "paymobTxnId" TEXT;

-- ─── 2. Index for fast lookups ──────────────────────────────
CREATE INDEX IF NOT EXISTS idx_booking_code ON "Booking" ("bookingCode");

CREATE INDEX IF NOT EXISTS idx_booking_payment_expires ON "Booking" ("paymentExpiresAt")
WHERE
    status = 'waiting_payment';

CREATE INDEX IF NOT EXISTS idx_booking_pending_created ON "Booking" ("createdAt")
WHERE
    status = 'pending';

SELECT id, name, "depositAmount"
FROM "Product"
WHERE
    id = '8d3fe352-29c2-43ed-9a0f-5e5f04db60ca';

-- ============================================================
-- Salon CRM — Migration 005: Prevent double-booking (DB-level)
-- Run this in Supabase Dashboard → SQL Editor. Idempotent.
-- ============================================================

-- btree_gist allows scalar columns (staff_id uuid) inside a GiST exclusion.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- One staff member cannot have two non-cancelled, time-based bookings
-- whose [bookingDate, endTime) intervals overlap.
ALTER TABLE "Booking" DROP CONSTRAINT IF EXISTS booking_no_overlap;

ALTER TABLE "Booking"
ADD CONSTRAINT booking_no_overlap EXCLUDE USING gist (
    staff_id
    WITH
        =,
        tstzrange ("bookingDate", "endTime")
    WITH
        &&
)
WHERE (
        "endTime" IS NOT NULL
        AND staff_id IS NOT NULL
        AND status <> 'cancelled'
    );

-- Index to support the overlap query the apps already run.
CREATE INDEX IF NOT EXISTS idx_booking_staff_date_gist ON "Booking" USING gist (
    staff_id,
    tstzrange ("bookingDate", "endTime")
);

-- ============================================================
-- Salon CRM — Migration 006: Backfill endTime (H10)
-- Run in Supabase Dashboard → SQL Editor.
-- Apply AFTER 005_booking_no_overlap.sql.
-- ============================================================
--
-- Why: migration 005's exclusion constraint only protects rows where
-- "endTime" IS NOT NULL. The CRM used to insert NULL endTime for
-- time-mode bookings that had no bookingTime, and the app fell back to a
-- hardcoded +30 min during overlap checks — so a 60-min service booked in
-- the 30–60 min window of such a row was NOT caught (double-booking gap).
-- This migration backfills endTime on every existing non-cancelled
-- time-mode booking so 005 fully protects them and the +30 min fallback
-- in the app can be removed.
--
-- STEP 1 — PRE-CHECK (run this SELECT first; resolve any pairs it returns
-- manually — e.g. cancel one of them — before running STEP 2).
-- It finds non-cancelled bookings for the same staff whose intervals
-- [bookingDate, computed_end) would overlap once endTime is backfilled.
-- computed_end = endTime when already set, else bookingDate + duration.

WITH computed AS (
  SELECT
    b.id,
    b.staff_id,
    b."bookingDate",
    COALESCE(
      b."endTime",
      b."bookingDate" + (p."durationMinutes" || ' minutes')::interval
    ) AS "computedEnd",
    b.status
  FROM "Booking" b
  LEFT JOIN "Product" p ON p.id = b."serviceId"
  WHERE b.status <> 'cancelled'
    AND b.staff_id IS NOT NULL
)
SELECT
  a.id   AS booking_a,
  b.id   AS booking_b,
  a.staff_id,
  a."bookingDate" AS start_a,
  a."computedEnd" AS end_a,
  b."bookingDate" AS start_b,
  b."computedEnd" AS end_b
FROM computed a
JOIN computed b
  ON a.staff_id = b.staff_id
 AND a.id < b.id
 AND tstzrange(a."bookingDate", a."computedEnd") && tstzrange(b."bookingDate", b."computedEnd")
ORDER BY a.staff_id, a."bookingDate";

-- STEP 2 — BACKFILL endTime for rows that are missing it.
-- (If STEP 1 returned rows, fix them first or this UPDATE will raise
--  exclusion_violation from the 005 constraint — which is the safety net
--  working as intended.)
UPDATE "Booking" b
SET "endTime" = b."bookingDate" + (p."durationMinutes" || ' minutes')::interval
FROM "Product" p
WHERE p.id = b."serviceId"
  AND b."endTime" IS NULL
  AND b.status <> 'cancelled'
  AND p."durationMinutes" IS NOT NULL;

-- ============================================================
-- Salon CRM — Migration 007: slotNumber uniqueness + maxSlots enforcement (H11)
-- Run in Supabase Dashboard → SQL Editor. Idempotent.
-- ============================================================

-- NOTE on mixed-case columns: PostgreSQL lowercases unquoted identifiers, so
-- "slotNumber", "serviceId", "bookingDate" (mixed-case in this schema) MUST be
-- double-quoted. Lowercase columns (status, id) stay unquoted.

-- Drop the earlier (broken) expression-index attempt if a partial run left it.
DROP INDEX IF EXISTS booking_slotnumber_unique;

-- ------------------------------------------------------------
-- H11a: slotNumber uniqueness — one active slot per (service, day).
-- A GiST/UNIQUE *expression index* on date_trunc(day, timestamptz) is NOT
-- allowed (date_trunc on timestamptz is STABLE, not IMMUTABLE), so we enforce
-- it with a BEFORE INSERT/UPDATE trigger instead. Under a per-(service,day,
-- slot) advisory lock it rejects a duplicate active slot for the same service
-- on the same calendar day, raising SQLSTATE 23505 (unique_violation) — the
-- apps map that to a 409 alongside the existing 23P01 handling.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION enforce_slotnumber_unique()
RETURNS trigger AS $$
DECLARE
  day_start timestamptz;
  day_end   timestamptz;
  dup_id    uuid;
  v_slot    integer;
  v_svc     uuid;
BEGIN
  -- No slot to protect, or the row is being cancelled (frees the slot).
  IF NEW."slotNumber" IS NULL OR NEW.status = 'cancelled' THEN
    RETURN NEW;
  END IF;

  v_slot := NEW."slotNumber";
  v_svc  := NEW."serviceId";
  day_start := date_trunc('day', NEW."bookingDate");
  day_end   := day_start + interval '1 day';

  -- Serialize concurrent inserts/updates for the same (service, slot) so the
  -- check-then-act window can't let a duplicate through.
  PERFORM pg_advisory_xact_lock(
    hashtext(COALESCE(v_svc::text, '')),
    v_slot
  );

  SELECT id INTO dup_id
  FROM "Booking"
  WHERE "slotNumber" = v_slot
    AND "serviceId" IS NOT DISTINCT FROM v_svc
    AND "bookingDate" >= day_start
    AND "bookingDate" < day_end
    AND status <> 'cancelled'
    AND id <> NEW.id
  LIMIT 1;

  IF dup_id IS NOT NULL THEN
    RAISE EXCEPTION 'duplicate slotNumber % for service % on %', v_slot, v_svc, day_start
      USING ERRCODE = 'unique_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_booking_slotnumber_unique ON "Booking";

CREATE TRIGGER trg_booking_slotnumber_unique
  BEFORE INSERT OR UPDATE ON "Booking"
  FOR EACH ROW
  EXECUTE FUNCTION enforce_slotnumber_unique();

-- ------------------------------------------------------------
-- H11b: DB-enforced maxSlots — kills the count->check->insert TOCTOU race
-- that let concurrent bookings exceed Product.maxSlots. Applies to
-- inserts from BOTH apps (CRM saloon-mostafa + storefront gardenia-website).
--
-- The trigger locks the Product row (FOR UPDATE) so concurrent inserts
-- for the same service serialize, then counts non-cancelled bookings for
-- the same service on the same day. If the count already >= maxSlots it
-- raises 'max_slots_exceeded' (SQLSTATE P0001) — the apps map it to 409.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION enforce_booking_max_slots()
RETURNS trigger AS $$
DECLARE
  day_start    timestamptz;
  day_end      timestamptz;
  current_count integer;
  max_slots    integer;
BEGIN
  IF NEW.status = 'cancelled' THEN
    RETURN NEW;
  END IF;

  -- Lock the service row so concurrent inserts for the same service
  -- serialize within their transactions, removing the TOCTOU window.
  SELECT "maxSlots" INTO max_slots
  FROM "Product"
  WHERE id = NEW."serviceId"
  FOR UPDATE;

  IF max_slots IS NULL THEN
    RETURN NEW;
  END IF;

  day_start := date_trunc('day', NEW."bookingDate");
  day_end   := day_start + interval '1 day';

  SELECT count(*) INTO current_count
  FROM "Booking"
  WHERE "serviceId" = NEW."serviceId"
    AND "bookingDate" >= day_start
    AND "bookingDate" < day_end
    AND status <> 'cancelled'
    AND id <> NEW.id;

  IF current_count >= max_slots THEN
    RAISE EXCEPTION 'max_slots_exceeded';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_booking_max_slots ON "Booking";

CREATE TRIGGER trg_booking_max_slots
  BEFORE INSERT ON "Booking"
  FOR EACH ROW
  EXECUTE FUNCTION enforce_booking_max_slots();

CREATE OR REPLACE FUNCTION public.handle_duplicate_message()
RETURNS TRIGGER AS $$
DECLARE
  existing_id UUID;
BEGIN
  -- Only check outgoing messages (agent/bot)
  IF NEW.sender_type IN ('agent', 'bot') THEN
    SELECT id INTO existing_id
    FROM public."Message"
    WHERE client_id = NEW.client_id
      AND sender_type IN ('agent', 'bot')
      AND text_content = NEW.text_content
      AND sent_at >= NOW() - INTERVAL '20 seconds'
    ORDER BY sent_at DESC
    LIMIT 1;

    IF existing_id IS NOT NULL THEN
      -- Update the existing row's platform ID if the new one has it
      IF NEW.message_platform_id IS NOT NULL THEN
        UPDATE public."Message"
        SET message_platform_id = NEW.message_platform_id
        WHERE id = existing_id;
      END IF;
      RETURN NULL; -- Discard duplicate
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_handle_duplicate_message ON public."Message";

CREATE TRIGGER tr_handle_duplicate_message
BEFORE INSERT ON public."Message"
FOR EACH ROW
EXECUTE FUNCTION public.handle_duplicate_message();

-- Migration 008: Allow 'demo' role in AppUserRole_role_check
ALTER TABLE "public"."AppUserRole" DROP CONSTRAINT IF EXISTS "AppUserRole_role_check";

ALTER TABLE "public"."AppUserRole" ADD CONSTRAINT "AppUserRole_role_check" CHECK (role IN ('admin', 'team', 'demo'));

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
INSERT INTO
    storage.buckets (id, name, public)
VALUES (
        'saloon_uploads',
        'saloon_uploads',
        true
    ) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "saloon_uploads_public_read" ON storage.objects;

DROP POLICY IF EXISTS "saloon_uploads_allow_insert" ON storage.objects;

DROP POLICY IF EXISTS "saloon_uploads_allow_update" ON storage.objects;

DROP POLICY IF EXISTS "saloon_uploads_allow_delete" ON storage.objects;

CREATE POLICY "saloon_uploads_public_read" ON storage.objects FOR
SELECT USING (bucket_id = 'saloon_uploads');

CREATE POLICY "saloon_uploads_allow_insert" ON storage.objects FOR
INSERT
WITH
    CHECK (bucket_id = 'saloon_uploads');

CREATE POLICY "saloon_uploads_allow_update" ON storage.objects FOR
UPDATE USING (bucket_id = 'saloon_uploads');

CREATE POLICY "saloon_uploads_allow_delete" ON storage.objects FOR DELETE USING (bucket_id = 'saloon_uploads');
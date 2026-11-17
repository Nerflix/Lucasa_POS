-- ============================================================================
-- SQL RECONCILIATION SCRIPT
-- ============================================================================
-- This script fixes the "Database error: could not find the table 'public.locations'"
-- and creates missing columns required by the Dart code.
--
-
-- ============================================================================

-- 1. Create table if it doesn't exist (Base definition)
CREATE TABLE IF NOT EXISTS public.locations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  email TEXT,
  till_number TEXT,
  paybill_number TEXT,
  logo_url TEXT,
  ago_pumps INTEGER DEFAULT 0,
  pms_pumps INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Add missing columns safely (Idempotent - won't fail if they exist)
DO $$
BEGIN
    -- Add is_active if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'locations' AND column_name = 'is_active') THEN
        ALTER TABLE public.locations ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
    END IF;

    -- Add logo_local_path if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'locations' AND column_name = 'logo_local_path') THEN
        ALTER TABLE public.locations ADD COLUMN logo_local_path TEXT;
    END IF;
END $$;

-- 3. Ensure Row Level Security is Enabled
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- 4. Re-apply Policies (Drop existing to avoid conflicts)
DROP POLICY IF EXISTS "Allow service role full access to locations" ON public.locations;

-- Create a permissible policy for authenticated users (Service Role bypasses this anyway, but good for testing)
CREATE POLICY "Allow service role full access to locations"
  ON public.locations
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- 5. Grant permissions to service_role (standard Supabase setup)
GRANT ALL ON public.locations TO service_role;
GRANT ALL ON public.locations TO postgres;
GRANT ALL ON public.locations TO anon; -- Only if you need public access (usually not recommended for write)
GRANT ALL ON public.locations TO authenticated;

-- Confirmation
SELECT 'Locations table reconciled successfully' as status;

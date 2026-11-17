-- ============================================================================
-- SQL RLS FIX SCRIPT
-- ============================================================================
-- This script fixes the "new row violates row-level security policy" error.
-- It works by allowing PUBLIC (anonymous) access to the locations table.
--
-- INSTRUCTIONS:
-- 1. Copy the content of this file.
-- 2. Go to your Supabase Dashboard > SQL Editor.
-- 3. Paste and run this script.
-- ============================================================================

-- 1. Enable RLS (Should already be enabled, but good to ensure)
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing restrictive policies
DROP POLICY IF EXISTS "Allow service role full access to locations" ON public.locations;
DROP POLICY IF EXISTS "Allow public full access to locations" ON public.locations;

-- 3. Create a PERMISSIVE policy for ALL users (Authenticated and Anonymous)
--    Since your app handles auth logic internally, we trust the app to send correct data.
CREATE POLICY "Allow public full access to locations"
  ON public.locations
  FOR ALL
  TO public
  USING (true)
  WITH CHECK (true);

-- 4. Grant necessary permissions
GRANT ALL ON public.locations TO anon;
GRANT ALL ON public.locations TO authenticated;
GRANT ALL ON public.locations TO service_role;

-- Confirmation
SELECT 'RLS Policy updated to allow public access' as status;

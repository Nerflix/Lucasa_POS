-- ============================================================================
-- CREATE SALE_AUDIT_LOGS TABLE
-- ============================================================================
-- Required for the auditing feature in Reports page.
-- This table tracks edits and deletions of sales records.

CREATE TABLE IF NOT EXISTS public.sale_audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    action TEXT NOT NULL, -- 'DELETE' or 'EDIT'
    sale_id TEXT NOT NULL, -- Human-readable receipt ID
    performed_by TEXT NOT NULL, -- Employee name
    performed_at TIMESTAMPTZ DEFAULT NOW(),
    location_id TEXT REFERENCES public.locations(id),
    category TEXT,
    snapshot JSONB NOT NULL -- Full sale + items at time of action
);

-- CREATE INDEXES
CREATE INDEX IF NOT EXISTS idx_sale_audit_logs_location ON public.sale_audit_logs(location_id);
CREATE INDEX IF NOT EXISTS idx_sale_audit_logs_performed_at ON public.sale_audit_logs(performed_at);
CREATE INDEX IF NOT EXISTS idx_sale_audit_logs_action ON public.sale_audit_logs(action);

-- ENABLE ROW LEVEL SECURITY
ALTER TABLE public.sale_audit_logs ENABLE ROW LEVEL SECURITY;

-- CREATE PERMISSIVE POLICIES
DROP POLICY IF EXISTS "Allow public full access to sale_audit_logs" ON public.sale_audit_logs;
CREATE POLICY "Allow public full access to sale_audit_logs" 
    ON public.sale_audit_logs FOR ALL 
    TO public 
    USING (true) 
    WITH CHECK (true);

-- Also add policies for 'service_role' (Standard Supabase setup)
DROP POLICY IF EXISTS "Allow service role full access to sale_audit_logs" ON public.sale_audit_logs;
CREATE POLICY "Allow service role full access to sale_audit_logs" 
    ON public.sale_audit_logs FOR ALL 
    TO service_role 
    USING (true) 
    WITH CHECK (true);

-- GRANT PERMISSIONS
GRANT ALL ON public.sale_audit_logs TO anon;
GRANT ALL ON public.sale_audit_logs TO authenticated;
GRANT ALL ON public.sale_audit_logs TO service_role;

-- Verification
SELECT 'Sale audit logs table created successfully' as status;

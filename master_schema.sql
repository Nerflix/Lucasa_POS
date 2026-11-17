-- ============================================================================
-- LUCASA POS - MASTER SUPABASE SCHEMA
-- ============================================================================
-- This script defines the entire database schema for the Lucasa POS application.
-- It works by:
-- 1. Creating tables if they don't exist.
-- 2. Adding missing columns to existing tables (Idempotent updates).
-- 3. Setting up Row Level Security (RLS) to allow PUBLIC (anonymous) access.
--    (Required because the app uses custom auth, not Supabase Auth).
--
-- INSTRUCTIONS:
-- 1. Copy the content of this file.
-- 2. Go to your Supabase Dashboard > SQL Editor.
-- 3. Paste and run this script.
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- 1. UTILITY FUNCTIONS
-- ============================================================================

-- Function to update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2. TABLE DEFINITIONS
-- ============================================================================

-- LOCATIONS
CREATE TABLE IF NOT EXISTS locations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  email TEXT,
  till_number TEXT,
  paybill_number TEXT,
  logo_url TEXT,
  logo_local_path TEXT, -- Added field
  ago_pumps INTEGER DEFAULT 0,
  pms_pumps INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE, -- Added field
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- EMPLOYEES
CREATE TABLE IF NOT EXISTS employees (
  id TEXT PRIMARY KEY,
  location_id TEXT, -- JSON array string or single ID
  role TEXT NOT NULL CHECK (role IN ('super_admin', 'admin', 'employee')),
  first_name TEXT NOT NULL,
  middle_name TEXT,
  surname TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT NOT NULL,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  permissions JSONB,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(), -- Added field to match Dart model
  synced_at TIMESTAMPTZ
);

-- ITEMS
CREATE TABLE IF NOT EXISTS items (
  id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(id),
  category TEXT DEFAULT 'Filling Station', -- Added field
  name TEXT NOT NULL,
  barcode TEXT,
  buying_price DECIMAL(10,2) NOT NULL,
  selling_price DECIMAL(10,2) NOT NULL,
  wholesale_price DECIMAL(10,2) NOT NULL,
  quantity DECIMAL(10,2) DEFAULT 0,
  reorder_level DOUBLE PRECISION DEFAULT 0,
  created_by TEXT NOT NULL REFERENCES employees(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

-- SALES
CREATE TABLE IF NOT EXISTS sales (
  id TEXT PRIMARY KEY,
  sale_id TEXT UNIQUE NOT NULL,
  location_id TEXT NOT NULL REFERENCES locations(id),
  category TEXT DEFAULT 'Filling Station', -- Added field
  employee_id TEXT NOT NULL REFERENCES employees(id),
  payment_method TEXT NOT NULL, -- Flexible check handled by app or loose constraint
  total_amount DECIMAL(10,2) NOT NULL,
  amount_paid DECIMAL(10,2) NOT NULL,
  change_given DECIMAL(10,2) DEFAULT 0,
  profit DECIMAL(10,2) DEFAULT 0,
  is_suspended BOOLEAN DEFAULT FALSE,
  suspension_notes TEXT,
  employee_name TEXT, -- Added field (redundant but useful for generic display)
  notes TEXT, -- Added field
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

-- SALE ITEMS
CREATE TABLE IF NOT EXISTS sale_items (
  id TEXT PRIMARY KEY,
  sale_id TEXT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  item_id TEXT NOT NULL REFERENCES items(id),
  item_name TEXT NOT NULL,
  quantity DECIMAL(10,2) NOT NULL,
  buying_price DECIMAL(10,2) NOT NULL,
  selling_price DECIMAL(10,2) NOT NULL,
  pricing_type TEXT NOT NULL CHECK (pricing_type IN ('retail', 'wholesale')),
  subtotal DECIMAL(10,2) NOT NULL,
  discount DECIMAL(10,2) DEFAULT 0,
  synced_at TIMESTAMPTZ
);

-- RECEIVINGS
CREATE TABLE IF NOT EXISTS receivings (
  id TEXT PRIMARY KEY,
  receiving_id TEXT UNIQUE NOT NULL,
  location_id TEXT NOT NULL REFERENCES locations(id),
  category TEXT DEFAULT 'Filling Station', -- Added field
  employee_id TEXT NOT NULL REFERENCES employees(id),
  total_amount DECIMAL(10,2) NOT NULL,
  employee_name TEXT, -- Added field
  notes TEXT, -- Added field
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

-- RECEIVING ITEMS
CREATE TABLE IF NOT EXISTS receiving_items (
  id TEXT PRIMARY KEY,
  receiving_id TEXT NOT NULL REFERENCES receivings(id) ON DELETE CASCADE,
  item_id TEXT NOT NULL REFERENCES items(id),
  item_name TEXT NOT NULL,
  quantity DECIMAL(10,2) NOT NULL,
  buying_price DECIMAL(10,2) NOT NULL,
  subtotal DECIMAL(10,2) NOT NULL,
  synced_at TIMESTAMPTZ
);

-- CUSTOMERS
CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(id),
  category TEXT DEFAULT 'Filling Station', -- Added field
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

-- CREDITS
CREATE TABLE IF NOT EXISTS credits (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL REFERENCES customers(id),
  sale_id TEXT NOT NULL REFERENCES sales(id),
  location_id TEXT NOT NULL REFERENCES locations(id),
  category TEXT DEFAULT 'Filling Station', -- Added field
  total_owed DECIMAL(10,2) NOT NULL,
  amount_paid DECIMAL(10,2) DEFAULT 0,
  balance DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_payment_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ
);

-- CREDIT PAYMENTS
CREATE TABLE IF NOT EXISTS credit_payments (
  id TEXT PRIMARY KEY,
  credit_id TEXT NOT NULL REFERENCES credits(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  paid_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

-- METER READINGS
CREATE TABLE IF NOT EXISTS meter_readings (
  id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(id),
  employee_id TEXT NOT NULL REFERENCES employees(id),
  reading_type TEXT NOT NULL CHECK (reading_type IN ('opening', 'closing')),
  category TEXT DEFAULT 'Filling Station', -- Added field
  pump_type TEXT NOT NULL CHECK (pump_type IN ('AGO', 'PMS')),
  pump_number INTEGER NOT NULL,
  value_a DECIMAL(10,2) NOT NULL,
  value_l DECIMAL(10,2) NOT NULL,
  value_t DECIMAL(10,2) NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

-- AUDIT LOGS
CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(id),
  employee_id TEXT NOT NULL REFERENCES employees(id),
  action_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  changes JSONB,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);


-- ============================================================================
-- 3. APPLY SCHEMA UPDATES (Adding missing columns if table exists)
-- ============================================================================

-- Add 'is_active' to locations if missing
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='locations' AND column_name='is_active') THEN
        ALTER TABLE locations ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='locations' AND column_name='logo_local_path') THEN
        ALTER TABLE locations ADD COLUMN logo_local_path TEXT;
    END IF;
    
    -- Add category columns where missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='items' AND column_name='category') THEN
        ALTER TABLE items ADD COLUMN category TEXT DEFAULT 'Filling Station';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sales' AND column_name='category') THEN
        ALTER TABLE sales ADD COLUMN category TEXT DEFAULT 'Filling Station';
    END IF;
    
     IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='receivings' AND column_name='category') THEN
        ALTER TABLE receivings ADD COLUMN category TEXT DEFAULT 'Filling Station';
    END IF;
    
     IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='customers' AND column_name='category') THEN
        ALTER TABLE customers ADD COLUMN category TEXT DEFAULT 'Filling Station';
    END IF;
    
     IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='credits' AND column_name='category') THEN
        ALTER TABLE credits ADD COLUMN category TEXT DEFAULT 'Filling Station';
    END IF;
    
     IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='meter_readings' AND column_name='category') THEN
        ALTER TABLE meter_readings ADD COLUMN category TEXT DEFAULT 'Filling Station';
    END IF;

    -- Add updated_at to employees if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='employees' AND column_name='updated_at') THEN
        ALTER TABLE employees ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Add discount to sale_items if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sale_items' AND column_name='discount') THEN
        ALTER TABLE sale_items ADD COLUMN discount DECIMAL(10,2) DEFAULT 0;
    END IF;
END $$;


-- ============================================================================
-- 4. CREATE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_employees_username ON employees(username);
CREATE INDEX IF NOT EXISTS idx_employees_location ON employees(location_id);
CREATE INDEX IF NOT EXISTS idx_employees_role ON employees(role);

CREATE INDEX IF NOT EXISTS idx_items_location ON items(location_id);
CREATE INDEX IF NOT EXISTS idx_items_barcode ON items(barcode);
CREATE INDEX IF NOT EXISTS idx_items_name ON items(name);

CREATE INDEX IF NOT EXISTS idx_sales_location ON sales(location_id);
CREATE INDEX IF NOT EXISTS idx_sales_employee ON sales(employee_id);
CREATE INDEX IF NOT EXISTS idx_sales_timestamp ON sales(timestamp);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id);

CREATE INDEX IF NOT EXISTS idx_receivings_location ON receivings(location_id);
CREATE INDEX IF NOT EXISTS idx_receivings_timestamp ON receivings(timestamp);

CREATE INDEX IF NOT EXISTS idx_receiving_items_receiving ON receiving_items(receiving_id);

CREATE INDEX IF NOT EXISTS idx_customers_location ON customers(location_id);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);

CREATE INDEX IF NOT EXISTS idx_credits_customer ON credits(customer_id);
CREATE INDEX IF NOT EXISTS idx_credits_location ON credits(location_id);

CREATE INDEX IF NOT EXISTS idx_credit_payments_credit ON credit_payments(credit_id);

CREATE INDEX IF NOT EXISTS idx_meter_readings_location ON meter_readings(location_id);
CREATE INDEX IF NOT EXISTS idx_meter_readings_employee ON meter_readings(employee_id);
CREATE INDEX IF NOT EXISTS idx_meter_readings_timestamp ON meter_readings(timestamp);

CREATE INDEX IF NOT EXISTS idx_audit_logs_location ON audit_logs(location_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_employee ON audit_logs(employee_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp);


-- ============================================================================
-- 5. ROW LEVEL SECURITY (RLS) FIX - PERMISSIVE PUBLIC ACCESS
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE receivings ENABLE ROW LEVEL SECURITY;
ALTER TABLE receiving_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE credits ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE meter_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- DROP ALL EXISTING POLICIES TO AVOID CONFLICTS
DO $$ 
DECLARE 
    r RECORD;
BEGIN 
    FOR r IN (SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public') LOOP 
        EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.' || r.tablename; 
    END LOOP; 
END $$;

-- CREATE PERMISSIVE POLICIES FOR ALL TABLES
-- These policies allow 'public' (anon) role to perform ALL operations (SELECT, INSERT, UPDATE, DELETE)

CREATE POLICY "Allow public full access to locations" ON locations FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to employees" ON employees FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to items" ON items FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to sales" ON sales FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to sale_items" ON sale_items FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to receivings" ON receivings FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to receiving_items" ON receiving_items FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to customers" ON customers FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to credits" ON credits FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to credit_payments" ON credit_payments FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to meter_readings" ON meter_readings FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Allow public full access to audit_logs" ON audit_logs FOR ALL TO public USING (true) WITH CHECK (true);

-- Also add policies for 'service_role' just in case
CREATE POLICY "Allow service role full access to locations" ON locations FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to employees" ON employees FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to items" ON items FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to sales" ON sales FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to sale_items" ON sale_items FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to receivings" ON receivings FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to receiving_items" ON receiving_items FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to customers" ON customers FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to credits" ON credits FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to credit_payments" ON credit_payments FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to meter_readings" ON meter_readings FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Allow service role full access to audit_logs" ON audit_logs FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ============================================================================
-- 6. GRANT PERMISSIONS
-- ============================================================================

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;

GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- ============================================================================
-- 7. TRIGGERS
-- ============================================================================

DROP TRIGGER IF EXISTS update_items_updated_at ON items;
CREATE TRIGGER update_items_updated_at
    BEFORE UPDATE ON items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_employees_updated_at ON employees;
CREATE TRIGGER update_employees_updated_at
    BEFORE UPDATE ON employees
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SCRIPT COMPLETE
-- ============================================================================
SELECT 'Master schema updated and permissions fixed' as status;

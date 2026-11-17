-- ============================================================================
-- LUCASA POS - SUPABASE POSTGRESQL SCHEMA
-- ============================================================================
-- This schema mirrors the local SQLite database structure for cloud backup
-- Run this SQL in your Supabase SQL Editor to set up the cloud database
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- LOCATIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS locations (
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

-- ============================================================================
-- EMPLOYEES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS employees (
  id TEXT PRIMARY KEY,
  location_id TEXT, -- No FK constraint: admins store multiple locations as JSON array e.g. '["loc_1","loc_2"]'
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
  synced_at TIMESTAMPTZ
);

CREATE INDEX idx_employees_username ON employees(username);
CREATE INDEX idx_employees_location ON employees(location_id);
CREATE INDEX idx_employees_role ON employees(role);

-- ============================================================================
-- ITEMS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS items (
  id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(id),
  category TEXT DEFAULT 'Filling Station',
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

CREATE INDEX idx_items_location ON items(location_id);
CREATE INDEX idx_items_barcode ON items(barcode);
CREATE INDEX idx_items_name ON items(name);

-- ============================================================================
-- SALES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS sales (
  id TEXT PRIMARY KEY,
  sale_id TEXT UNIQUE NOT NULL,
  location_id TEXT NOT NULL REFERENCES locations(id),
  employee_id TEXT NOT NULL REFERENCES employees(id),
  payment_method TEXT NOT NULL CHECK (payment_method IN ('Cash', 'Mpesa Till', 'Equity Paybill', 'Credit')),
  total_amount DECIMAL(10,2) NOT NULL,
  amount_paid DECIMAL(10,2) NOT NULL,
  change_given DECIMAL(10,2) DEFAULT 0,
  profit DECIMAL(10,2) DEFAULT 0,
  is_suspended BOOLEAN DEFAULT FALSE,
  suspension_notes TEXT,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

CREATE INDEX idx_sales_location ON sales(location_id);
CREATE INDEX idx_sales_employee ON sales(employee_id);
CREATE INDEX idx_sales_timestamp ON sales(timestamp);
CREATE INDEX idx_sales_suspended ON sales(is_suspended);

-- ============================================================================
-- SALE ITEMS TABLE
-- ============================================================================

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
  synced_at TIMESTAMPTZ
);

CREATE INDEX idx_sale_items_sale ON sale_items(sale_id);

-- ============================================================================
-- RECEIVINGS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS receivings (
  id TEXT PRIMARY KEY,
  receiving_id TEXT UNIQUE NOT NULL,
  location_id TEXT NOT NULL REFERENCES locations(id),
  employee_id TEXT NOT NULL REFERENCES employees(id),
  total_amount DECIMAL(10,2) NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

CREATE INDEX idx_receivings_location ON receivings(location_id);
CREATE INDEX idx_receivings_timestamp ON receivings(timestamp);

-- ============================================================================
-- RECEIVING ITEMS TABLE
-- ============================================================================

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

CREATE INDEX idx_receiving_items_receiving ON receiving_items(receiving_id);

-- ============================================================================
-- CUSTOMERS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(id),
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

CREATE INDEX idx_customers_location ON customers(location_id);
CREATE INDEX idx_customers_phone ON customers(phone);

-- ============================================================================
-- CREDITS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS credits (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL REFERENCES customers(id),
  sale_id TEXT NOT NULL REFERENCES sales(id),
  location_id TEXT NOT NULL REFERENCES locations(id),
  total_owed DECIMAL(10,2) NOT NULL,
  amount_paid DECIMAL(10,2) DEFAULT 0,
  balance DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_payment_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ
);

CREATE INDEX idx_credits_customer ON credits(customer_id);
CREATE INDEX idx_credits_location ON credits(location_id);
CREATE INDEX idx_credits_balance ON credits(balance);

-- ============================================================================
-- CREDIT PAYMENTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS credit_payments (
  id TEXT PRIMARY KEY,
  credit_id TEXT NOT NULL REFERENCES credits(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  paid_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

CREATE INDEX idx_credit_payments_credit ON credit_payments(credit_id);

-- ============================================================================
-- METER READINGS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS meter_readings (
  id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(id),
  employee_id TEXT NOT NULL REFERENCES employees(id),
  reading_type TEXT NOT NULL CHECK (reading_type IN ('opening', 'closing')),
  pump_type TEXT NOT NULL CHECK (pump_type IN ('AGO', 'PMS')),
  pump_number INTEGER NOT NULL,
  value_a DECIMAL(10,2) NOT NULL,
  value_l DECIMAL(10,2) NOT NULL,
  value_t DECIMAL(10,2) NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

CREATE INDEX idx_meter_readings_location ON meter_readings(location_id);
CREATE INDEX idx_meter_readings_employee ON meter_readings(employee_id);
CREATE INDEX idx_meter_readings_timestamp ON meter_readings(timestamp);

-- ============================================================================
-- AUDIT LOGS TABLE
-- ============================================================================

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

CREATE INDEX idx_audit_logs_location ON audit_logs(location_id);
CREATE INDEX idx_audit_logs_employee ON audit_logs(employee_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action_type);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================
-- NOTE: Since the app uses custom authentication (not Supabase Auth),
-- RLS policies are configured to allow full access to the service role key.
-- Security is handled at the application level.
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

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "employees_own_location_sales" ON sales;
DROP POLICY IF EXISTS "employees_own_location_items" ON items;
DROP POLICY IF EXISTS "authenticated_access_locations" ON locations;
DROP POLICY IF EXISTS "authenticated_access_employees" ON employees;
DROP POLICY IF EXISTS "authenticated_access_items" ON items;
DROP POLICY IF EXISTS "authenticated_access_sales" ON sales;
DROP POLICY IF EXISTS "authenticated_access_sale_items" ON sale_items;
DROP POLICY IF EXISTS "authenticated_access_receivings" ON receivings;
DROP POLICY IF EXISTS "authenticated_access_receiving_items" ON receiving_items;
DROP POLICY IF EXISTS "authenticated_access_customers" ON customers;
DROP POLICY IF EXISTS "authenticated_access_credits" ON credits;
DROP POLICY IF EXISTS "authenticated_access_credit_payments" ON credit_payments;
DROP POLICY IF EXISTS "authenticated_access_meter_readings" ON meter_readings;
DROP POLICY IF EXISTS "authenticated_access_audit_logs" ON audit_logs;

-- Allow all operations for service role (used by the app)
-- The app uses its own authentication system, so security is enforced at the app level

CREATE POLICY "Allow service role full access to locations"
  ON locations FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to employees"
  ON employees FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to items"
  ON items FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to sales"
  ON sales FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to sale_items"
  ON sale_items FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to receivings"
  ON receivings FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to receiving_items"
  ON receiving_items FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to customers"
  ON customers FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to credits"
  ON credits FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to credit_payments"
  ON credit_payments FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to meter_readings"
  ON meter_readings FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role full access to audit_logs"
  ON audit_logs FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_items_updated_at
    BEFORE UPDATE ON items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- INITIAL DATA SETUP
-- ============================================================================

-- You can add initial location data here if needed
-- Example:
-- INSERT INTO locations (id, name, address) 
-- VALUES ('LOC1', 'Main Branch', '123 Main Street')
-- ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- STORAGE POLICIES
-- ============================================================================

-- Configure storage policies for buckets
-- Note: You need to create these buckets in Supabase Dashboard > Storage first

-- Allow authenticated access to storage objects
-- Run these after creating the buckets in Supabase Dashboard

-- For config-files bucket (logos)
-- CREATE POLICY "Allow authenticated upload to config-files"
--   ON storage.objects FOR INSERT
--   TO authenticated
--   WITH CHECK (bucket_id = 'config-files');
-- 
-- CREATE POLICY "Allow public read from config-files"
--   ON storage.objects FOR SELECT
--   TO public
--   USING (bucket_id = 'config-files');

-- For receipts bucket
-- CREATE POLICY "Allow authenticated upload to receipts"
--   ON storage.objects FOR INSERT
--   TO authenticated
--   WITH CHECK (bucket_id = 'receipts');
-- 
-- CREATE POLICY "Allow public read from receipts"
--   ON storage.objects FOR SELECT
--   TO public
--   USING (bucket_id = 'receipts');

-- ============================================================================
-- NOTES
-- ============================================================================

-- 1. Run this script in Supabase SQL Editor
-- 2. Make sure to use your service_role key (not anon key) in the app for bypass RLS
--    OR ensure you're connecting with a valid authenticated session
-- 3. Create storage buckets manually in Supabase Storage:
--    - config-files (for shop logos) - set to public
--    - receipts (for receipt PDFs) - set to public  
-- 4. Uncomment and run the storage policies above after creating buckets
-- 5. The app will automatically sync data to these tables
-- 6. Use Supabase Dashboard to view and manage data
-- 7. Security is enforced at the application level through permissions system

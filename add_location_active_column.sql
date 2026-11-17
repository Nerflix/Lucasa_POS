-- Add is_active column to locations table
ALTER TABLE locations ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

-- Update existing locations to be active (if not already set)
UPDATE locations SET is_active = TRUE WHERE is_active IS NULL;

-- Note: No changes needed to employees table as it already has is_active.

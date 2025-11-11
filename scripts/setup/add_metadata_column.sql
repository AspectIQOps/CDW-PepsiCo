-- Add metadata column to applications_dim if it doesn't exist
-- This stores additional JSON data from AppDynamics like tier count, node count, description

DO $$
BEGIN
    -- Check if metadata column exists
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'applications_dim' 
        AND column_name = 'metadata'
    ) THEN
        -- Add the column
        ALTER TABLE applications_dim 
        ADD COLUMN metadata JSONB DEFAULT '{}'::jsonb;
        
        RAISE NOTICE 'Added metadata column to applications_dim';
    ELSE
        RAISE NOTICE 'metadata column already exists in applications_dim';
    END IF;
END $$;
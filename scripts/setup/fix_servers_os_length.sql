-- ========================================
-- Fix servers_dim schema for long OS names
-- Run this TODAY before next ETL run
-- ========================================

-- HOW TO RUN:
-- Method 1 (Interactive):
--   cd ~/CDW-PepsiCo/scripts/utils
--   ./platform_manager.sh db
--   Then paste this SQL and hit Enter
--
-- Method 2 (File):
--   Save this as sql/migrations/fix_servers_os_length.sql
--   Then run: ./platform_manager.sh db < ../../sql/migrations/fix_servers_os_length.sql
--
-- Method 3 (Direct):
--   See instructions in artifact description

BEGIN;

-- Increase os column length from 100 to 255 characters
ALTER TABLE servers_dim 
ALTER COLUMN os TYPE VARCHAR(255);

-- Also fix ip_address while we're at it (some IPs have CIDR notation)
ALTER TABLE servers_dim
ALTER COLUMN ip_address TYPE VARCHAR(100);

-- Verify the changes
SELECT column_name, data_type, character_maximum_length
FROM information_schema.columns
WHERE table_name = 'servers_dim' AND column_name IN ('os', 'ip_address')
ORDER BY column_name;

COMMIT;

-- Success message
DO $
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✓ servers_dim schema updated:';
    RAISE NOTICE '  • os: VARCHAR(100) → VARCHAR(255)';
    RAISE NOTICE '  • ip_address: VARCHAR(50) → VARCHAR(100)';
    RAISE NOTICE '========================================';
END
$;
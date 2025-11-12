-- Migration: Add multi-controller support to applications_dim
-- Date: 2025-11-12
-- Description: Adds appd_controller field to track which controller each application belongs to

-- Add controller column
ALTER TABLE applications_dim ADD COLUMN IF NOT EXISTS appd_controller VARCHAR(255);

-- Drop old unique constraint on appd_application_id
ALTER TABLE applications_dim DROP CONSTRAINT IF EXISTS applications_dim_appd_application_id_key;

-- Add new composite unique constraint (app_id + controller)
ALTER TABLE applications_dim ADD CONSTRAINT applications_dim_appd_id_controller_key
    UNIQUE (appd_application_id, appd_controller);

-- Add index on controller for performance
CREATE INDEX IF NOT EXISTS idx_apps_controller ON applications_dim(appd_controller);

-- Add comment
COMMENT ON COLUMN applications_dim.appd_controller IS 'AppDynamics controller hostname for multi-controller support';

-- Update existing records to have a default controller value (if any exist)
-- This should be updated to the actual primary controller hostname
UPDATE applications_dim
SET appd_controller = 'primary-controller'
WHERE appd_controller IS NULL AND appd_application_id IS NOT NULL;

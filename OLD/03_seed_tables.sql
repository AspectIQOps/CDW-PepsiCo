-- 03_seed_tables.sql
-- Creates the mock data generation function and populates the usage_fact table.

-- Set configuration for transaction safety
SET application_name TO 'init_script_03';

-- ===============================================
-- 1. Mock Data Generation Function
-- ===============================================

-- Drop function if it exists to allow re-creation
DROP FUNCTION IF EXISTS generate_mock_license_data(integer);

-- Function to generate mock data for the usage_fact table
CREATE OR REPLACE FUNCTION generate_mock_license_data(num_rows INT)
RETURNS TABLE (
    application_key INT,
    owner_key INT,
    capability_key INT,
    units_used BIGINT,
    load_time TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        (random() * 4 + 1)::INT AS application_key,   -- Random key between 1 and 5
        (random() * 2 + 1)::INT AS owner_key,           -- Random key between 1 and 3
        (random() * 5 + 1)::INT AS capability_key,      -- Random key between 1 and 6
        (random() * 1000 + 100)::BIGINT AS units_used,  -- Random usage units
        NOW() - ('1 day'::interval * (random() * 90)::INT) AS load_time -- Random load time over last 90 days
    FROM generate_series(1, num_rows);
END;
$$;


-- ===============================================
-- 2. Populate usage_fact table
-- ===============================================

INSERT INTO usage_fact (
    application_key,
    owner_key,
    capability_key,
    units_used,
    load_time
)
SELECT
    t.application_key,
    t.owner_key,
    t.capability_key,
    t.units_used,
    t.load_time
FROM
    generate_mock_license_data(250) AS t; -- Generate 250 rows of mock data

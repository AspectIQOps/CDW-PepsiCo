-- 04_create_views.sql
-- Creates the final materialized view for the license chargeback report.

-- Drop the view if it exists
DROP VIEW IF EXISTS license_chargeback_report;

-- Create the main reporting view
CREATE VIEW license_chargeback_report AS
SELECT
    f.load_time,
    a.application_name,
    a.current_architecture_type,
    a.h_code,
    o.owner_name,
    o.sector,
    c.capability_name,
    c.license_type,
    f.units_used,
    p.unit_price,
    (f.units_used * p.unit_price) AS calculated_chargeback_cost,
    f.usage_id
FROM
    usage_fact f
JOIN
    applications_dim a ON f.application_key = a.application_key
JOIN
    owners_dim o ON f.owner_key = o.owner_key
JOIN
    capabilities_dim c ON f.capability_key = c.capability_key
LEFT JOIN
    -- Use LEFT JOIN in case a usage record exists without a price configured yet
    price_config p ON f.capability_key = p.capability_key
ORDER BY
    f.load_time DESC;

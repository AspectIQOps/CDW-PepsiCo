-- 01_seed_dimensions.sql
-- Seed dimension tables with default/required data BEFORE applications_dim is populated
-- This must run AFTER 02_create_tables.sql (alphabetically comes first in docker-entrypoint-initdb.d)

-- ============================================
-- Seed Owners Dimension with defaults
-- ============================================
INSERT INTO owners_dim (owner_name, organizational_hierarchy, email) VALUES
    ('Unassigned', 'PepsiCo/Unassigned', 'unassigned@pepsico.com'),
    ('IT Infrastructure', 'PepsiCo/Global IT/Infrastructure', 'it-infra@pepsico.com'),
    ('Application Services', 'PepsiCo/Global IT/Application Services', 'app-services@pepsico.com')
ON CONFLICT DO NOTHING;

-- ============================================
-- Seed Sectors Dimension with defaults
-- ============================================
INSERT INTO sectors_dim (sector_name) VALUES
    ('Unassigned'),
    ('Beverages North America'),
    ('Frito-Lay North America'),
    ('Quaker Foods North America'),
    ('Latin America'),
    ('Europe'),
    ('Africa, Middle East and South Asia'),
    ('Asia Pacific, Australia and New Zealand and China Region'),
    ('Corporate/Shared Services')
ON CONFLICT (sector_name) DO NOTHING;

-- ============================================
-- Seed Architecture Dimension
-- ============================================
INSERT INTO architecture_dim (pattern_name, description) VALUES
    ('Unknown', 'Architecture pattern not yet classified'),
    ('Monolith', 'Traditional monolithic application architecture'),
    ('Microservices', 'Microservices-based architecture'),
    ('Hybrid', 'Mix of monolithic and microservices patterns'),
    ('Serverless', 'Serverless/Function-as-a-Service architecture')
ON CONFLICT (pattern_name) DO NOTHING;

-- ============================================
-- Seed Capabilities Dimension (License Types)
-- ============================================
INSERT INTO capabilities_dim (capability_code, description) VALUES
    ('APM', 'Application Performance Monitoring'),
    ('MRUM', 'Mobile Real User Monitoring'),
    ('BRUM', 'Browser Real User Monitoring'),
    ('SYN', 'Synthetic Monitoring'),
    ('DB', 'Database Monitoring')
ON CONFLICT (capability_code) DO NOTHING;

-- ============================================
-- Seed Time Dimension (Next 36 months daily)
-- ============================================
INSERT INTO time_dim (ts, year, month, day, yyyy_mm)
SELECT 
    ts,
    EXTRACT(YEAR FROM ts)::INT,
    EXTRACT(MONTH FROM ts)::INT,
    EXTRACT(DAY FROM ts)::INT,
    TO_CHAR(ts, 'YYYY-MM')
FROM generate_series(
    DATE_TRUNC('day', NOW() - INTERVAL '12 months')::TIMESTAMP,
    DATE_TRUNC('day', NOW() + INTERVAL '36 months')::TIMESTAMP,
    INTERVAL '1 day'
) AS ts
ON CONFLICT (ts) DO NOTHING;

-- ============================================
-- Seed Price Configuration (Example rates)
-- ============================================
INSERT INTO price_config (capability_id, tier, start_date, end_date, unit_rate, contract_renewal_date)
SELECT 
    c.capability_id,
    tier.tier_name,
    NOW()::DATE - INTERVAL '1 year',
    NOW()::DATE + INTERVAL '1 year',
    CASE 
        WHEN c.capability_code = 'APM' AND tier.tier_name = 'Peak' THEN 0.50
        WHEN c.capability_code = 'APM' AND tier.tier_name = 'Pro' THEN 0.30
        WHEN c.capability_code IN ('MRUM', 'BRUM') AND tier.tier_name = 'Peak' THEN 0.40
        WHEN c.capability_code IN ('MRUM', 'BRUM') AND tier.tier_name = 'Pro' THEN 0.25
        WHEN c.capability_code = 'SYN' AND tier.tier_name = 'Peak' THEN 0.60
        WHEN c.capability_code = 'SYN' AND tier.tier_name = 'Pro' THEN 0.35
        WHEN c.capability_code = 'DB' AND tier.tier_name = 'Peak' THEN 0.45
        WHEN c.capability_code = 'DB' AND tier.tier_name = 'Pro' THEN 0.28
        ELSE 0.20
    END,
    NOW()::DATE + INTERVAL '11 months'
FROM capabilities_dim c
CROSS JOIN (VALUES ('Peak'), ('Pro')) AS tier(tier_name);

-- ============================================
-- Verification Queries (Helpful for debugging)
-- ============================================
DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Dimension Tables Seeded Successfully';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Owners: % rows', (SELECT COUNT(*) FROM owners_dim);
    RAISE NOTICE 'Sectors: % rows', (SELECT COUNT(*) FROM sectors_dim);
    RAISE NOTICE 'Architectures: % rows', (SELECT COUNT(*) FROM architecture_dim);
    RAISE NOTICE 'Capabilities: % rows', (SELECT COUNT(*) FROM capabilities_dim);
    RAISE NOTICE 'Time dimension: % rows', (SELECT COUNT(*) FROM time_dim);
    RAISE NOTICE 'Price configs: % rows', (SELECT COUNT(*) FROM price_config);
    RAISE NOTICE '==============================================';
END $$;
-- ============================================================
-- PepsiCo AppDynamics Licensing Dimension Seed Data
-- Idempotent (safe to re-run with ON CONFLICT)
-- ============================================================

-- ============================================================
-- OWNERS DIMENSION
-- ============================================================
INSERT INTO owners_dim (owner_name, organizational_hierarchy, email) VALUES
    ('Unassigned', 'PepsiCo/Unassigned', 'unassigned@pepsico.com'),
    ('IT Infrastructure', 'PepsiCo/Global IT/Infrastructure', 'it-infra@pepsico.com'),
    ('Application Services', 'PepsiCo/Global IT/Application Services', 'app-services@pepsico.com'),
    ('Digital Technology', 'PepsiCo/Global IT/Digital Technology', 'digital-tech@pepsico.com')
ON CONFLICT (owner_name) DO UPDATE SET
    organizational_hierarchy = EXCLUDED.organizational_hierarchy,
    email = EXCLUDED.email,
    updated_at = NOW();

-- ============================================================
-- SECTORS DIMENSION
-- ============================================================
INSERT INTO sectors_dim (sector_name) VALUES
    ('Unassigned'),
    ('Beverages North America'),
    ('Frito-Lay North America'),
    ('Quaker Foods North America'),
    ('Latin America'),
    ('Europe'),
    ('Africa, Middle East and South Asia'),
    ('Asia Pacific, Australia and New Zealand and China Region'),
    ('Corporate/Shared Services'),
    ('Global IT'),
    ('Supply Chain'),
    ('Human Resources'),
    ('Finance')
ON CONFLICT (sector_name) DO NOTHING;

-- ============================================================
-- ARCHITECTURE DIMENSION
-- ============================================================
INSERT INTO architecture_dim (pattern_name, description) VALUES
    ('Unknown', 'Architecture pattern not yet classified'),
    ('Monolith', 'Traditional monolithic application architecture'),
    ('Microservices', 'Microservices-based architecture'),
    ('Hybrid', 'Mix of monolithic and microservices patterns'),
    ('Serverless', 'Serverless/Function-as-a-Service architecture'),
    ('Legacy', 'Legacy system or mainframe'),
    ('SaaS', 'Software-as-a-Service (external)')
ON CONFLICT (pattern_name) DO UPDATE SET
    description = EXCLUDED.description;

-- ============================================================
-- CAPABILITIES DIMENSION
-- ============================================================
INSERT INTO capabilities_dim (capability_code, description) VALUES
    ('APM', 'Application Performance Monitoring'),
    ('MRUM', 'Mobile Real User Monitoring'),
    ('BRUM', 'Browser Real User Monitoring'),
    ('SYN', 'Synthetic Monitoring'),
    ('DB', 'Database Monitoring'),
    ('INFRA', 'Infrastructure Monitoring'),
    ('BIZ', 'Business iQ / Analytics')
ON CONFLICT (capability_code) DO UPDATE SET
    description = EXCLUDED.description;

-- ============================================================
-- TIME DIMENSION (48 months: -12 months to +36 months)
-- ============================================================
INSERT INTO time_dim (ts, year, month, day, day_name, month_name, quarter, yyyy_mm)
SELECT 
    ts,
    EXTRACT(YEAR FROM ts)::INT,
    EXTRACT(MONTH FROM ts)::INT,
    EXTRACT(DAY FROM ts)::INT,
    TO_CHAR(ts, 'Day'),
    TO_CHAR(ts, 'Month'),
    'Q' || EXTRACT(QUARTER FROM ts)::TEXT,
    TO_CHAR(ts, 'YYYY-MM')
FROM generate_series(
    DATE_TRUNC('day', NOW() - INTERVAL '12 months')::TIMESTAMP,
    DATE_TRUNC('day', NOW() + INTERVAL '36 months')::TIMESTAMP,
    INTERVAL '1 day'
) AS ts
ON CONFLICT (ts) DO NOTHING;

-- ============================================================
-- PRICE CONFIGURATION (Example rates - adjust per contract)
-- ============================================================
INSERT INTO price_config (capability_id, tier, start_date, end_date, unit_rate, contract_renewal_date)
SELECT 
    c.capability_id,
    tier.tier_name,
    NOW()::DATE - INTERVAL '1 year',
    NOW()::DATE + INTERVAL '1 year',
    CASE 
        -- APM Pricing
        WHEN c.capability_code = 'APM' AND tier.tier_name = 'PEAK' THEN 0.75
        WHEN c.capability_code = 'APM' AND tier.tier_name = 'PRO' THEN 0.50
        -- RUM Pricing
        WHEN c.capability_code IN ('MRUM', 'BRUM') AND tier.tier_name = 'PEAK' THEN 0.60
        WHEN c.capability_code IN ('MRUM', 'BRUM') AND tier.tier_name = 'PRO' THEN 0.40
        -- Synthetic Pricing
        WHEN c.capability_code = 'SYN' AND tier.tier_name = 'PEAK' THEN 0.80
        WHEN c.capability_code = 'SYN' AND tier.tier_name = 'PRO' THEN 0.55
        -- Database Monitoring
        WHEN c.capability_code = 'DB' AND tier.tier_name = 'PEAK' THEN 0.70
        WHEN c.capability_code = 'DB' AND tier.tier_name = 'PRO' THEN 0.45
        -- Infrastructure Monitoring
        WHEN c.capability_code = 'INFRA' AND tier.tier_name = 'PEAK' THEN 0.40
        WHEN c.capability_code = 'INFRA' AND tier.tier_name = 'PRO' THEN 0.25
        -- Business iQ
        WHEN c.capability_code = 'BIZ' AND tier.tier_name = 'PEAK' THEN 1.00
        WHEN c.capability_code = 'BIZ' AND tier.tier_name = 'PRO' THEN 0.70
        ELSE 0.30
    END,
    NOW()::DATE + INTERVAL '11 months'
FROM capabilities_dim c
CROSS JOIN (VALUES ('PEAK'), ('PRO')) AS tier(tier_name);

-- ============================================================
-- VERIFICATION
-- ============================================================
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
    RAISE NOTICE 'Database ready for ETL operations';
    RAISE NOTICE '==============================================';
END $$;
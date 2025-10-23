-- =====================================================
-- Init script for appd_licensing database
-- =====================================================

-- Use the public schema
CREATE SCHEMA IF NOT EXISTS public;

-- ------------------------
-- Table: capabilities_dim
-- ------------------------
CREATE TABLE IF NOT EXISTS capabilities_dim (
    capability_code TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

-- Seed capabilities
INSERT INTO capabilities_dim (capability_code, description) VALUES
('APM','Application Performance Monitoring'),
('MRUM','Mobile Real User Monitoring'),
('BRUM','Browser Real User Monitoring'),
('SYN','Synthetic Monitoring'),
('DB','Database Monitoring')
ON CONFLICT (capability_code) DO NOTHING;

-- ------------------------
-- Table: time_dim
-- ------------------------
CREATE TABLE IF NOT EXISTS time_dim (
    ts TIMESTAMPTZ PRIMARY KEY,
    y INT NOT NULL,
    m INT NOT NULL,
    d INT NOT NULL,
    yyyy_mm TEXT NOT NULL
);

-- Seed time dimension for 2 years
WITH t AS (
    SELECT generate_series(
        date_trunc('day', now())::timestamptz,
        (now() + interval '730 days')::date,
        interval '1 day'
    ) AS ts
)
INSERT INTO time_dim (ts, y, m, d, yyyy_mm)
SELECT ts,
       EXTRACT(YEAR FROM ts)::int,
       EXTRACT(MONTH FROM ts)::int,
       EXTRACT(DAY FROM ts)::int,
       TO_CHAR(ts,'YYYY-MM')
FROM t
ON CONFLICT (ts) DO NOTHING;

-- ------------------------
-- Table: price_config
-- ------------------------
CREATE TABLE IF NOT EXISTS price_config (
    capability_code TEXT NOT NULL,
    tier TEXT NOT NULL DEFAULT 'DEFAULT',
    usd_per_unit NUMERIC NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE NOT NULL,
    PRIMARY KEY (capability_code, tier)
);

-- Seed price config
INSERT INTO price_config (capability_code, tier, usd_per_unit, effective_from, effective_to) VALUES
('APM','PRO',  0, '2025-01-01','2099-12-31'),
('APM','PEAK', 0, '2025-01-01','2099-12-31'),
('MRUM','DEFAULT',  0, '2025-01-01','2099-12-31'),
('BRUM','DEFAULT',  0, '2025-01-01','2099-12-31'),
('SYN','DEFAULT',  0, '2025-01-01','2099-12-31'),
('DB','DEFAULT',  0, '2025-01-01','2099-12-31')
ON CONFLICT (capability_code, tier) DO NOTHING;

-- ------------------------
-- Table: applications_dim
-- ------------------------
CREATE TABLE IF NOT EXISTS applications_dim (
    appd_application_name TEXT NOT NULL,
    sn_sys_id TEXT PRIMARY KEY,
    sn_service_name TEXT,
    h_code TEXT,
    sector TEXT
);

-- Optional: initial seed (empty placeholder, ETL will populate)
-- INSERT INTO applications_dim (appd_application_name, sn_sys_id, sn_service_name, h_code, sector)
-- VALUES (...);

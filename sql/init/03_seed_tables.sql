-- 03_seed_tables.sql
-- Seed Data Script (Updated for Comprehensive Schema and Foreign Key Handling)
-- --------------------------------------------------------------------------------

-- 1. TRUNCATE: Truncate all application tables to ensure clean restart
TRUNCATE TABLE
  license_usage_fact,
  license_cost_fact,
  chargeback_fact,
  forecast_fact,
  data_lineage,
  etl_execution_log,
  reconciliation_log,
  user_actions,
  mapping_overrides,
  price_config,
  allocation_rules,
  applications_dim,
  owners_dim,
  sectors_dim,
  architecture_dim,
  capabilities_dim,
  time_dim
RESTART IDENTITY CASCADE; -- CASCADE ensures dependent tables are truncated.

-- ----------------------------------------------------
-- 2. SEED DIMENSION TABLES
-- ----------------------------------------------------

-- Seed Capabilities
INSERT INTO capabilities_dim (capability_code, description)
VALUES
  ('APM','Application Performance Monitoring'),
  ('MRUM','Mobile Real User Monitoring'),
  ('BRUM','Browser Real User Monitoring'),
  ('SYN','Synthetics'),
  ('DB','Database Monitoring');

-- Seed Sectors (used by applications_dim and chargeback_fact)
INSERT INTO sectors_dim (sector_name)
VALUES
  ('Beverages North America'),
  ('Frito Lay'),
  ('Global Snacks Group'),
  ('Global IT'),
  ('Latin America');

-- Seed Owners
INSERT INTO owners_dim (owner_name, organizational_hierarchy, email)
VALUES
  ('Sarah Connor', 'Global IT/Apps', 'sarah.connor@pepsico.com'),
  ('John Smith', 'Frito Lay/Operations', 'john.smith@pepsico.com'),
  ('Jane Doe', 'Beverages NA/Digital', 'jane.doe@pepsico.com');

-- Seed Architecture Patterns
INSERT INTO architecture_dim (pattern_name, description)
VALUES
  ('Monolith', 'Large, single-tier application'),
  ('Microservices', 'Distributed service architecture'),
  ('Serverless', 'Function-as-a-Service');

-- Seed Time Dimension (next 24 months daily)
WITH t AS (
  SELECT generate_series(
    date_trunc('day', now())::timestamptz,
    (now() + interval '730 days')::date,
    interval '1 day'
  ) AS ts
)
INSERT INTO time_dim (ts, year, month, day, yyyy_mm)
SELECT ts,
       extract(year from ts)::int,
       extract(month from ts)::int,
       extract(day from ts)::int,
       to_char(ts,'YYYY-MM')
FROM t
ON CONFLICT (ts) DO NOTHING;


-- Seed Applications (linking to new dimensions)
INSERT INTO applications_dim (
    appd_application_id, appd_application_name, sn_sys_id, sn_service_name,
    owner_id, sector_id, architecture_id, h_code, is_critical, support_group
)
SELECT i, 'App_' || i, md5(random()::text), 'Service_' || i,
       (SELECT owner_id FROM owners_dim ORDER BY random() LIMIT 1),
       (SELECT sector_id FROM sectors_dim ORDER BY random() LIMIT 1),
       (SELECT architecture_id FROM architecture_dim ORDER BY random() LIMIT 1),
       'H' || LPAD(i::text, 3, '0'), -- Generates H001, H002, etc.
       CASE WHEN i % 5 = 0 THEN TRUE ELSE FALSE END,
       'Level3_' || i
FROM generate_series(1, 20) AS s(i);

-- Seed Price Config (Example Rates)
INSERT INTO price_config (capability_id, tier, start_date, unit_rate, contract_renewal_date)
VALUES
    ((SELECT capability_id FROM capabilities_dim WHERE capability_code = 'APM'), 'PRO', '2024-01-01', 0.50, '2025-12-31'),
    ((SELECT capability_id FROM capabilities_dim WHERE capability_code = 'APM'), 'PEAK', '2024-01-01', 0.75, '2025-12-31');

-- ----------------------------------------------------
-- 3. SEED FACT TABLES (Using new FKs)
-- ----------------------------------------------------

-- Seed License Usage Fact
INSERT INTO license_usage_fact (ts, app_id, capability_id, tier, units_consumed, nodes_count, servers_count)
SELECT t.ts,
       a.app_id,
       c.capability_id,
       pc.tier,
       ROUND((random() * 100 + 5)::numeric, 2), -- units between 5 and 105
       (random()*10)::int + 1,
       (random()*5)::int + 1
FROM time_dim t
CROSS JOIN applications_dim a
CROSS JOIN capabilities_dim c
CROSS JOIN price_config pc
WHERE pc.capability_id = c.capability_id
  AND t.ts > now() - interval '90 days' -- Only seed recent usage for speed
LIMIT 500;

-- Seed License Cost Fact
INSERT INTO license_cost_fact (ts, app_id, capability_id, tier, usd_cost, price_id)
SELECT lu.ts,
       lu.app_id,
       lu.capability_id,
       lu.tier,
       ROUND((lu.units_consumed * pc.unit_rate)::numeric, 2),
       pc.price_id
FROM license_usage_fact lu
JOIN price_config pc ON pc.capability_id = lu.capability_id AND pc.tier = lu.tier;

-- Seed Chargeback Fact (Monthly Aggregation)
INSERT INTO chargeback_fact (month_start, app_id, h_code, sector_id, owner_id, usd_amount, chargeback_cycle, is_finalized)
SELECT date_trunc('month', ts)::date,
       a.app_id,
       a.h_code,
       a.sector_id,
       a.owner_id,
       SUM(lc.usd_cost),
       'Monthly',
       FALSE
FROM license_cost_fact lc
JOIN applications_dim a ON a.app_id = lc.app_id
GROUP BY 1,2,3,4,5
LIMIT 50;

-- Seed Forecast Fact (Simple projection of last month)
INSERT INTO forecast_fact (month_start, app_id, capability_id, tier, projected_units, projected_cost, method)
WITH last_month AS (
  SELECT app_id, capability_id, tier, SUM(units_consumed) AS units, SUM(usd_cost) AS cost
  FROM license_usage_fact
  WHERE ts >= date_trunc('month', now() - interval '1 month')
    AND ts < date_trunc('month', now())
  GROUP BY 1,2,3,4
)
SELECT date_trunc('month', now() + interval '1 month')::date,
       app_id,
       capability_id,
       tier,
       ROUND((units * 1.15)::numeric,2), -- 15% projected growth
       ROUND((cost * 1.15)::numeric,2),
       'Simple Growth'
FROM last_month;

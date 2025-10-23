-- Seed Capabilities
TRUNCATE TABLE capabilities_dim RESTART IDENTITY;
INSERT INTO capabilities_dim (capability_code, description)
VALUES
  ('APM','Application Performance Monitoring'),
  ('MRUM','Mobile Real User Monitoring'),
  ('BRUM','Browser Real User Monitoring'),
  ('SYN','Synthetics'),
  ('DB','Database Monitoring');

-- Seed Time Dimension (next 24 months daily)
TRUNCATE TABLE time_dim RESTART IDENTITY;
WITH t AS (
  SELECT generate_series(
    date_trunc('day', now())::timestamptz,
    (now() + interval '730 days')::date,
    interval '1 day'
  ) AS ts
)
INSERT INTO time_dim (ts, y, m, d, yyyy_mm)
SELECT ts,
       extract(year from ts)::int,
       extract(month from ts)::int,
       extract(day from ts)::int,
       to_char(ts,'YYYY-MM')
FROM t
ON CONFLICT (ts) DO NOTHING;

-- Seed Applications (example data)
TRUNCATE TABLE applications_dim RESTART IDENTITY;
INSERT INTO applications_dim (appd_application_id, appd_application_name, sn_sys_id, sn_service_name, h_code, sector)
SELECT i, 'App_' || i, md5(random()::text), 'Service_' || i,
       CASE WHEN i % 2 = 0 THEN 'H001' ELSE 'H002' END,
       CASE WHEN i % 3 = 0 THEN 'Finance' ELSE 'Ops' END
FROM generate_series(1, 20) AS s(i);

-- Seed License Usage Fact
TRUNCATE TABLE license_usage_fact;
INSERT INTO license_usage_fact (ts, app_id, capability_id, tier, units, nodes)
SELECT t.ts,
       a.app_id,
       c.capability_id,
       CASE WHEN random() < 0.5 THEN 'PEAK' ELSE 'PRO' END,
       ROUND((random() * 100)::numeric, 2),
       (random()*10)::int
FROM time_dim t
CROSS JOIN applications_dim a
CROSS JOIN capabilities_dim c
LIMIT 150;

-- Seed License Cost Fact
TRUNCATE TABLE license_cost_fact;
INSERT INTO license_cost_fact (ts, app_id, capability_id, tier, usd_cost)
SELECT lu.ts,
       lu.app_id,
       lu.capability_id,
       lu.tier,
       ROUND((lu.units * (0.25 + random()*0.05))::numeric, 2)
FROM license_usage_fact lu;

-- Seed Chargeback Fact
TRUNCATE TABLE chargeback_fact;
INSERT INTO chargeback_fact (month_start, app_id, h_code, sector, usd_amount)
SELECT date_trunc('month', ts)::date,
       a.app_id,
       a.h_code,
       a.sector,
       SUM(lc.usd_cost)
FROM license_cost_fact lc
JOIN applications_dim a ON a.app_id = lc.app_id
GROUP BY 1,2,3,4
LIMIT 50;

-- Seed Forecast Fact (simple linear projection)
TRUNCATE TABLE forecast_fact;
INSERT INTO forecast_fact (month_start, app_id, capability_id, tier, projected_units, projected_cost, method)
WITH last_12 AS (
  SELECT date_trunc('month', ts)::date AS month_start, app_id, capability_id, tier, SUM(units) AS units
  FROM license_usage_fact
  WHERE ts >= now() - interval '12 months'
  GROUP BY 1,2,3,4
)
SELECT month_start + interval '1 month',
       app_id,
       capability_id,
       tier,
       ROUND((units * (1 + random()*0.1))::numeric,2),
       NULL,
       'linear'
FROM last_12
LIMIT 50;

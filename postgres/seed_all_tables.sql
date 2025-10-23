-- ============================================
-- Seed Data for AppD Licensing Demo
-- ============================================
\echo '🌱 Starting seed data insert...'

-- Clean up any previous data
TRUNCATE TABLE 
    license_usage_fact,
    license_cost_fact,
    chargeback_fact,
    forecast_fact,
    etl_execution_log,
    data_lineage,
    mapping_overrides,
    applications_dim,
    capabilities_dim,
    time_dim
RESTART IDENTITY CASCADE;

-- ============================================
-- 1. Capabilities Dimension
-- ============================================
INSERT INTO capabilities_dim (capability_code, description) VALUES
('APM', 'Application Performance Monitoring'),
('INFRA', 'Infrastructure Visibility'),
('DBMON', 'Database Monitoring'),
('BROWSER', 'Browser Real User Monitoring'),
('MOBILE', 'Mobile Real User Monitoring');

-- ============================================
-- 2. Applications Dimension
-- ============================================
INSERT INTO applications_dim (appd_application_id, appd_application_name, sn_sys_id, sn_service_name, h_code, sector) VALUES
(101, 'SAP Financial Accounting', '26e426be0a0a0bb40046890d90059eaa', 'SAP Financial Accounting', 'FIN-001', 'Finance'),
(102, 'SAP Enterprise Services', '26da329f0a0a0bb400f69d8159bc753d', 'SAP Enterprise Services', 'ENT-002', 'Finance'),
(201, 'PepsiCo eCommerce', '36aa12ff0a0a0bb4001ef9433f2a885e', 'Digital Storefront', 'ECOM-010', 'Sales'),
(301, 'Logistics Optimization Engine', '47ab334e0a0a0bb400acf9d903c7ffde', 'Logistics Optimization', 'LOG-020', 'Supply Chain'),
(401, 'Manufacturing Line Control', '58cb999e0a0a0bb400fd39f913b7ee42', 'Factory Operations', 'MFG-030', 'Manufacturing');

-- ============================================
-- 3. Time Dimension (Last 12 Months)
-- ============================================
DO $$
DECLARE
    d DATE := date_trunc('month', CURRENT_DATE) - INTERVAL '11 months';
BEGIN
    WHILE d <= CURRENT_DATE LOOP
        INSERT INTO time_dim (ts, y, m, d, yyyy_mm)
        VALUES (d, EXTRACT(YEAR FROM d), EXTRACT(MONTH FROM d), EXTRACT(DAY FROM d), TO_CHAR(d, 'YYYY-MM'));
        d := d + INTERVAL '1 month';
    END LOOP;
END $$;

-- ============================================
-- 4. License Usage Fact
-- ============================================
INSERT INTO license_usage_fact (ts, app_id, capability_id, tier, units, nodes)
SELECT
    t.ts,
    a.app_id,
    c.capability_id,
    CASE WHEN random() < 0.33 THEN 'PROD' WHEN random() < 0.66 THEN 'UAT' ELSE 'DEV' END,
    ROUND((random() * 500 + 100)::NUMERIC, 2),
    (random() * 20 + 3)::INT
FROM time_dim t
CROSS JOIN applications_dim a
CROSS JOIN capabilities_dim c
WHERE t.ts >= (CURRENT_DATE - INTERVAL '6 months');

-- ============================================
-- 5. License Cost Fact (simulate $ scaling with usage)
-- ============================================
INSERT INTO license_cost_fact (ts, app_id, capability_id, tier, usd_cost)
SELECT 
    u.ts,
    u.app_id,
    u.capability_id,
    u.tier,
    ROUND(u.units * (0.25 + random() * 0.05), 2)
FROM license_usage_fact u;

-- ============================================
-- 6. Chargeback Fact (monthly aggregates)
-- ============================================
INSERT INTO chargeback_fact (month_start, app_id, h_code, sector, usd_amount)
SELECT
    date_trunc('month', ts) AS month_start,
    a.app_id,
    a.h_code,
    a.sector,
    ROUND(SUM(l.usd_cost), 2)
FROM license_cost_fact l
JOIN applications_dim a USING (app_id)
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2;

-- ============================================
-- 7. Forecast Fact (simple linear projection)
-- ============================================
INSERT INTO forecast_fact (month_start, app_id, capability_id, tier, projected_units, projected_cost, method)
SELECT
    (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month') AS forecast_month,
    app_id,
    capability_id,
    tier,
    AVG(units) * 1.10, -- +10% growth projection
    AVG(units) * 1.10 * 0.30,
    'Linear +10%'
FROM license_usage_fact
GROUP BY app_id, capability_id, tier;

-- ============================================
-- 8. ETL Execution Log (recent successful runs)
-- ============================================
INSERT INTO etl_execution_log (job_name, started_at, finished_at, status, rows_ingested) VALUES
('appd_pull', now() - interval '2 days', now() - interval '2 days' + interval '15 minutes', 'SUCCESS', 520),
('snow_pull', now() - interval '2 days', now() - interval '2 days' + interval '12 minutes', 'SUCCESS', 78),
('license_rollup', now() - interval '1 day', now() - interval '1 day' + interval '10 minutes', 'SUCCESS', 600),
('chargeback_aggregate', now() - interval '1 day', now() - interval '1 day' + interval '8 minutes', 'SUCCESS', 120);

-- ============================================
-- 9. Data Lineage
-- ============================================
INSERT INTO data_lineage (run_id, source_system, source_endpoint, target_table, target_pk) VALUES
(1, 'AppDynamics', '/controller/api/licensing/usage', 'license_usage_fact', '{"ts": "2025-10-01T00:00:00Z"}'),
(2, 'ServiceNow', '/api/now/table/cmdb_ci_service', 'applications_dim', '{"sn_sys_id": "26e426be0a0a0bb40046890d90059eaa"}'),
(3, 'AppDynamics', '/controller/api/licensing/cost', 'license_cost_fact', '{"ts": "2025-10-01T00:00:00Z"}');

-- ============================================
-- 10. Mapping Overrides (example governance adjustments)
-- ============================================
INSERT INTO mapping_overrides (source, source_key, h_code_override, sector_override) VALUES
('ServiceNow', 'Digital Storefront', 'ECOM-999', 'Sales'),
('AppDynamics', 'SAP Enterprise Services', 'FIN-999', 'Finance');

\echo '✅ Seed data inserted successfully.'

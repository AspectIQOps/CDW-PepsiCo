-- ========================================
-- PERFORMANCE OPTIMIZATION - Phase 2
-- ========================================
-- Run AFTER 00_complete_init.sql
-- Creates materialized views + additional indexes
-- ========================================

-- ========================================
-- PART 1: ADDITIONAL PERFORMANCE INDEXES
-- ========================================

-- Composite indexes for time-series queries (critical for dashboard performance)
CREATE INDEX IF NOT EXISTS idx_license_usage_ts_app
ON license_usage_fact(ts DESC, app_id);

CREATE INDEX IF NOT EXISTS idx_license_cost_ts_app
ON license_cost_fact(ts DESC, app_id);

-- Update statistics for query planner
ANALYZE license_usage_fact;
ANALYZE license_cost_fact;

-- ========================================
-- PART 2: MATERIALIZED VIEWS
-- ========================================

-- 1. Daily Cost by Controller (HIGHEST PRIORITY)
DROP MATERIALIZED VIEW IF EXISTS mv_daily_cost_by_controller CASCADE;
CREATE MATERIALIZED VIEW mv_daily_cost_by_controller AS
SELECT
  DATE(lc.ts) as cost_date,
  COALESCE(a.appd_controller, 'Unknown') as controller,
  lc.tier,
  SUM(lc.usd_cost) as total_cost,
  AVG(lc.usd_cost) as avg_cost,
  COUNT(*) as record_count,
  COUNT(DISTINCT lc.app_id) as app_count
FROM license_cost_fact lc
JOIN applications_dim a ON lc.app_id = a.app_id
WHERE lc.ts >= NOW() - INTERVAL '180 days'
GROUP BY DATE(lc.ts), a.appd_controller, lc.tier;

-- Unique index required for CONCURRENT refresh (zero downtime)
CREATE UNIQUE INDEX idx_mv_daily_cost_unique ON mv_daily_cost_by_controller(cost_date, controller, tier);
CREATE INDEX idx_mv_daily_cost_date ON mv_daily_cost_by_controller(cost_date DESC);
CREATE INDEX idx_mv_daily_cost_controller ON mv_daily_cost_by_controller(controller);
CREATE INDEX idx_mv_daily_cost_tier ON mv_daily_cost_by_controller(tier);

-- 2. Daily Usage by Capability
DROP MATERIALIZED VIEW IF EXISTS mv_daily_usage_by_capability CASCADE;
CREATE MATERIALIZED VIEW mv_daily_usage_by_capability AS
SELECT
  DATE(lu.ts) as usage_date,
  c.capability_code,
  c.capability_name,
  COALESCE(a.appd_controller, 'Unknown') as controller,
  lu.tier,
  SUM(lu.units_consumed) as total_units,
  AVG(lu.units_consumed) as avg_units,
  SUM(lu.nodes_count) as total_nodes,
  AVG(lu.nodes_count) as avg_nodes,
  COUNT(DISTINCT lu.app_id) as app_count,
  COUNT(*) as record_count
FROM license_usage_fact lu
JOIN capabilities_dim c ON lu.capability_id = c.capability_id
JOIN applications_dim a ON lu.app_id = a.app_id
WHERE lu.ts >= NOW() - INTERVAL '180 days'
GROUP BY DATE(lu.ts), c.capability_code, c.capability_name, a.appd_controller, lu.tier;

-- Unique index required for CONCURRENT refresh
CREATE UNIQUE INDEX idx_mv_daily_usage_unique ON mv_daily_usage_by_capability(usage_date, capability_code, controller, tier);
CREATE INDEX idx_mv_daily_usage_date ON mv_daily_usage_by_capability(usage_date DESC);
CREATE INDEX idx_mv_daily_usage_capability ON mv_daily_usage_by_capability(capability_code);
CREATE INDEX idx_mv_daily_usage_controller ON mv_daily_usage_by_capability(controller);
CREATE INDEX idx_mv_daily_usage_tier ON mv_daily_usage_by_capability(tier);

-- 3. Cost by Sector and Controller
DROP MATERIALIZED VIEW IF EXISTS mv_cost_by_sector_controller CASCADE;
CREATE MATERIALIZED VIEW mv_cost_by_sector_controller AS
SELECT
  DATE(lc.ts) as cost_date,
  COALESCE(s.sector_name, 'Unknown') as sector_name,
  COALESCE(s.sector_id, -1) as sector_id,
  COALESCE(a.appd_controller, 'Unknown') as controller,
  lc.tier,
  SUM(lc.usd_cost) as total_cost,
  AVG(lc.usd_cost) as avg_cost,
  COUNT(DISTINCT a.app_id) as app_count,
  COUNT(*) as record_count
FROM license_cost_fact lc
JOIN applications_dim a ON lc.app_id = a.app_id
LEFT JOIN sectors_dim s ON a.sector_id = s.sector_id
WHERE lc.ts >= NOW() - INTERVAL '180 days'
GROUP BY DATE(lc.ts), s.sector_name, COALESCE(s.sector_id, -1), a.appd_controller, lc.tier;

-- Unique index required for CONCURRENT refresh
CREATE UNIQUE INDEX idx_mv_cost_sector_unique ON mv_cost_by_sector_controller(cost_date, COALESCE(sector_id, -1), controller, tier);
CREATE INDEX idx_mv_cost_sector_date ON mv_cost_by_sector_controller(cost_date DESC);
CREATE INDEX idx_mv_cost_sector_name ON mv_cost_by_sector_controller(sector_name);
CREATE INDEX idx_mv_cost_sector_controller ON mv_cost_by_sector_controller(controller);
CREATE INDEX idx_mv_cost_sector_tier ON mv_cost_by_sector_controller(tier);

-- 4. Cost by Owner and Controller
DROP MATERIALIZED VIEW IF EXISTS mv_cost_by_owner_controller CASCADE;
CREATE MATERIALIZED VIEW mv_cost_by_owner_controller AS
SELECT
  DATE(lc.ts) as cost_date,
  COALESCE(o.owner_name, 'Unknown') as owner_name,
  o.owner_id,
  COALESCE(a.appd_controller, 'Unknown') as controller,
  lc.tier,
  SUM(lc.usd_cost) as total_cost,
  AVG(lc.usd_cost) as avg_cost,
  COUNT(DISTINCT a.app_id) as app_count,
  COUNT(*) as record_count
FROM license_cost_fact lc
JOIN applications_dim a ON lc.app_id = a.app_id
LEFT JOIN owners_dim o ON a.owner_id = o.owner_id
WHERE lc.ts >= NOW() - INTERVAL '180 days'
GROUP BY DATE(lc.ts), o.owner_name, o.owner_id, a.appd_controller, lc.tier;

-- Unique index required for CONCURRENT refresh
CREATE UNIQUE INDEX idx_mv_cost_owner_unique ON mv_cost_by_owner_controller(cost_date, COALESCE(owner_id, -1), controller, tier);
CREATE INDEX idx_mv_cost_owner_date ON mv_cost_by_owner_controller(cost_date DESC);
CREATE INDEX idx_mv_cost_owner_name ON mv_cost_by_owner_controller(owner_name);
CREATE INDEX idx_mv_cost_owner_controller ON mv_cost_by_owner_controller(controller);
CREATE INDEX idx_mv_cost_owner_tier ON mv_cost_by_owner_controller(tier);

-- 5. Architecture Metrics (90-day window)
DROP MATERIALIZED VIEW IF EXISTS mv_architecture_metrics_90d CASCADE;
CREATE MATERIALIZED VIEW mv_architecture_metrics_90d AS
SELECT
  COALESCE(ar.pattern_name, 'Unknown') as architecture_name,
  ar.architecture_id,
  COALESCE(a.appd_controller, 'Unknown') as controller,
  c.capability_code,
  c.capability_name,
  lc.tier,
  COUNT(DISTINCT a.app_id) as app_count,
  SUM(lu.units_consumed) as total_units,
  AVG(lu.units_consumed) as avg_units_per_day,
  SUM(lu.nodes_count) as total_nodes,
  AVG(lu.nodes_count) as avg_nodes,
  SUM(lc.usd_cost) as total_cost,
  AVG(lc.usd_cost) as avg_cost_per_day,
  CASE
    WHEN AVG(lu.nodes_count) > 0
    THEN SUM(lu.units_consumed) / AVG(lu.nodes_count)
    ELSE 0
  END as units_per_node,
  CASE
    WHEN AVG(lu.nodes_count) > 0
    THEN SUM(lc.usd_cost) / AVG(lu.nodes_count)
    ELSE 0
  END as cost_per_node
FROM applications_dim a
LEFT JOIN architecture_dim ar ON a.architecture_id = ar.architecture_id
LEFT JOIN license_usage_fact lu ON a.app_id = lu.app_id
  AND lu.ts >= NOW() - INTERVAL '90 days'
LEFT JOIN license_cost_fact lc ON a.app_id = lc.app_id
  AND DATE(lc.ts) = DATE(lu.ts)
  AND lc.ts >= NOW() - INTERVAL '90 days'
LEFT JOIN capabilities_dim c ON lu.capability_id = c.capability_id
WHERE lu.ts IS NOT NULL
GROUP BY ar.pattern_name, ar.architecture_id, a.appd_controller,
         c.capability_code, c.capability_name, lc.tier;

-- Unique index required for CONCURRENT refresh
CREATE UNIQUE INDEX idx_mv_arch_unique ON mv_architecture_metrics_90d(COALESCE(architecture_id, -1), controller, capability_code, tier);
CREATE INDEX idx_mv_arch_name ON mv_architecture_metrics_90d(architecture_name);
CREATE INDEX idx_mv_arch_controller ON mv_architecture_metrics_90d(controller);
CREATE INDEX idx_mv_arch_capability ON mv_architecture_metrics_90d(capability_code);
CREATE INDEX idx_mv_arch_tier ON mv_architecture_metrics_90d(tier);

-- 6. App Cost Rankings (Monthly)
DROP MATERIALIZED VIEW IF EXISTS mv_app_cost_rankings_monthly CASCADE;
CREATE MATERIALIZED VIEW mv_app_cost_rankings_monthly AS
SELECT
  DATE_TRUNC('month', lc.ts) as month_start,
  a.app_id,
  a.appd_application_name,
  a.appd_application_id,
  COALESCE(a.appd_controller, 'Unknown') as controller,
  COALESCE(s.sector_name, 'Unknown') as sector_name,
  COALESCE(o.owner_name, 'Unknown') as owner_name,
  a.license_tier,
  lc.tier as cost_tier,
  SUM(lc.usd_cost) as total_cost,
  AVG(lc.usd_cost) as avg_daily_cost,
  COUNT(*) as days_active,
  RANK() OVER (
    PARTITION BY DATE_TRUNC('month', lc.ts), a.appd_controller
    ORDER BY SUM(lc.usd_cost) DESC
  ) as cost_rank
FROM license_cost_fact lc
JOIN applications_dim a ON lc.app_id = a.app_id
LEFT JOIN sectors_dim s ON a.sector_id = s.sector_id
LEFT JOIN owners_dim o ON a.owner_id = o.owner_id
WHERE lc.ts >= NOW() - INTERVAL '13 months'
  AND a.appd_application_name IS NOT NULL
GROUP BY DATE_TRUNC('month', lc.ts), a.app_id, a.appd_application_name,
         a.appd_application_id, a.appd_controller, s.sector_name,
         o.owner_name, a.license_tier, lc.tier;

-- Unique index required for CONCURRENT refresh
CREATE UNIQUE INDEX idx_mv_app_rank_unique ON mv_app_cost_rankings_monthly(month_start, app_id, cost_tier);
CREATE INDEX idx_mv_app_rank_month ON mv_app_cost_rankings_monthly(month_start DESC);
CREATE INDEX idx_mv_app_rank_controller ON mv_app_cost_rankings_monthly(controller);
CREATE INDEX idx_mv_app_rank_cost ON mv_app_cost_rankings_monthly(total_cost DESC);
CREATE INDEX idx_mv_app_rank_rank ON mv_app_cost_rankings_monthly(cost_rank);
CREATE INDEX idx_mv_app_rank_tier ON mv_app_cost_rankings_monthly(cost_tier);

-- 7. Monthly Chargeback Summary
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_chargeback_summary CASCADE;
CREATE MATERIALIZED VIEW mv_monthly_chargeback_summary AS
SELECT
  c.month_start,
  COALESCE(a.appd_controller, 'Unknown') as controller,
  COALESCE(s.sector_name, 'Unknown') as sector_name,
  COALESCE(s.sector_id, -1) as sector_id,
  COALESCE(c.cost_center, 'Unknown') as cost_center,
  SUM(c.usd_amount) as total_amount,
  AVG(c.usd_amount) as avg_amount,
  COUNT(DISTINCT c.app_id) as app_count,
  COUNT(*) as chargeback_records
FROM chargeback_fact c
JOIN applications_dim a ON c.app_id = a.app_id
LEFT JOIN sectors_dim s ON c.sector_id = s.sector_id
WHERE c.month_start >= DATE_TRUNC('month', NOW() - INTERVAL '24 months')
GROUP BY c.month_start,
         COALESCE(a.appd_controller, 'Unknown'),
         COALESCE(s.sector_name, 'Unknown'),
         COALESCE(s.sector_id, -1),
         COALESCE(c.cost_center, 'Unknown');

-- Unique index required for CONCURRENT refresh
CREATE UNIQUE INDEX idx_mv_chargeback_unique ON mv_monthly_chargeback_summary(month_start, controller, COALESCE(sector_id, -1), cost_center);
CREATE INDEX idx_mv_chargeback_month ON mv_monthly_chargeback_summary(month_start DESC);
CREATE INDEX idx_mv_chargeback_controller ON mv_monthly_chargeback_summary(controller);
CREATE INDEX idx_mv_chargeback_sector ON mv_monthly_chargeback_summary(sector_name);
CREATE INDEX idx_mv_chargeback_cost_center ON mv_monthly_chargeback_summary(cost_center);

-- 8. Peak vs Pro Comparison
DROP MATERIALIZED VIEW IF EXISTS mv_peak_pro_comparison CASCADE;
CREATE MATERIALIZED VIEW mv_peak_pro_comparison AS
WITH peak_costs AS (
  SELECT
    DATE(lc.ts) as cost_date,
    a.app_id,
    a.appd_application_name,
    a.appd_controller,
    SUM(lc.usd_cost) as peak_cost
  FROM license_cost_fact lc
  JOIN applications_dim a ON lc.app_id = a.app_id
  WHERE lc.tier = 'Peak'
    AND lc.ts >= NOW() - INTERVAL '90 days'
  GROUP BY DATE(lc.ts), a.app_id, a.appd_application_name, a.appd_controller
),
pro_costs AS (
  SELECT
    DATE(lc.ts) as cost_date,
    a.app_id,
    a.appd_application_name,
    a.appd_controller,
    SUM(lc.usd_cost) as pro_cost
  FROM license_cost_fact lc
  JOIN applications_dim a ON lc.app_id = a.app_id
  WHERE lc.tier = 'Pro'
    AND lc.ts >= NOW() - INTERVAL '90 days'
  GROUP BY DATE(lc.ts), a.app_id, a.appd_application_name, a.appd_controller
)
SELECT
  COALESCE(pk.cost_date, pr.cost_date) as cost_date,
  COALESCE(pk.app_id, pr.app_id) as app_id,
  COALESCE(pk.appd_application_name, pr.appd_application_name) as app_name,
  COALESCE(pk.appd_controller, pr.appd_controller) as controller,
  COALESCE(pk.peak_cost, 0) as peak_cost,
  COALESCE(pr.pro_cost, 0) as pro_cost,
  COALESCE(pk.peak_cost, 0) + COALESCE(pr.pro_cost, 0) as total_cost,
  CASE
    WHEN pk.peak_cost > 0
    THEN pk.peak_cost - (pk.peak_cost * 0.67)
    ELSE 0
  END as potential_savings
FROM peak_costs pk
FULL OUTER JOIN pro_costs pr
  ON pk.cost_date = pr.cost_date
  AND pk.app_id = pr.app_id;

-- Unique index required for CONCURRENT refresh
CREATE UNIQUE INDEX idx_mv_peak_pro_unique ON mv_peak_pro_comparison(cost_date, app_id);
CREATE INDEX idx_mv_peak_pro_date ON mv_peak_pro_comparison(cost_date DESC);
CREATE INDEX idx_mv_peak_pro_controller ON mv_peak_pro_comparison(controller);
CREATE INDEX idx_mv_peak_pro_savings ON mv_peak_pro_comparison(potential_savings DESC);

-- ========================================
-- PART 3: REFRESH FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION refresh_all_dashboard_views()
RETURNS TABLE(view_name TEXT, refresh_status TEXT, refresh_time INTERVAL) AS $$
DECLARE
  start_time TIMESTAMP;
  end_time TIMESTAMP;
  v_name TEXT;
BEGIN
  FOR v_name IN
    SELECT unnest(ARRAY[
      'mv_daily_cost_by_controller',
      'mv_daily_usage_by_capability',
      'mv_cost_by_sector_controller',
      'mv_cost_by_owner_controller',
      'mv_architecture_metrics_90d',
      'mv_app_cost_rankings_monthly',
      'mv_monthly_chargeback_summary',
      'mv_peak_pro_comparison'
    ])
  LOOP
    BEGIN
      start_time := clock_timestamp();
      EXECUTE 'REFRESH MATERIALIZED VIEW CONCURRENTLY ' || v_name;
      end_time := clock_timestamp();

      view_name := v_name;
      refresh_status := 'SUCCESS';
      refresh_time := end_time - start_time;
      RETURN NEXT;

    EXCEPTION WHEN OTHERS THEN
      view_name := v_name;
      refresh_status := 'FAILED: ' || SQLERRM;
      refresh_time := NULL;
      RETURN NEXT;
    END;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- PART 4: GRANTS
-- ========================================

GRANT SELECT ON mv_daily_cost_by_controller TO grafana_ro;
GRANT SELECT ON mv_daily_usage_by_capability TO grafana_ro;
GRANT SELECT ON mv_cost_by_sector_controller TO grafana_ro;
GRANT SELECT ON mv_cost_by_owner_controller TO grafana_ro;
GRANT SELECT ON mv_architecture_metrics_90d TO grafana_ro;
GRANT SELECT ON mv_app_cost_rankings_monthly TO grafana_ro;
GRANT SELECT ON mv_monthly_chargeback_summary TO grafana_ro;
GRANT SELECT ON mv_peak_pro_comparison TO grafana_ro;

-- ========================================
-- LICENSE OVERAGE TRACKING (SOW Section 2.1 & 2.3)
-- ========================================
-- These views enable overage tracking and license exhaustion predictions
-- by comparing actual usage vs licensed capacity

-- Current License Entitlements (most recent capture per controller/package)
DROP MATERIALIZED VIEW IF EXISTS mv_current_license_entitlements CASCADE;
CREATE MATERIALIZED VIEW mv_current_license_entitlements AS
WITH latest_capture AS (
    SELECT
        appd_controller,
        appd_account_id,
        package_name,
        MAX(captured_at) as latest_captured_at
    FROM license_entitlements
    GROUP BY appd_controller, appd_account_id, package_name
)
SELECT
    le.entitlement_id,
    le.appd_controller,
    le.appd_account,
    le.appd_account_id,
    le.package_name,
    le.capability_id,
    c.capability_code,
    c.capability_name,
    le.tier,
    le.licensed_units,
    le.expiration_date,
    le.captured_at
FROM license_entitlements le
JOIN latest_capture lc
    ON le.appd_controller = lc.appd_controller
    AND le.appd_account_id = lc.appd_account_id
    AND le.package_name = lc.package_name
    AND le.captured_at = lc.latest_captured_at
LEFT JOIN capabilities_dim c ON le.capability_id = c.capability_id;

CREATE UNIQUE INDEX idx_mv_current_entitlements_unique
    ON mv_current_license_entitlements(appd_controller, appd_account_id, package_name);
CREATE INDEX idx_mv_current_entitlements_capability
    ON mv_current_license_entitlements(capability_id);

COMMENT ON MATERIALIZED VIEW mv_current_license_entitlements IS
'SOW 2.1: Current licensed capacity per controller/package (most recent snapshot)';

-- Daily Peak Usage vs Licensed Capacity (Overage Analysis)
DROP MATERIALIZED VIEW IF EXISTS mv_license_overage_daily CASCADE;
CREATE MATERIALIZED VIEW mv_license_overage_daily AS
WITH daily_peak_usage AS (
    -- Get peak daily usage by controller and capability
    SELECT
        DATE(luf.ts) as usage_date,
        a.appd_controller,
        luf.capability_id,
        c.capability_code,
        luf.tier,
        MAX(luf.units_consumed) as peak_units_consumed,
        COUNT(DISTINCT luf.app_id) as app_count
    FROM license_usage_fact luf
    JOIN applications_dim a ON luf.app_id = a.app_id
    JOIN capabilities_dim c ON luf.capability_id = c.capability_id
    WHERE luf.ts >= NOW() - INTERVAL '90 days'
      AND c.capability_code IN ('APM', 'BRUM', 'MRUM', 'ANALYTICS', 'INFRA')
    GROUP BY DATE(luf.ts), a.appd_controller, luf.capability_id, c.capability_code, luf.tier
),
latest_entitlements AS (
    -- Get most recent licensed capacity
    SELECT
        mce.appd_controller,
        mce.capability_id,
        mce.capability_code,
        mce.tier,
        SUM(mce.licensed_units) as total_licensed_units,
        MAX(mce.expiration_date) as expiration_date
    FROM mv_current_license_entitlements mce
    WHERE mce.capability_id IS NOT NULL
      -- Exclude summary packages (eum-unified, eum-browser, eum-mobile) to avoid double-counting
      AND mce.package_name NOT IN ('eum-unified', 'eum-browser', 'eum-mobile')
    GROUP BY mce.appd_controller, mce.capability_id, mce.capability_code, mce.tier
)
SELECT
    dpu.usage_date,
    dpu.appd_controller,
    dpu.capability_id,
    dpu.capability_code,
    dpu.tier,
    dpu.peak_units_consumed,
    dpu.app_count,
    COALESCE(le.total_licensed_units, 0) as licensed_units,
    GREATEST(dpu.peak_units_consumed - COALESCE(le.total_licensed_units, 0), 0) as overage_units,
    CASE
        WHEN COALESCE(le.total_licensed_units, 0) = 0 THEN 0
        ELSE ROUND((dpu.peak_units_consumed / le.total_licensed_units * 100)::numeric, 2)
    END as usage_percent,
    CASE
        WHEN COALESCE(le.total_licensed_units, 0) = 0 THEN 'NO_LICENSE'
        WHEN dpu.peak_units_consumed > le.total_licensed_units THEN 'OVERAGE'
        WHEN dpu.peak_units_consumed > (le.total_licensed_units * 0.90) THEN 'WARNING'
        ELSE 'OK'
    END as status,
    le.expiration_date
FROM daily_peak_usage dpu
LEFT JOIN latest_entitlements le
    ON dpu.appd_controller = le.appd_controller
    AND dpu.capability_id = le.capability_id
    AND dpu.tier = le.tier;

CREATE UNIQUE INDEX idx_mv_overage_daily_unique
    ON mv_license_overage_daily(usage_date, appd_controller, capability_id, tier);
CREATE INDEX idx_mv_overage_daily_date ON mv_license_overage_daily(usage_date DESC);
CREATE INDEX idx_mv_overage_daily_controller ON mv_license_overage_daily(appd_controller);
CREATE INDEX idx_mv_overage_daily_capability ON mv_license_overage_daily(capability_id);
CREATE INDEX idx_mv_overage_daily_status ON mv_license_overage_daily(status);

COMMENT ON MATERIALIZED VIEW mv_license_overage_daily IS
'SOW 2.1 & 2.3: Daily peak usage vs licensed capacity with overage calculations. WARNING = >90% utilization, OVERAGE = exceeds license.';

-- Monthly Overage Summary for Chargeback
DROP MATERIALIZED VIEW IF EXISTS mv_license_overage_monthly CASCADE;
CREATE MATERIALIZED VIEW mv_license_overage_monthly AS
SELECT
    DATE_TRUNC('month', usage_date)::date as month_start,
    appd_controller,
    capability_id,
    capability_code,
    tier,
    AVG(peak_units_consumed)::numeric(18,2) as avg_units_consumed,
    MAX(peak_units_consumed)::numeric(18,2) as max_units_consumed,
    AVG(licensed_units)::numeric(18,2) as avg_licensed_units,
    AVG(overage_units)::numeric(18,2) as avg_overage_units,
    MAX(overage_units)::numeric(18,2) as max_overage_units,
    AVG(usage_percent)::numeric(18,2) as avg_usage_percent,
    MAX(usage_percent)::numeric(18,2) as max_usage_percent,
    COUNT(CASE WHEN status = 'OVERAGE' THEN 1 END) as days_in_overage,
    COUNT(CASE WHEN status = 'WARNING' THEN 1 END) as days_in_warning,
    COUNT(*) as total_days,
    MAX(expiration_date) as expiration_date
FROM mv_license_overage_daily
GROUP BY DATE_TRUNC('month', usage_date)::date, appd_controller, capability_id, capability_code, tier;

CREATE UNIQUE INDEX idx_mv_overage_monthly_unique
    ON mv_license_overage_monthly(month_start, appd_controller, capability_id, tier);
CREATE INDEX idx_mv_overage_monthly_month ON mv_license_overage_monthly(month_start DESC);
CREATE INDEX idx_mv_overage_monthly_controller ON mv_license_overage_monthly(appd_controller);

COMMENT ON MATERIALIZED VIEW mv_license_overage_monthly IS
'SOW 2.1 & 2.3: Monthly overage summary for license compliance reporting and overage billing calculations.';

-- Grant access to new overage views
GRANT SELECT ON mv_current_license_entitlements TO grafana_ro;
GRANT SELECT ON mv_license_overage_daily TO grafana_ro;
GRANT SELECT ON mv_license_overage_monthly TO grafana_ro;

-- ========================================
-- VERIFICATION
-- ========================================

DO $$
DECLARE
  v_name TEXT;
  v_count BIGINT;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Performance Optimization Complete!';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Materialized Views Created: 11';
  RAISE NOTICE '  - 8 Performance/Analytics Views';
  RAISE NOTICE '  - 3 License Overage Views (SOW 2.1 & 2.3)';
  RAISE NOTICE 'Additional Indexes Created: 2';
  RAISE NOTICE '';
  RAISE NOTICE 'Views will be empty until first ETL run.';
  RAISE NOTICE 'Run refresh_views.py after ETL completes.';
  RAISE NOTICE '========================================';
END $$;

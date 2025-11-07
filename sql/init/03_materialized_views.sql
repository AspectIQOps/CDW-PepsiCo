-- ============================================================
-- Materialized Views for Dashboard Performance
-- ============================================================

-- Drop existing views (for clean rebuilds)
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_cost_summary CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_app_cost_current CASCADE;

-- Monthly Cost Summary (aggregated by month/app/capability/tier)
CREATE MATERIALIZED VIEW mv_monthly_cost_summary AS
SELECT 
    DATE_TRUNC('month', ts)::date as month_start,
    app_id,
    capability_id,
    tier,
    SUM(usd_cost) as total_cost,
    AVG(usd_cost) as avg_daily_cost,
    COUNT(*) as days_active,
    MIN(ts) as first_usage,
    MAX(ts) as last_usage
FROM license_cost_fact
GROUP BY 1,2,3,4;

CREATE UNIQUE INDEX idx_mv_monthly_cost_unique ON mv_monthly_cost_summary(month_start, app_id, capability_id, tier);
CREATE INDEX idx_mv_monthly_cost_month ON mv_monthly_cost_summary(month_start);
CREATE INDEX idx_mv_monthly_cost_app ON mv_monthly_cost_summary(app_id);

COMMENT ON MATERIALIZED VIEW mv_monthly_cost_summary IS 'Pre-aggregated monthly costs for dashboard performance';

-- Application Cost Summary (current month with metadata)
CREATE MATERIALIZED VIEW mv_app_cost_current AS
SELECT 
    ad.app_id,
    COALESCE(ad.appd_application_name, ad.sn_service_name) as app_name,
    o.owner_name,
    s.sector_name,
    ar.pattern_name as architecture,
    ad.h_code,
    SUM(lcf.usd_cost) as month_cost,
    COUNT(DISTINCT lcf.capability_id) as capability_count,
    COUNT(DISTINCT DATE(lcf.ts)) as days_active,
    AVG(lcf.usd_cost) as avg_daily_cost
FROM applications_dim ad
LEFT JOIN owners_dim o ON o.owner_id = ad.owner_id
LEFT JOIN sectors_dim s ON s.sector_id = ad.sector_id
LEFT JOIN architecture_dim ar ON ar.architecture_id = ad.architecture_id
LEFT JOIN license_cost_fact lcf ON lcf.app_id = ad.app_id
    AND DATE_TRUNC('month', lcf.ts) = DATE_TRUNC('month', NOW())
GROUP BY ad.app_id, ad.appd_application_name, ad.sn_service_name,
         o.owner_name, s.sector_name, ar.pattern_name, ad.h_code;

CREATE UNIQUE INDEX idx_mv_app_cost_app_id ON mv_app_cost_current(app_id);
CREATE INDEX idx_mv_app_cost_sector ON mv_app_cost_current(sector_name);
CREATE INDEX idx_mv_app_cost_owner ON mv_app_cost_current(owner_name);

COMMENT ON MATERIALIZED VIEW mv_app_cost_current IS 'Current month application costs with metadata for dashboards';

-- Grant permissions
GRANT SELECT ON mv_monthly_cost_summary TO etl_analytics;
GRANT SELECT ON mv_app_cost_current TO etl_analytics;

-- Verification
DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Materialized Views Created Successfully';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'mv_monthly_cost_summary: % rows', (SELECT COUNT(*) FROM mv_monthly_cost_summary);
    RAISE NOTICE 'mv_app_cost_current: % rows', (SELECT COUNT(*) FROM mv_app_cost_current);
    RAISE NOTICE '==============================================';
END $$;
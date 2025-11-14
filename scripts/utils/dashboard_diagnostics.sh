#!/bin/bash
# Dashboard Data Diagnostics
# Run from: ubuntu@ip-172-31-35-82:~/CDW-PepsiCo$
# Purpose: Identify why Grafana dashboard shows "No Data"

echo "=========================================="
echo "Dashboard Data Diagnostics"
echo "=========================================="

# 1. Check chargeback_fact table
echo -e "\n1. CHARGEBACK_FACT STATUS:"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT 
  COUNT(*) as total_records,
  COUNT(DISTINCT month_start) as distinct_months,
  COUNT(DISTINCT app_id) as distinct_apps,
  COUNT(DISTINCT sector_id) as distinct_sectors,
  MIN(month_start) as earliest_month,
  MAX(month_start) as latest_month,
  ROUND(SUM(usd_amount)::numeric, 2) as total_usd
FROM chargeback_fact;
"

# 2. Check if materialized view exists and has data
echo -e "\n2. MATERIALIZED VIEW STATUS:"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT 
  schemaname,
  matviewname,
  hasindexes,
  ispopulated,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||matviewname)) as size
FROM pg_matviews
WHERE matviewname = 'mv_monthly_chargeback_summary';
"

echo -e "\n   View Row Count:"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT COUNT(*) as row_count FROM mv_monthly_chargeback_summary;
"

# 3. Check applications dimension - H-codes and sectors
echo -e "\n3. APPLICATIONS DIMENSION STATUS:"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT 
  COUNT(*) as total_apps,
  COUNT(CASE WHEN h_code IS NOT NULL AND h_code != 'Unknown' THEN 1 END) as apps_with_hcode,
  COUNT(CASE WHEN sector_id IS NOT NULL THEN 1 END) as apps_with_sector,
  COUNT(CASE WHEN appd_application_id IS NOT NULL THEN 1 END) as appd_apps,
  COUNT(CASE WHEN sn_sys_id IS NOT NULL THEN 1 END) as snow_apps,
  COUNT(CASE WHEN appd_application_id IS NOT NULL AND sn_sys_id IS NOT NULL THEN 1 END) as matched_apps
FROM applications_dim;
"

# 4. Check raw cost data (source for chargeback)
echo -e "\n4. LICENSE_COST_FACT STATUS (source data):"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT 
  COUNT(*) as total_records,
  COUNT(DISTINCT app_id) as distinct_apps,
  COUNT(DISTINCT DATE_TRUNC('month', ts)) as distinct_months,
  MIN(ts) as earliest_date,
  MAX(ts) as latest_date,
  ROUND(SUM(usd_cost)::numeric, 2) as total_cost
FROM license_cost_fact;
"

# 5. Sample data from chargeback_fact
echo -e "\n5. SAMPLE CHARGEBACK DATA (last 5 records):"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT 
  c.month_start,
  a.appd_application_name,
  s.sector_name,
  c.h_code,
  c.usd_amount,
  c.chargeback_cycle
FROM chargeback_fact c
LEFT JOIN applications_dim a ON c.app_id = a.app_id
LEFT JOIN sectors_dim s ON c.sector_id = s.sector_id
ORDER BY c.month_start DESC, c.usd_amount DESC
LIMIT 5;
"

# 6. Check if controller variable filter has data
echo -e "\n6. CONTROLLER FILTER DATA (for dashboard variable):"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT 
  appd_controller,
  COUNT(*) as app_count
FROM applications_dim 
WHERE appd_controller IS NOT NULL
GROUP BY appd_controller
ORDER BY app_count DESC;
"

# 7. Check sector dimension
echo -e "\n7. SECTORS DIMENSION:"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT 
  s.sector_id,
  s.sector_name,
  COUNT(a.app_id) as app_count
FROM sectors_dim s
LEFT JOIN applications_dim a ON a.sector_id = s.sector_id
GROUP BY s.sector_id, s.sector_name
ORDER BY app_count DESC;
"

# 8. Check if ETL has run recently
echo -e "\n8. RECENT ETL EXECUTION LOG:"
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT 
  job_name,
  started_at,
  finished_at,
  status,
  rows_ingested,
  error_message
FROM etl_execution_log
ORDER BY started_at DESC
LIMIT 10;
"

echo -e "\n=========================================="
echo "Diagnostics Complete"
echo "=========================================="
echo ""
echo "NEXT STEPS BASED ON RESULTS:"
echo "  - If chargeback_fact is EMPTY: Run allocation_engine.py"
echo "  - If mv_monthly_chargeback_summary is EMPTY: Run refresh_views.py"
echo "  - If apps missing H-codes: Run reconciliation or load H-code mapping"
echo "  - If license_cost_fact is EMPTY: Run appd_etl.py first"
echo ""
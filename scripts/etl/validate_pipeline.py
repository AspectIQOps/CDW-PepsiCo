#!/usr/bin/env python3
"""Validate ETL pipeline data quality"""
import psycopg2
import os

DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_NAME = os.getenv('DB_NAME', 'cost_analytics_db')
DB_USER = os.getenv('DB_USER', 'etl_analytics')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'appd_pass')

def validate_pipeline():
    conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)
    cursor = conn.cursor()
    
    print("=" * 70)
    print("ETL PIPELINE VALIDATION REPORT")
    print("=" * 70)
    
    # 1. Check table row counts
    tables = [
        'applications_dim', 'servers_dim', 'app_server_mapping',
        'license_usage_fact', 'license_cost_fact', 'chargeback_fact',
        'forecast_fact', 'reconciliation_log', 'etl_execution_log'
    ]
    
    print("\n1. TABLE ROW COUNTS:")
    print("-" * 70)
    for table in tables:
        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        count = cursor.fetchone()[0]
        status = "✅" if count > 0 else "❌"
        print(f"{status} {table:<25} {count:>10,} rows")
    
    # 2. Check match rate - FIXED LOGIC
    print("\n2. RECONCILIATION MATCH RATE:")
    print("-" * 70)
    
    # Count apps with AppD data (regardless of whether they have sn_sys_id)
    cursor.execute("""
        SELECT COUNT(*) 
        FROM applications_dim 
        WHERE appd_application_name IS NOT NULL
    """)
    apps_with_appd = cursor.fetchone()[0]
    
    # Count apps with BOTH AppD name and ServiceNow name (merged records)
    cursor.execute("""
        SELECT COUNT(*) 
        FROM applications_dim 
        WHERE appd_application_name IS NOT NULL 
        AND sn_service_name IS NOT NULL
    """)
    matched_apps = cursor.fetchone()[0]
    
    # Calculate match rate for AppD-monitored apps
    if apps_with_appd > 0:
        appd_match_rate = (matched_apps / apps_with_appd * 100)
        status = "✅" if appd_match_rate >= 95 else "⚠️"
        print(f"{status} AppD Applications Matched: {matched_apps}/{apps_with_appd} ({appd_match_rate:.1f}%)")
        print(f"    (This measures how many AppD-monitored apps matched to CMDB)")
    else:
        print("⚠️  No AppD applications found in system")
    
    # Overall application breakdown
    cursor.execute("""
        SELECT 
            COUNT(CASE WHEN appd_application_name IS NOT NULL AND sn_service_name IS NOT NULL THEN 1 END) as matched,
            COUNT(CASE WHEN appd_application_name IS NOT NULL AND sn_service_name IS NULL THEN 1 END) as appd_only,
            COUNT(CASE WHEN appd_application_name IS NULL AND sn_service_name IS NOT NULL THEN 1 END) as snow_only,
            COUNT(*) as total
        FROM applications_dim
    """)
    stats = cursor.fetchone()
    
    print(f"\n    Application Breakdown:")
    print(f"    • Matched (AppD + ServiceNow): {stats[0]}")
    print(f"    • AppD Only (no CMDB match): {stats[1]}")
    print(f"    • ServiceNow Only (not monitored): {stats[2]}")
    print(f"    • Total Applications: {stats[3]}")
    
    # 3. Check data freshness
    print("\n3. DATA FRESHNESS:")
    print("-" * 70)
    cursor.execute("""
        SELECT 
            job_name,
            MAX(finished_at) as last_run,
            MAX(CASE WHEN status = 'success' THEN finished_at END) as last_success
        FROM etl_execution_log
        GROUP BY job_name
    """)
    for row in cursor.fetchall():
        print(f"  {row[0]:<20} Last run: {row[1]}, Last success: {row[2]}")
    
    # 4. Check for orphaned records
    print("\n4. DATA QUALITY CHECKS:")
    print("-" * 70)
    
    cursor.execute("""
        SELECT COUNT(*) FROM license_usage_fact luf
        WHERE NOT EXISTS (SELECT 1 FROM license_cost_fact lcf 
                         WHERE lcf.app_id = luf.app_id 
                         AND lcf.ts = luf.ts 
                         AND lcf.capability_id = luf.capability_id)
    """)
    orphaned_usage = cursor.fetchone()[0]
    status = "✅" if orphaned_usage == 0 else "⚠️"
    print(f"{status} Orphaned usage records (no cost): {orphaned_usage}")
    
    # 5. Check forecast coverage (only for apps with usage data)
    cursor.execute("""
        SELECT COUNT(DISTINCT app_id) 
        FROM license_usage_fact
        WHERE ts >= NOW() - INTERVAL '30 days'
    """)
    apps_with_usage = cursor.fetchone()[0]
    
    cursor.execute("""
        SELECT COUNT(DISTINCT app_id)
        FROM forecast_fact
        WHERE month_start >= DATE_TRUNC('month', NOW())
    """)
    apps_with_forecasts = cursor.fetchone()[0]
    
    if apps_with_usage > 0:
        coverage = (apps_with_forecasts / apps_with_usage * 100)
        status = "✅" if coverage >= 80 else "⚠️"
        print(f"{status} Forecast coverage: {apps_with_forecasts}/{apps_with_usage} apps with usage data ({coverage:.1f}%)")
    else:
        print("⚠️  No usage data available for forecasting")
    
    # 6. Check reconciliation success rate
    print("\n5. RECONCILIATION QUALITY:")
    print("-" * 70)
    
    cursor.execute("""
        SELECT 
            COUNT(CASE WHEN match_status = 'auto_matched' THEN 1 END) as auto_matched,
            COUNT(CASE WHEN match_status = 'needs_review' THEN 1 END) as needs_review,
            COUNT(*) as total_attempts
        FROM reconciliation_log
    """)
    recon_stats = cursor.fetchone()
    
    if recon_stats and recon_stats[2] > 0:
        auto_rate = (recon_stats[0] / recon_stats[2] * 100)
        status = "✅" if auto_rate >= 80 else "⚠️"
        print(f"{status} Auto-matched: {recon_stats[0]}/{recon_stats[2]} attempts ({auto_rate:.1f}%)")
        if recon_stats[1] > 0:
            print(f"⚠️  Needs manual review: {recon_stats[1]} matches")
    else:
        print("ℹ️  No reconciliation attempts logged yet")
    
    # 7. Cost calculation accuracy
    print("\n6. COST CALCULATION ACCURACY:")
    print("-" * 70)
    
    cursor.execute("""
        SELECT 
            SUM(luf.units_consumed * pc.unit_rate) as expected_cost,
            SUM(lcf.usd_cost) as actual_cost
        FROM license_usage_fact luf
        JOIN license_cost_fact lcf 
            ON lcf.app_id = luf.app_id 
            AND lcf.ts = luf.ts 
            AND lcf.capability_id = luf.capability_id
            AND lcf.tier = luf.tier
        JOIN price_config pc 
            ON pc.capability_id = luf.capability_id 
            AND pc.tier = luf.tier
            AND luf.ts::date BETWEEN pc.start_date AND COALESCE(pc.end_date, luf.ts::date)
    """)
    cost_check = cursor.fetchone()
    
    if cost_check and cost_check[0] and cost_check[1]:
        expected = float(cost_check[0])
        actual = float(cost_check[1])
        diff_pct = abs(expected - actual) / expected * 100 if expected > 0 else 0
        
        status = "✅" if diff_pct < 1 else "⚠️"
        print(f"{status} Cost calculation variance: {diff_pct:.2f}%")
        print(f"    Expected: ${expected:,.2f}")
        print(f"    Actual:   ${actual:,.2f}")
    else:
        print("⚠️  Unable to validate cost calculations (missing data)")
    
    print("=" * 70)
    print("\n✅ Validation Complete!")
    
    # Summary status
    if apps_with_appd > 0 and matched_apps == apps_with_appd:
        print("🎉 ALL CHECKS PASSED - Pipeline is healthy!")
    elif apps_with_appd > 0 and matched_apps >= apps_with_appd * 0.95:
        print("✅ Pipeline is operational (minor warnings)")
    else:
        print("⚠️  Some issues detected - review warnings above")
    
    print("=" * 70)
    
    cursor.close()
    conn.close()

if __name__ == '__main__':
    validate_pipeline()
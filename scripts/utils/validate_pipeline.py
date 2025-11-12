#!/usr/bin/env python3
"""
Validate ETL pipeline data quality - Production Grade
FIXED: Reconciliation match rate calculation
"""
import psycopg2
import os
import sys

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

def validate_pipeline():
    """Comprehensive ETL pipeline validation"""
    try:
        conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)
    except Exception as e:
        print("=" * 70)
        print("ETL PIPELINE VALIDATION FAILED")
        print("=" * 70)
        print(f"❌ Cannot connect to database: {e}")
        sys.exit(1)
    
    cursor = conn.cursor()
    
    print("=" * 70)
    print("ETL PIPELINE VALIDATION REPORT")
    print("=" * 70)
    
    validation_passed = True
    
    # 1. Check table row counts
    tables = [
        'applications_dim', 'servers_dim', 'app_server_mapping',
        'license_usage_fact', 'license_cost_fact', 'chargeback_fact',
        'forecast_fact', 'reconciliation_log', 'etl_execution_log'
    ]
    
    print("\n1. TABLE ROW COUNTS:")
    print("-" * 70)
    
    table_counts = {}
    for table in tables:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = cursor.fetchone()[0]
            table_counts[table] = count
            status = "✅" if count > 0 else "⚠️ "
            print(f"{status} {table:<25} {count:>10,} rows")
            
            # Critical tables must have data
            if table in ['applications_dim', 'etl_execution_log'] and count == 0:
                validation_passed = False
        except Exception as e:
            print(f"❌ {table:<25} ERROR: {e}")
            validation_passed = False
    
    # 2. Check match rate - FIXED LOGIC
    print("\n2. RECONCILIATION MATCH RATE:")
    print("-" * 70)
    
    try:
        # Count apps that came from AppD (have appd_application_id)
        cursor.execute("""
            SELECT COUNT(*) 
            FROM applications_dim 
            WHERE appd_application_id IS NOT NULL
        """)
        apps_from_appd = cursor.fetchone()[0]
        
        # Count apps that came from ServiceNow (have sn_sys_id)
        cursor.execute("""
            SELECT COUNT(*) 
            FROM applications_dim 
            WHERE sn_sys_id IS NOT NULL
        """)
        apps_from_snow = cursor.fetchone()[0]
        
        # Count MATCHED apps (have BOTH appd_application_id AND sn_sys_id)
        # After reconciliation, these records have data from both sources merged
        cursor.execute("""
            SELECT COUNT(*) 
            FROM applications_dim 
            WHERE appd_application_id IS NOT NULL 
            AND sn_sys_id IS NOT NULL
        """)
        matched_apps = cursor.fetchone()[0]
        
        # Calculate match rates
        if apps_from_appd > 0:
            appd_match_rate = (matched_apps / apps_from_appd * 100)
            status = "✅" if appd_match_rate >= 80 else "⚠️ "
            print(f"{status} AppD Apps Matched to CMDB: {matched_apps}/{apps_from_appd} ({appd_match_rate:.1f}%)")
            print(f"    (Measures how many AppD-monitored apps were found in ServiceNow)")
            
            if appd_match_rate < 80:
                print(f"    ⚠️  Target is 80%+ match rate for production use")
                validation_passed = False
        else:
            print("⚠️  No AppDynamics applications found")
            print("    Run appd_etl.py to load AppDynamics data")
        
        if apps_from_snow > 0:
            snow_match_rate = (matched_apps / apps_from_snow * 100) if apps_from_snow > 0 else 0
            print(f"\n    ServiceNow Apps Matched to AppD: {matched_apps}/{apps_from_snow} ({snow_match_rate:.1f}%)")
            print(f"    (Measures what % of CMDB apps are monitored in AppD)")
            print(f"    Note: Low % is normal - not all CMDB apps are monitored")
        
        # Detailed breakdown
        cursor.execute("""
            SELECT 
                COUNT(CASE WHEN appd_application_id IS NOT NULL AND sn_sys_id IS NOT NULL THEN 1 END) as matched,
                COUNT(CASE WHEN appd_application_id IS NOT NULL AND sn_sys_id IS NULL THEN 1 END) as appd_only,
                COUNT(CASE WHEN appd_application_id IS NULL AND sn_sys_id IS NOT NULL THEN 1 END) as snow_only,
                COUNT(*) as total
            FROM applications_dim
        """)
        stats = cursor.fetchone()
        
        print(f"\n    Application Breakdown:")
        print(f"    • Matched (AppD + ServiceNow): {stats[0]}")
        print(f"    • AppD Only (no CMDB match): {stats[1]}")
        print(f"    • ServiceNow Only (not monitored): {stats[2]}")
        print(f"    • Total Application Records: {stats[3]}")
        
    except Exception as e:
        print(f"❌ Reconciliation validation failed: {e}")
        validation_passed = False
    
    # 3. Check data freshness
    print("\n3. DATA FRESHNESS:")
    print("-" * 70)
    
    try:
        cursor.execute("""
            SELECT 
                job_name,
                MAX(finished_at) as last_run,
                MAX(CASE WHEN status = 'success' THEN finished_at END) as last_success,
                MAX(CASE WHEN status = 'failed' THEN finished_at END) as last_failure
            FROM etl_execution_log
            GROUP BY job_name
            ORDER BY MAX(finished_at) DESC
        """)
        
        for row in cursor.fetchall():
            job_name, last_run, last_success, last_failure = row
            
            if last_success:
                print(f"  ✅ {job_name:<25} Last success: {last_success}")
            elif last_failure:
                print(f"  ❌ {job_name:<25} Last run failed: {last_failure}")
                validation_passed = False
            else:
                print(f"  ⚠️  {job_name:<25} No successful runs yet")
    
    except Exception as e:
        print(f"  ⚠️  Could not check data freshness: {e}")
    
    # 4. Check for orphaned records
    print("\n4. DATA QUALITY CHECKS:")
    print("-" * 70)
    
    try:
        # Check for usage records without corresponding cost records
        cursor.execute("""
            SELECT COUNT(*) FROM license_usage_fact luf
            WHERE NOT EXISTS (
                SELECT 1 FROM license_cost_fact lcf 
                WHERE lcf.app_id = luf.app_id 
                AND lcf.ts = luf.ts 
                AND lcf.capability_id = luf.capability_id
            )
            AND luf.ts >= NOW() - INTERVAL '90 days'
        """)
        orphaned_usage = cursor.fetchone()[0]
        status = "✅" if orphaned_usage == 0 else "⚠️ "
        print(f"{status} Orphaned usage records (no cost): {orphaned_usage}")
        
        if orphaned_usage > 100:
            print(f"    ⚠️  High number of orphaned records - check price_config")
            validation_passed = False
    
    except Exception as e:
        print(f"  ⚠️  Orphaned records check failed: {e}")
    
    # 5. Check forecast coverage
    try:
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
            status = "✅" if coverage >= 70 else "⚠️ "
            print(f"{status} Forecast coverage: {apps_with_forecasts}/{apps_with_usage} apps ({coverage:.1f}%)")
            
            if coverage < 70:
                print(f"    ⚠️  Target is 70%+ coverage for reliable forecasting")
        else:
            print("⚠️  No usage data available for forecasting")
    
    except Exception as e:
        print(f"  ⚠️  Forecast coverage check failed: {e}")
    
    # 6. Check reconciliation quality
    print("\n5. RECONCILIATION QUALITY:")
    print("-" * 70)
    
    try:
        cursor.execute("""
            SELECT 
                COUNT(CASE WHEN match_status = 'auto_matched' THEN 1 END) as auto_matched,
                COUNT(CASE WHEN match_status = 'needs_review' THEN 1 END) as needs_review,
                COUNT(CASE WHEN match_status = 'conflict' THEN 1 END) as conflicts,
                COUNT(*) as total_attempts
            FROM reconciliation_log
        """)
        recon_stats = cursor.fetchone()
        
        if recon_stats and recon_stats[3] > 0:
            auto_matched, needs_review, conflicts, total = recon_stats
            auto_rate = (auto_matched / total * 100)
            status = "✅" if auto_rate >= 70 else "⚠️ "
            print(f"{status} Auto-matched: {auto_matched}/{total} attempts ({auto_rate:.1f}%)")
            
            if needs_review > 0:
                print(f"⚠️  Needs manual review: {needs_review} matches")
            
            if conflicts > 0:
                print(f"⚠️  Conflicts detected: {conflicts} cases")
                print(f"    Check reconciliation_log for details")
        else:
            print("ℹ️  No reconciliation attempts logged yet")
            print("   This is normal if reconciliation hasn't run")
    
    except Exception as e:
        print(f"  ⚠️  Reconciliation quality check failed: {e}")
    
    # 7. Cost calculation accuracy
    print("\n6. COST CALCULATION ACCURACY:")
    print("-" * 70)
    
    try:
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
            WHERE luf.ts >= NOW() - INTERVAL '30 days'
        """)
        cost_check = cursor.fetchone()
        
        if cost_check and cost_check[0] and cost_check[1]:
            expected = float(cost_check[0])
            actual = float(cost_check[1])
            diff_pct = abs(expected - actual) / expected * 100 if expected > 0 else 0
            
            status = "✅" if diff_pct < 1 else "⚠️ "
            print(f"{status} Cost calculation variance: {diff_pct:.2f}%")
            print(f"    Expected: ${expected:,.2f}")
            print(f"    Actual:   ${actual:,.2f}")
            
            if diff_pct >= 1:
                print(f"    ⚠️  Variance exceeds 1% - check price_config alignment")
                validation_passed = False
        else:
            print("⚠️  Unable to validate cost calculations (insufficient data)")
    
    except Exception as e:
        print(f"  ⚠️  Cost accuracy check failed: {e}")
    
    # 8. Check for missing reference data
    print("\n7. REFERENCE DATA COMPLETENESS:")
    print("-" * 70)
    
    try:
        # Check capabilities_dim
        cursor.execute("SELECT COUNT(*) FROM capabilities_dim")
        cap_count = cursor.fetchone()[0]
        status = "✅" if cap_count >= 2 else "❌"
        print(f"{status} Capabilities: {cap_count} (need APM, MRUM at minimum)")
        
        if cap_count < 2:
            validation_passed = False
        
        # Check price_config
        cursor.execute("SELECT COUNT(*) FROM price_config WHERE NOW()::date BETWEEN start_date AND COALESCE(end_date, NOW()::date)")
        price_count = cursor.fetchone()[0]
        status = "✅" if price_count >= 2 else "❌"
        print(f"{status} Active price configs: {price_count}")
        
        if price_count < 2:
            validation_passed = False
        
        # Check sectors_dim
        cursor.execute("SELECT COUNT(*) FROM sectors_dim")
        sector_count = cursor.fetchone()[0]
        status = "✅" if sector_count > 0 else "⚠️ "
        print(f"{status} Sectors: {sector_count}")
        
    except Exception as e:
        print(f"  ⚠️  Reference data check failed: {e}")
    
    # Summary
    print("=" * 70)
    
    if validation_passed:
        print("✅ VALIDATION PASSED - Pipeline is healthy!")
        print("\nAll critical checks passed. Data quality is good.")
    else:
        print("⚠️  VALIDATION WARNINGS - Review issues above")
        print("\nSome quality checks failed. Pipeline may need attention.")
    
    print("=" * 70)
    
    cursor.close()
    conn.close()
    
    # Return exit code
    return 0 if validation_passed else 1

if __name__ == '__main__':
    exit_code = validate_pipeline()
    sys.exit(exit_code)
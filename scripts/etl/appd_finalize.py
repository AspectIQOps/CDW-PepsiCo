#!/usr/bin/env python3
"""
AppDynamics Finalize - Phase 3: Chargeback, Allocation, and Forecasting
Runs AFTER ServiceNow enrichment provides CMDB fields (cost_center, sector_id, owner_id)
"""
import psycopg2
import os
import sys

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

def get_conn():
    """Establish database connection"""
    try:
        return psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        raise

def generate_chargeback(conn):
    """
    Generate monthly chargeback records from cost data
    Requires CMDB enrichment (cost_center, sector_id, owner_id)
    """
    print("\n[Phase 3.1] Generating Chargeback Records")
    print("-" * 70)
    
    cur = conn.cursor()

    # Check if we have enriched data
    cur.execute("""
        SELECT COUNT(*) FROM applications_dim 
        WHERE appd_application_id IS NOT NULL 
        AND sn_sys_id IS NOT NULL
    """)
    enriched_count = cur.fetchone()[0]
    
    if enriched_count == 0:
        print("  ⚠️  No enriched applications found")
        print("     Run snow_enrichment.py first")
        cur.close()
        return 0

    print(f"  INFO:  Processing chargeback for {enriched_count} enriched applications")

    cur.execute("""
        INSERT INTO chargeback_fact
        (month_start, app_id, cost_center, sector_id, owner_id, usd_amount, chargeback_cycle)
        SELECT
            DATE_TRUNC('month', lcf.ts)::date AS month_start,
            lcf.app_id,
            ad.cost_center,
            ad.sector_id,
            ad.owner_id,
            SUM(lcf.usd_cost) AS usd_amount,
            'direct' AS chargeback_cycle
        FROM license_cost_fact lcf
        JOIN applications_dim ad ON ad.app_id = lcf.app_id
        WHERE ad.appd_application_id IS NOT NULL
        GROUP BY DATE_TRUNC('month', lcf.ts)::date, lcf.app_id,
                 ad.cost_center, ad.sector_id, ad.owner_id
        ON CONFLICT (month_start, app_id, sector_id)
        DO UPDATE SET
            usd_amount = EXCLUDED.usd_amount,
            cost_center = EXCLUDED.cost_center,
            owner_id = EXCLUDED.owner_id,
            chargeback_cycle = EXCLUDED.chargeback_cycle
    """)

    rows = cur.rowcount
    conn.commit()
    
    # Report on cost_center coverage
    cur.execute("""
        SELECT 
            COUNT(*) as total_apps,
            COUNT(CASE WHEN cost_center IS NOT NULL THEN 1 END) as apps_with_cost_center,
            COUNT(CASE WHEN cost_center IS NULL THEN 1 END) as apps_without_cost_center
        FROM applications_dim
        WHERE appd_application_id IS NOT NULL
    """)
    cost_center_stats = cur.fetchone()
    
    cost_center_coverage = (cost_center_stats[1] / cost_center_stats[0] * 100) if cost_center_stats[0] > 0 else 0
    
    cur.close()
    
    print(f"  ✅ Generated {rows} chargeback records")
    print(f"\n  H-Code Coverage:")
    print(f"    • Apps with Cost Center: {cost_center_stats[1]}/{cost_center_stats[0]} ({cost_center_coverage:.1f}%)")
    print(f"    • Apps without Cost Center: {cost_center_stats[2]}")
    
    if cost_center_coverage < 90:
        print(f"  ⚠️  Cost Center coverage below 90% target")
        print(f"     PepsiCo should populate cost_center field in ServiceNow")
    
    return rows

def generate_forecasts(conn):
    """
    Generate 12-month forecasts using simple linear regression
    Based on last 90 days of usage data
    """
    print("\n[Phase 3.2] Generating Usage Forecasts")
    print("-" * 70)
    
    cur = conn.cursor()

    # Simple linear projection: next 12 months based on trend
    # IDEMPOTENT: Uses ON CONFLICT to update forecasts as usage patterns change
    cur.execute("""
        WITH recent_usage AS (
            SELECT
                app_id,
                capability_id,
                tier,
                AVG(units_consumed) as avg_units,
                STDDEV(units_consumed) as stddev_units
            FROM license_usage_fact
            WHERE ts >= NOW() - INTERVAL '90 days'
            GROUP BY app_id, capability_id, tier
            HAVING COUNT(*) >= 30
        )
        INSERT INTO forecast_fact
        (month_start, app_id, capability_id, tier, projected_units,
         projected_cost, confidence_interval_low, confidence_interval_high, method)
        SELECT
            (DATE_TRUNC('month', NOW()) + (n || ' month')::interval)::date,
            ru.app_id,
            ru.capability_id,
            ru.tier,
            ROUND(ru.avg_units * 30, 2) as projected_units,
            ROUND(ru.avg_units * 30 * p.unit_rate, 2) as projected_cost,
            ROUND((ru.avg_units - COALESCE(ru.stddev_units, 0)) * 30, 2) as ci_low,
            ROUND((ru.avg_units + COALESCE(ru.stddev_units, 0)) * 30, 2) as ci_high,
            'linear_trend'
        FROM recent_usage ru
        CROSS JOIN generate_series(1, 12) n
        JOIN price_config p ON p.capability_id = ru.capability_id
            AND p.tier = ru.tier
            AND NOW()::date BETWEEN p.start_date AND COALESCE(p.end_date, NOW()::date)
        ON CONFLICT (month_start, app_id, capability_id, tier)
        DO UPDATE SET
            projected_units = EXCLUDED.projected_units,
            projected_cost = EXCLUDED.projected_cost,
            confidence_interval_low = EXCLUDED.confidence_interval_low,
            confidence_interval_high = EXCLUDED.confidence_interval_high,
            method = EXCLUDED.method
    """)

    rows = cur.rowcount
    conn.commit()
    cur.close()
    
    print(f"  ✅ Generated {rows} forecast records (12 months ahead)")
    
    return rows

def refresh_dashboard_views(conn):
    """
    Refresh materialized views for dashboard performance
    """
    print("\n[Phase 3.3] Refreshing Dashboard Views")
    print("-" * 70)
    
    cur = conn.cursor()

    try:
        # Check if materialized views exist
        cur.execute("""
            SELECT COUNT(*) FROM pg_matviews 
            WHERE schemaname = 'public' 
            AND matviewname IN ('mv_monthly_cost_summary', 'mv_app_cost_current')
        """)
        view_count = cur.fetchone()[0]
        
        if view_count > 0:
            cur.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_cost_summary")
            cur.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY mv_app_cost_current")
            print(f"  ✅ Refreshed {view_count} materialized views")
        else:
            print("  INFO:  No materialized views configured yet")

    except Exception as e:
        print(f"  ⚠️  Warning: Failed to refresh views: {e}")
        conn.rollback()
    finally:
        cur.close()

def generate_summary_report(conn):
    """Generate pipeline execution summary"""
    print("\n" + "=" * 70)
    print("PIPELINE EXECUTION SUMMARY")
    print("=" * 70)
    
    cur = conn.cursor()
    
    # Application counts
    cur.execute("""
        SELECT 
            COUNT(*) as total_apps,
            COUNT(CASE WHEN appd_application_id IS NOT NULL THEN 1 END) as appd_apps,
            COUNT(CASE WHEN sn_sys_id IS NOT NULL THEN 1 END) as snow_apps,
            COUNT(CASE WHEN appd_application_id IS NOT NULL 
                       AND sn_sys_id IS NOT NULL THEN 1 END) as matched_apps
        FROM applications_dim
    """)
    app_stats = cur.fetchone()
    
    print(f"\nSUMMARY: Applications:")
    print(f"  • Total records: {app_stats[0]}")
    print(f"  • AppDynamics apps: {app_stats[1]}")
    print(f"  • ServiceNow enriched: {app_stats[2]}")
    print(f"  • Fully matched: {app_stats[3]}")
    
    # Data volume
    cur.execute("""
        SELECT 
            (SELECT COUNT(*) FROM license_usage_fact) as usage_records,
            (SELECT COUNT(*) FROM license_cost_fact) as cost_records,
            (SELECT COUNT(*) FROM chargeback_fact) as chargeback_records,
            (SELECT COUNT(*) FROM forecast_fact) as forecast_records
    """)
    data_stats = cur.fetchone()
    
    print(f"\n📈 Data Volume:")
    print(f"  • Usage records: {data_stats[0]:,}")
    print(f"  • Cost records: {data_stats[1]:,}")
    print(f"  • Chargeback records: {data_stats[2]:,}")
    print(f"  • Forecast records: {data_stats[3]:,}")
    
    # Cost summary
    cur.execute("""
        SELECT 
            SUM(usd_cost) as total_cost,
            DATE_TRUNC('month', MIN(ts)) as earliest_data,
            DATE_TRUNC('month', MAX(ts)) as latest_data
        FROM license_cost_fact
    """)
    cost_stats = cur.fetchone()
    
    if cost_stats and cost_stats[0]:
        print(f"\n Cost Summary:")
        print(f"  • Total costs tracked: ${cost_stats[0]:,.2f}")
        print(f"  • Data range: {cost_stats[1].date()} to {cost_stats[2].date()}")
    
    # Cost Center coverage
    cur.execute("""
        SELECT 
            COUNT(*) as total,
            COUNT(CASE WHEN cost_center IS NOT NULL THEN 1 END) as with_cost_center
        FROM applications_dim
        WHERE appd_application_id IS NOT NULL
    """)
    cost_center_stats = cur.fetchone()
    
    cost_center_pct = (cost_center_stats[1] / cost_center_stats[0] * 100) if cost_center_stats[0] > 0 else 0
    
    print(f"\n🏢 Chargeback Readiness:")
    print(f"  • Cost Center coverage: {cost_center_stats[1]}/{cost_center_stats[0]} ({cost_center_pct:.1f}%)")
    
    if cost_center_pct >= 90:
        print(f"  ✅ Ready for production chargeback")
    else:
        print(f"  ⚠️  Below 90% target - PepsiCo should populate Cost Centers")
    
    # Recent ETL runs
    cur.execute("""
        SELECT job_name, status, started_at, finished_at
        FROM etl_execution_log
        WHERE started_at > NOW() - INTERVAL '1 day'
        ORDER BY started_at DESC
        LIMIT 10
    """)

    print(f"\n🔄 Recent ETL Runs:")
    for row in cur.fetchall():
        job_name, status, started_at, finished_at = row
        status_icon = "✅" if status == "success" else ("⏳" if status == "running" else "❌")
        finished_str = str(finished_at) if finished_at else "Running..."
        print(f"  {status_icon} {job_name:<25} Started: {started_at}, Finished: {finished_str}")
    
    print("=" * 70)
    
    cur.close()

def run_appd_finalize():
    """Phase 3: Generate chargeback, allocations, and forecasts"""
    print("=" * 70)
    print("AppDynamics Finalize - Phase 3: Analytics & Chargeback")
    print("=" * 70)
    print()

    conn = None
    run_id = None

    try:
        # Connect to database
        conn = get_conn()
        print("✅ Database connected\n")

        # Log ETL start
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('appd_finalize', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cur.fetchone()[0]
        conn.commit()
        cur.close()

        # Generate chargeback records
        chargeback_rows = generate_chargeback(conn)

        # Generate forecasts
        forecast_rows = generate_forecasts(conn)

        # Refresh dashboard views
        refresh_dashboard_views(conn)

        # Update ETL log
        cur = conn.cursor()
        cur.execute("""
            UPDATE etl_execution_log
            SET finished_at = NOW(),
                status = 'success',
                rows_ingested = %s
            WHERE run_id = %s
        """, (chargeback_rows + forecast_rows, run_id))
        conn.commit()
        cur.close()

        # Generate summary report
        generate_summary_report(conn)

        print("\n✅ Phase 3 Complete: Pipeline Finalized")
        print("=" * 70)

    except Exception as e:
        print("\n" + "=" * 70)
        print(f"❌ FATAL ERROR: {e}")
        print("=" * 70)
        import traceback
        traceback.print_exc()

        # Update ETL log with error
        if conn and run_id:
            try:
                cur = conn.cursor()
                cur.execute("""
                    UPDATE etl_execution_log
                    SET finished_at = NOW(),
                        status = 'failed',
                        error_message = %s
                    WHERE run_id = %s
                """, (str(e), run_id))
                conn.commit()
                cur.close()
            except:
                pass

        sys.exit(1)

    finally:
        if conn:
            conn.close()

if __name__ == '__main__':
    run_appd_finalize()
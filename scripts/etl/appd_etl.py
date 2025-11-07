#!/usr/bin/env python3
"""AppDynamics ETL - Mock Data Generator with Automatic Cost Calculation"""
import psycopg2
import os
import time
import random
import sys
from datetime import datetime, timedelta

# Configuration
DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_NAME = os.getenv('DB_NAME', 'appd_licensing')
DB_USER = os.getenv('DB_USER', 'appd_ro')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'appd_pass')

MOCK_END = datetime.now()
MOCK_START = MOCK_END - timedelta(days=90)

# Apps that will match ServiceNow data with high confidence
APPS = [
    {"name": "E-Commerce", "team": "Retail", "owner": "Alice Johnson"},
    {"name": "SAP Enterprise Services", "team": "Enterprise", "owner": "Bob Williams"},
    {"name": "PeopleSoft HRMS", "team": "Human Resources", "owner": "Carol Davis"},
    {"name": "Retail POS (Point of Sale)", "team": "Retail", "owner": "David Chen"},
    {"name": "Workday Enterprise Services", "team": "Human Resources", "owner": "Emma Martinez"},
    {"name": "ServiceNow Enterprise Services", "team": "IT Services", "owner": "Frank Thompson"}
]

def get_conn():
    """Establish database connection with retry logic"""
    for i in range(5):
        try:
            return psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD
            )
        except: 
            if i < 4:
                time.sleep(2**i)
            else:
                raise

def upsert_apps(conn):
    """Upsert mock applications into applications_dim"""
    cur = conn.cursor()
    for app in APPS:
        cur.execute(
            "SELECT app_id FROM applications_dim WHERE appd_application_name = %s",
            (app['name'],)
        )
        result = cur.fetchone()
        if result:
            app['id'] = result[0]
        else:
            cur.execute("""
                INSERT INTO applications_dim 
                (appd_application_name, owner_id, sector_id, architecture_id)
                VALUES (%s, 1, 1, 2) 
                RETURNING app_id
            """, (app['name'],))
            app['id'] = cur.fetchone()[0]
    conn.commit()
    cur.close()
    return APPS

def insert_usage(conn, apps):
    """Generate and insert mock usage data"""
    cur = conn.cursor()
    
    # Get capability IDs
    cur.execute("SELECT capability_id, capability_code FROM capabilities_dim")
    caps = {row[1]: row[0] for row in cur.fetchall()}
    
    # Generate usage data
    data = []
    current = MOCK_START
    while current <= MOCK_END:
        for app in apps:
            for cap_code in ['APM', 'MRUM']:
                tier = random.choice(['PEAK', 'PRO'])
                units = round(random.uniform(50, 500), 2)
                nodes = random.randint(5, 50)
                data.append((current, app['id'], caps[cap_code], tier, units, nodes))
        current += timedelta(days=1)
    
    # Insert usage records
    cur.executemany("""
        INSERT INTO license_usage_fact 
        (ts, app_id, capability_id, tier, units_consumed, nodes_count)
        VALUES (%s, %s, %s, %s, %s, %s)
        ON CONFLICT DO NOTHING
    """, data)
    
    conn.commit()
    cur.close()
    print(f"✅ Inserted {len(data)} usage records")

def calculate_costs(conn):
    """
    Calculate costs from usage using price_config
    This runs after usage data is inserted to ensure all costs are calculated
    """
    cur = conn.cursor()
    
    print("💰 Calculating costs from usage data...")
    
    # Calculate costs by joining usage with pricing rules
    cur.execute("""
        INSERT INTO license_cost_fact (ts, app_id, capability_id, tier, usd_cost, price_id)
        SELECT 
            u.ts,
            u.app_id,
            u.capability_id,
            u.tier,
            ROUND((u.units_consumed * p.unit_rate)::numeric, 2) AS usd_cost,
            p.price_id
        FROM license_usage_fact u
        JOIN price_config p 
            ON u.capability_id = p.capability_id
            AND u.tier = p.tier
            AND u.ts::date BETWEEN p.start_date AND COALESCE(p.end_date, u.ts::date)
        WHERE NOT EXISTS (
            SELECT 1 
            FROM license_cost_fact c
            WHERE c.app_id = u.app_id
              AND c.capability_id = u.capability_id
              AND c.tier = u.tier
              AND c.ts = u.ts
        )
    """)
    
    rows = cur.rowcount
    conn.commit()
    cur.close()
    print(f"✅ Calculated costs for {rows} usage records")
    return rows

def generate_chargeback(conn):
    """
    Generate monthly chargeback records from cost data
    Aggregates costs by month, application, and sector
    """
    cur = conn.cursor()
    
    print("📊 Generating chargeback records...")
    
    cur.execute("""
        INSERT INTO chargeback_fact 
        (month_start, app_id, h_code, sector_id, owner_id, usd_amount)
        SELECT 
            DATE_TRUNC('month', lcf.ts)::date AS month_start,
            lcf.app_id,
            ad.h_code,
            ad.sector_id,
            ad.owner_id,
            SUM(lcf.usd_cost) AS usd_amount
        FROM license_cost_fact lcf
        JOIN applications_dim ad ON ad.app_id = lcf.app_id
        GROUP BY DATE_TRUNC('month', lcf.ts)::date, lcf.app_id, 
                 ad.h_code, ad.sector_id, ad.owner_id
        ON CONFLICT (month_start, app_id, sector_id) 
        DO UPDATE SET
            usd_amount = EXCLUDED.usd_amount,
            h_code = EXCLUDED.h_code,
            owner_id = EXCLUDED.owner_id
    """)
    
    rows = cur.rowcount
    conn.commit()
    cur.close()
    print(f"✅ Generated {rows} chargeback records")
    return rows

def generate_forecasts(conn):
    """
    Generate 12-month forecasts using simple linear regression
    Based on last 90 days of usage data
    """
    cur = conn.cursor()
    
    print("📈 Generating usage forecasts...")
    
    # Simple linear projection: next 12 months based on trend
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
        WHERE NOT EXISTS (
            SELECT 1 FROM forecast_fact ff
            WHERE ff.month_start = (DATE_TRUNC('month', NOW()) + (n || ' month')::interval)::date
              AND ff.app_id = ru.app_id
              AND ff.capability_id = ru.capability_id
              AND ff.tier = ru.tier
        )
    """)
    
    rows = cur.rowcount
    conn.commit()
    cur.close()
    print(f"✅ Generated {rows} forecast records (12 months ahead)")
    return rows

def refresh_dashboard_views(conn):
    """
    Refresh materialized views for dashboard performance
    """
    cur = conn.cursor()
    
    print("🔄 Refreshing dashboard views...")
    
    try:
        # Refresh materialized views if they exist
        cur.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_cost_summary")
        cur.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY mv_app_cost_current")
        print("✅ Dashboard views refreshed successfully")
        
    except Exception as e:
        print(f"⚠️  Warning: Failed to refresh views: {e}")
        conn.rollback()
    finally:
        cur.close()

def run_appd_etl():
    """Main ETL orchestration function"""
    print("=" * 60)
    print("AppDynamics ETL Starting (Mock Data)")
    print("=" * 60)
    
    conn = None
    run_id = None
    
    try:
        # Step 1: Connect to database
        conn = get_conn()
        
        # Step 2: Log ETL start in etl_execution_log
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('appd_etl', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        
        # Step 3: Upsert applications
        apps = upsert_apps(conn)
        print(f"✅ Processed {len(apps)} applications")
        
        # Step 4: Generate and insert usage data
        insert_usage(conn, apps)
        
        # Step 5: Calculate costs from usage
        cost_rows = calculate_costs(conn)
        
        # Step 6: Generate chargeback records
        chargeback_rows = generate_chargeback(conn)
        
        # Step 7: Generate forecasts
        forecast_rows = generate_forecasts(conn)
        
        # Step 8: Refresh dashboard views
        refresh_dashboard_views(conn)
        
        # Step 9: Update ETL log
        cur = conn.cursor()
        cur.execute("""
            UPDATE etl_execution_log 
            SET finished_at = NOW(), 
                status = 'success',
                rows_ingested = %s
            WHERE run_id = %s
        """, (cost_rows + chargeback_rows + forecast_rows, run_id))
        conn.commit()
        cur.close()
        
        # Summary
        days = (MOCK_END - MOCK_START).days + 1
        print("=" * 60)
        print(f"✅ ETL Complete: {len(apps)} apps, {days} days of data")
        print("   • Usage records generated")
        print("   • Costs calculated")
        print("   • Chargebacks aggregated")
        print("   • Forecasts generated (12 months)")
        print("   • Dashboard views refreshed")
        print("=" * 60)
        
    except Exception as e:
        print("=" * 60)
        print(f"❌ FATAL ERROR: {e}")
        print("=" * 60)
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
    finally:
        if conn:
            conn.close()

if __name__ == '__main__':
    run_appd_etl()
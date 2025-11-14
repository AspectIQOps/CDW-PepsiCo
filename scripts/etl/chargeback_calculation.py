#!/usr/bin/env python3
"""
Chargeback Calculation Engine
Aggregates license costs into monthly chargeback records by sector and H-code

PIPELINE POSITION: Runs AFTER appd_finalize.py, BEFORE allocation_engine.py
- appd_finalize.py creates license_cost_fact from usage data
- chargeback_calculation.py aggregates costs into monthly chargeback_fact
- allocation_engine.py distributes shared service costs

WHAT THIS DOES:
- Reads daily license_cost_fact records
- Aggregates by month + app + sector + h_code
- Inserts into chargeback_fact with 'direct' cycle type
- Validates coverage and reports gaps
"""
import psycopg2
from datetime import datetime
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

def calculate_direct_chargebacks(conn):
    """
    Calculate direct monthly chargebacks for all applications.
    
    Aggregates daily license_cost_fact into monthly chargeback_fact.
    Uses sector and H-code from applications_dim (enriched by ServiceNow).
    """
    cursor = conn.cursor()
    
    print("\n[Chargeback Calculation] Aggregating costs into monthly chargebacks")
    print("-" * 70)
    
    # Get distinct months that have cost data
    cursor.execute("""
        SELECT DISTINCT DATE_TRUNC('month', ts)::date as month_start
        FROM license_cost_fact
        ORDER BY month_start DESC
    """)
    
    months = [row[0] for row in cursor.fetchall()]
    
    if not months:
        print("  ⚠️  No cost data found in license_cost_fact")
        print("     Run appd_finalize.py first to generate costs")
        cursor.close()
        return 0
    
    print(f"  ℹ️  Found {len(months)} months with cost data")
    print(f"     Range: {months[-1]} to {months[0]}")
    
    records_inserted = 0
    records_updated = 0
    
    for month_start in months:
        print(f"\n  Processing {month_start}...")
        
        # Calculate monthly costs per app with sector and H-code attribution
        cursor.execute("""
            WITH monthly_costs AS (
                SELECT 
                    %s as month_start,
                    lc.app_id,
                    COALESCE(a.h_code, 'Unknown') as h_code,
                    COALESCE(a.sector_id, 1) as sector_id,  -- Default to 'Unassigned' sector (ID=1)
                    COALESCE(a.owner_id, 1) as owner_id,    -- Default to 'Unassigned' owner
                    SUM(lc.usd_cost) as usd_amount,
                    'direct' as chargeback_cycle
                FROM license_cost_fact lc
                JOIN applications_dim a ON lc.app_id = a.app_id
                WHERE DATE_TRUNC('month', lc.ts) = %s
                GROUP BY lc.app_id, a.h_code, a.sector_id, a.owner_id
            )
            INSERT INTO chargeback_fact 
            (month_start, app_id, h_code, sector_id, owner_id, usd_amount, chargeback_cycle)
            SELECT * FROM monthly_costs
            ON CONFLICT (month_start, app_id, sector_id) 
            DO UPDATE SET
                usd_amount = EXCLUDED.usd_amount,
                h_code = EXCLUDED.h_code,
                owner_id = EXCLUDED.owner_id,
                chargeback_cycle = EXCLUDED.chargeback_cycle
            RETURNING (xmax = 0) AS inserted
        """, (month_start, month_start))
        
        results = cursor.fetchall()
        inserted = sum(1 for r in results if r[0])  # True = insert, False = update
        updated = len(results) - inserted
        
        records_inserted += inserted
        records_updated += updated
        
        print(f"    ✅ {inserted} new, {updated} updated")
    
    conn.commit()
    cursor.close()
    
    print(f"\n  ✅ Total: {records_inserted} inserted, {records_updated} updated")
    return records_inserted + records_updated

def generate_chargeback_summary(conn):
    """Generate summary report of chargebacks by sector and H-code"""
    cursor = conn.cursor()
    
    print("\n[Summary Report] Current Month Chargeback Breakdown")
    print("-" * 70)
    
    # Get current month totals
    cursor.execute("""
        SELECT 
            s.sector_name,
            COUNT(DISTINCT c.app_id) as app_count,
            SUM(c.usd_amount) as total_amount,
            COUNT(CASE WHEN c.h_code IS NOT NULL AND c.h_code != 'Unknown' THEN 1 END) as apps_with_hcode
        FROM chargeback_fact c
        LEFT JOIN sectors_dim s ON c.sector_id = s.sector_id
        WHERE c.month_start = (SELECT MAX(month_start) FROM chargeback_fact)
          AND c.chargeback_cycle = 'direct'
        GROUP BY s.sector_name
        ORDER BY total_amount DESC
    """)
    
    print(f"\n{'Sector':<30} {'Apps':>6} {'H-Code':>8} {'Total Cost':>15}")
    print("-" * 70)
    
    total_apps = 0
    total_amount = 0
    total_hcode = 0
    
    for row in cursor.fetchall():
        sector = row[0][:29] if row[0] else 'Unknown'
        apps = row[1]
        amount = row[2]
        hcode = row[3]
        
        total_apps += apps
        total_amount += amount
        total_hcode += hcode
        
        print(f"{sector:<30} {apps:>6} {hcode:>8} ${amount:>13,.2f}")
    
    print("-" * 70)
    print(f"{'TOTAL':<30} {total_apps:>6} {total_hcode:>8} ${total_amount:>13,.2f}")
    print("=" * 70)
    
    cursor.close()

def validate_chargeback_coverage(conn):
    """Validate that all apps with costs have chargeback records"""
    cursor = conn.cursor()
    
    print("\n[Validation] Chargeback Coverage Check")
    print("-" * 70)
    
    # Check for apps with costs but no chargeback
    cursor.execute("""
        WITH cost_apps AS (
            SELECT DISTINCT app_id, DATE_TRUNC('month', ts)::date as month_start
            FROM license_cost_fact
            WHERE ts >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
        ),
        chargeback_apps AS (
            SELECT DISTINCT app_id, month_start
            FROM chargeback_fact
            WHERE month_start >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
        )
        SELECT 
            COUNT(DISTINCT ca.app_id) as apps_with_costs,
            COUNT(DISTINCT cba.app_id) as apps_with_chargeback,
            COUNT(DISTINCT ca.app_id) - COUNT(DISTINCT cba.app_id) as missing
        FROM cost_apps ca
        LEFT JOIN chargeback_apps cba ON ca.app_id = cba.app_id AND ca.month_start = cba.month_start
    """)
    
    stats = cursor.fetchone()
    
    print(f"  Apps with costs (current month): {stats[0]}")
    print(f"  Apps with chargeback records: {stats[1]}")
    
    if stats[2] > 0:
        print(f"  ⚠️  Missing chargeback for {stats[2]} apps!")
    else:
        print(f"  ✅ All apps have chargeback records")
    
    # H-code coverage
    cursor.execute("""
        SELECT 
            COUNT(*) as total_records,
            COUNT(CASE WHEN h_code IS NULL OR h_code = 'Unknown' THEN 1 END) as missing_hcode,
            COUNT(CASE WHEN h_code IS NOT NULL AND h_code != 'Unknown' THEN 1 END) as with_hcode
        FROM chargeback_fact
        WHERE month_start = (SELECT MAX(month_start) FROM chargeback_fact)
          AND chargeback_cycle = 'direct'
    """)
    
    hcode_stats = cursor.fetchone()
    hcode_pct = (hcode_stats[2] / hcode_stats[0] * 100) if hcode_stats[0] > 0 else 0
    
    print(f"\n  H-Code Coverage:")
    print(f"    With H-Code: {hcode_stats[2]} ({hcode_pct:.1f}%)")
    print(f"    Missing/Unknown: {hcode_stats[1]}")
    
    if hcode_pct < 80:
        print(f"    ⚠️  H-code coverage below 80%")
        print(f"       This is expected in test environments")
        print(f"       Production: Populate h_code via ServiceNow or AppD tags")
    else:
        print(f"    ✅ Good H-code coverage")
    
    # Sector distribution
    cursor.execute("""
        SELECT 
            s.sector_name,
            COUNT(*) as record_count
        FROM chargeback_fact c
        LEFT JOIN sectors_dim s ON c.sector_id = s.sector_id
        WHERE c.month_start = (SELECT MAX(month_start) FROM chargeback_fact)
          AND c.chargeback_cycle = 'direct'
        GROUP BY s.sector_name
        ORDER BY record_count DESC
    """)
    
    print(f"\n  Sector Distribution:")
    for row in cursor.fetchall():
        print(f"    {row[0]:<30} {row[1]:>6} records")
    
    cursor.close()

def run_chargeback_calculation():
    """Main chargeback calculation orchestration"""
    print("=" * 70)
    print("Chargeback Calculation Engine Starting")
    print("=" * 70)
    
    conn = None
    run_id = None
    
    try:
        # Step 1: Connect to database
        conn = get_conn()
        print("✅ Database connected")
        
        # Step 2: Log ETL start
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('chargeback_calculation', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cursor.fetchone()[0]
        conn.commit()
        cursor.close()
        
        # Step 3: Calculate direct chargebacks
        records = calculate_direct_chargebacks(conn)
        
        if records == 0:
            print("\n⚠️  No chargeback records created")
            print("   Check that appd_finalize.py has run successfully")
            raise Exception("No cost data available for chargeback calculation")
        
        # Step 4: Validate coverage
        validate_chargeback_coverage(conn)
        
        # Step 5: Generate summary report
        generate_chargeback_summary(conn)
        
        # Step 6: Update ETL log
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE etl_execution_log 
            SET finished_at = NOW(), 
                status = 'success',
                rows_ingested = %s
            WHERE run_id = %s
        """, (records, run_id))
        conn.commit()
        cursor.close()
        
        print("\n" + "=" * 70)
        print("✅ Chargeback Calculation Complete")
        print(f"   {records} chargeback records processed")
        print("=" * 70)
        print("\nℹ️  Next Steps:")
        print("   1. allocation_engine.py will distribute shared service costs")
        print("   2. refresh_views.py will update dashboard materialized views")
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
                cursor = conn.cursor()
                cursor.execute("""
                    UPDATE etl_execution_log 
                    SET finished_at = NOW(), 
                        status = 'failed',
                        error_message = %s
                    WHERE run_id = %s
                """, (str(e), run_id))
                conn.commit()
                cursor.close()
            except:
                pass
        
        sys.exit(1)
        
    finally:
        if conn:
            conn.close()

if __name__ == '__main__':
    run_chargeback_calculation()
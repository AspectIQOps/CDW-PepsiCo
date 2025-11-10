#!/usr/bin/env python3
"""
Allocation Rules Engine - Shared Service Cost Distribution
Distributes costs for shared/platform services across business sectors
"""
import psycopg2
from datetime import datetime
import os
import json

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

def get_conn():
    return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)

def seed_allocation_rules(conn):
    """Seed default allocation rules if they don't exist"""
    cursor = conn.cursor()
    
    rules = [
        {
            'rule_name': 'Platform Services - Proportional',
            'distribution_method': 'proportional_usage',
            'shared_service_code': 'PLATFORM',
            'applies_to_sector_id': None,
            'is_active': True
        },
        {
            'rule_name': 'Global IT - Equal Split',
            'distribution_method': 'equal_split',
            'shared_service_code': 'GLOBAL_IT',
            'applies_to_sector_id': None,
            'is_active': True
        },
        {
            'rule_name': 'Shared Services - Custom Formula',
            'distribution_method': 'custom_formula',
            'shared_service_code': 'SHARED_SVC',
            'applies_to_sector_id': None,
            'is_active': True
        }
    ]
    
    for rule in rules:
        cursor.execute("""
            INSERT INTO allocation_rules 
            (rule_name, distribution_method, shared_service_code, applies_to_sector_id, is_active)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT DO NOTHING
        """, (rule['rule_name'], rule['distribution_method'], 
              rule['shared_service_code'], rule['applies_to_sector_id'], 
              rule['is_active']))
    
    conn.commit()
    cursor.close()

def identify_shared_services(conn):
    """Identify applications that are shared services"""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT 
            app_id,
            COALESCE(appd_application_name, sn_service_name) as app_name,
            h_code,
            s.sector_name
        FROM applications_dim a
        JOIN sectors_dim s ON s.sector_id = a.sector_id
        WHERE 
            s.sector_name IN ('Corporate/Shared Services', 'Global IT')
            OR h_code ILIKE '%PLATFORM%'
            OR h_code ILIKE '%SHARED%'
            OR h_code ILIKE '%GLOBAL%'
    """)
    
    shared_services = cursor.fetchall()
    cursor.close()
    
    return shared_services

def proportional_allocation(conn, shared_app_id, month_start):
    """Allocate shared service costs proportionally based on each sector's usage"""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT SUM(usd_cost)
        FROM license_cost_fact
        WHERE app_id = %s
          AND DATE_TRUNC('month', ts) = %s
    """, (shared_app_id, month_start))
    
    total_cost = cursor.fetchone()[0] or 0
    
    if total_cost == 0:
        cursor.close()
        return 0
    
    cursor.execute("""
        SELECT 
            a.sector_id,
            SUM(u.units_consumed) as sector_usage
        FROM license_usage_fact u
        JOIN applications_dim a ON a.app_id = u.app_id
        WHERE DATE_TRUNC('month', u.ts) = %s
          AND a.sector_id != (SELECT sector_id FROM applications_dim WHERE app_id = %s)
        GROUP BY a.sector_id
    """, (month_start, shared_app_id))
    
    sector_usage = cursor.fetchall()
    total_usage = sum([row[1] for row in sector_usage])
    
    if total_usage == 0:
        cursor.close()
        return 0
    
    allocations = 0
    for sector_id, usage in sector_usage:
        allocated_amount = total_cost * (usage / total_usage)
        
        cursor.execute("""
            INSERT INTO chargeback_fact 
            (month_start, app_id, sector_id, owner_id, usd_amount, chargeback_cycle)
            VALUES (%s, %s, %s, 1, %s, 'allocated_shared_service')
            ON CONFLICT (month_start, app_id, sector_id) 
            DO UPDATE SET
                usd_amount = chargeback_fact.usd_amount + EXCLUDED.usd_amount
        """, (month_start, shared_app_id, sector_id, round(allocated_amount, 2)))
        allocations += 1
    
    conn.commit()
    cursor.close()
    return allocations

def equal_split_allocation(conn, shared_app_id, month_start):
    """Allocate shared service costs equally across all active sectors"""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT SUM(usd_cost)
        FROM license_cost_fact
        WHERE app_id = %s
          AND DATE_TRUNC('month', ts) = %s
    """, (shared_app_id, month_start))
    
    total_cost = cursor.fetchone()[0] or 0
    
    if total_cost == 0:
        cursor.close()
        return 0
    
    cursor.execute("""
        SELECT DISTINCT sector_id
        FROM applications_dim
        WHERE sector_id != (SELECT sector_id FROM applications_dim WHERE app_id = %s)
    """, (shared_app_id,))
    
    active_sectors = [row[0] for row in cursor.fetchall()]
    
    if len(active_sectors) == 0:
        cursor.close()
        return 0
    
    per_sector_cost = total_cost / len(active_sectors)
    
    for sector_id in active_sectors:
        cursor.execute("""
            INSERT INTO chargeback_fact 
            (month_start, app_id, sector_id, owner_id, usd_amount, chargeback_cycle)
            VALUES (%s, %s, %s, 1, %s, 'allocated_equal_split')
            ON CONFLICT (month_start, app_id, sector_id) 
            DO UPDATE SET
                usd_amount = chargeback_fact.usd_amount + EXCLUDED.usd_amount
        """, (month_start, shared_app_id, sector_id, round(per_sector_cost, 2)))
    
    conn.commit()
    cursor.close()
    return len(active_sectors)

def custom_formula_allocation(conn, shared_app_id, month_start):
    """Custom allocation formula - 40% proportional, 60% equal split"""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT SUM(usd_cost)
        FROM license_cost_fact
        WHERE app_id = %s
          AND DATE_TRUNC('month', ts) = %s
    """, (shared_app_id, month_start))
    
    total_cost = cursor.fetchone()[0] or 0
    
    if total_cost == 0:
        cursor.close()
        return 0
    
    proportional_portion = total_cost * 0.4
    
    cursor.execute("""
        SELECT 
            a.sector_id,
            SUM(u.units_consumed) as sector_usage
        FROM license_usage_fact u
        JOIN applications_dim a ON a.app_id = u.app_id
        WHERE DATE_TRUNC('month', u.ts) = %s
          AND a.sector_id != (SELECT sector_id FROM applications_dim WHERE app_id = %s)
        GROUP BY a.sector_id
    """, (month_start, shared_app_id))
    
    sector_usage = cursor.fetchall()
    total_usage = sum([row[1] for row in sector_usage])
    
    equal_portion = total_cost * 0.6
    active_sectors = [row[0] for row in sector_usage]
    per_sector_equal = equal_portion / len(active_sectors) if active_sectors else 0
    
    allocations = 0
    for sector_id, usage in sector_usage:
        proportional_share = proportional_portion * (usage / total_usage) if total_usage > 0 else 0
        total_allocation = proportional_share + per_sector_equal
        
        cursor.execute("""
            INSERT INTO chargeback_fact 
            (month_start, app_id, sector_id, owner_id, usd_amount, chargeback_cycle)
            VALUES (%s, %s, %s, 1, %s, 'allocated_custom_formula')
            ON CONFLICT (month_start, app_id, sector_id) 
            DO UPDATE SET
                usd_amount = chargeback_fact.usd_amount + EXCLUDED.usd_amount
        """, (month_start, shared_app_id, sector_id, round(total_allocation, 2)))
        allocations += 1
    
    conn.commit()
    cursor.close()
    return allocations

def apply_allocation_rules(conn):
    """Apply all active allocation rules for the current month"""
    print("💰 Applying allocation rules for shared services...")
    
    seed_allocation_rules(conn)
    shared_services = identify_shared_services(conn)
    
    if not shared_services:
        print("⚠️  No shared services identified")
        return 0
    
    print(f"Found {len(shared_services)} shared service(s)")
    
    month_start = datetime.now().replace(day=1).date()
    
    cursor = conn.cursor()
    cursor.execute("""
        SELECT rule_id, distribution_method, shared_service_code
        FROM allocation_rules
        WHERE is_active = true
    """)
    
    active_rules = cursor.fetchall()
    cursor.close()
    
    allocations_made = 0
    
    for app_id, app_name, h_code, sector_name in shared_services:
        print(f"  Allocating costs for: {app_name} (H-code: {h_code})")
        
        for rule_id, method, service_code in active_rules:
            if h_code and service_code in h_code:
                if method == 'proportional_usage':
                    count = proportional_allocation(conn, app_id, month_start)
                elif method == 'equal_split':
                    count = equal_split_allocation(conn, app_id, month_start)
                elif method == 'custom_formula':
                    count = custom_formula_allocation(conn, app_id, month_start)
                
                allocations_made += count
                break
    
    print(f"✅ Applied {allocations_made} allocation rules")
    return allocations_made

def generate_allocation_report(conn):
    """Generate summary of allocated costs"""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT 
            s.sector_name,
            SUM(CASE WHEN chargeback_cycle LIKE 'allocated%' THEN usd_amount ELSE 0 END) as allocated_costs,
            SUM(CASE WHEN chargeback_cycle NOT LIKE 'allocated%' THEN usd_amount ELSE 0 END) as direct_costs,
            SUM(usd_amount) as total_costs
        FROM chargeback_fact c
        JOIN sectors_dim s ON s.sector_id = c.sector_id
        WHERE month_start = DATE_TRUNC('month', NOW())
        GROUP BY s.sector_name
        ORDER BY total_costs DESC
    """)
    
    print("\n" + "="*70)
    print("ALLOCATION SUMMARY - Current Month")
    print("="*70)
    print(f"{'Sector':<30} {'Direct':<15} {'Allocated':<15} {'Total':<15}")
    print("-"*70)
    
    for row in cursor.fetchall():
        print(f"{row[0]:<30} ${row[2]:>12,.2f} ${row[1]:>12,.2f} ${row[3]:>12,.2f}")
    
    print("="*70)
    
    cursor.close()

def run_allocation():
    """Main allocation orchestration function"""
    print("=" * 60)
    print("Allocation Engine Starting")
    print("=" * 60)
    
    conn = None
    run_id = None
    
    try:
        # Step 1: Connect to database
        conn = get_conn()
        
        # Step 2: Log ETL start
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('allocation_engine', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cursor.fetchone()[0]
        conn.commit()
        cursor.close()
        
        # Step 3: Apply allocation rules
        allocations_made = apply_allocation_rules(conn)
        
        # Step 4: Generate report
        generate_allocation_report(conn)
        
        # Step 5: Update ETL log
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE etl_execution_log 
            SET finished_at = NOW(), 
                status = 'success',
                rows_ingested = %s
            WHERE run_id = %s
        """, (allocations_made, run_id))
        conn.commit()
        cursor.close()
        
        print("=" * 60)
        print("✅ Allocation Complete")
        print("=" * 60)
        
    except Exception as e:
        print("=" * 60)
        print(f"❌ FATAL: {e}")
        print("=" * 60)
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
    finally:
        if conn:
            conn.close()

if __name__ == '__main__':
    run_allocation()
#!/usr/bin/env python3
"""
Reconciliation Engine - Fuzzy Matching Between AppD and ServiceNow
Run after both appd_etl.py and snow_etl.py complete

FIXED: Handles duplicate appd_application_id constraint properly
"""
import psycopg2
from difflib import SequenceMatcher
from datetime import datetime
import os

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

def fuzzy_match_score(str1, str2):
    """Calculate similarity score (0-100)"""
    if not str1 or not str2:
        return 0
    return SequenceMatcher(None, str1.lower(), str2.lower()).ratio() * 100

def reconcile_applications(conn):
    """Match AppD apps with ServiceNow services
    
    FIXED LOGIC:
    - Instead of copying AppD fields to ServiceNow record and deleting AppD record,
    - We now UPDATE the AppD record with ServiceNow fields and update foreign keys
    - This prevents unique constraint violations
    """
    cursor = conn.cursor()
    
    # Get unmatched AppD applications (have AppD data but no ServiceNow link)
    cursor.execute("""
        SELECT app_id, appd_application_name, appd_application_id
        FROM applications_dim 
        WHERE sn_sys_id IS NULL AND appd_application_name IS NOT NULL
    """)
    appd_apps = cursor.fetchall()
    
    # Get unmatched ServiceNow services (have ServiceNow data but no AppD link)
    cursor.execute("""
        SELECT app_id, sn_sys_id, sn_service_name, owner_id, sector_id, 
               architecture_id, h_code, support_group
        FROM applications_dim 
        WHERE appd_application_id IS NULL AND sn_service_name IS NOT NULL
    """)
    snow_services = cursor.fetchall()
    
    matches_made = 0
    
    for appd_id, appd_name, appd_application_id in appd_apps:
        best_match = None
        best_score = 0
        
        for snow_record in snow_services:
            snow_id = snow_record[0]
            snow_sys_id = snow_record[1]
            snow_name = snow_record[2]
            
            score = fuzzy_match_score(appd_name, snow_name)
            if score > best_score:
                best_score = score
                best_match = snow_record
        
        # Auto-match threshold: 80%
        if best_score >= 80:
            (snow_id, snow_sys_id, snow_name, owner_id, sector_id, 
             architecture_id, h_code, support_group) = best_match
            
            # FIXED APPROACH: Update the AppD record with ServiceNow enrichment data
            # This keeps the appd_application_id unique and adds ServiceNow metadata
            
            # First, check if this sn_sys_id is already assigned to another app
            cursor.execute("""
                SELECT app_id, appd_application_name 
                FROM applications_dim 
                WHERE sn_sys_id = %s AND app_id != %s
            """, (snow_sys_id, appd_id))
            existing = cursor.fetchone()
            
            if existing:
                # Another AppD app already claimed this ServiceNow record
                # Log this as a conflict and skip
                print(f"   ⚠️  Conflict: {appd_name} matches {snow_name}, but already matched to {existing[1]}")
                cursor.execute("""
                    INSERT INTO reconciliation_log 
                    (source_a, source_b, match_key_a, match_key_b, confidence_score, match_status, notes)
                    VALUES ('AppDynamics', 'ServiceNow', %s, %s, %s, 'conflict', %s)
                """, (appd_name, snow_name, best_score, 
                      f"ServiceNow app already matched to {existing[1]}"))
                continue
            
            # Safe to update - no conflict
            cursor.execute("""
                UPDATE applications_dim 
                SET sn_sys_id = %s,
                    sn_service_name = %s,
                    owner_id = %s,
                    sector_id = %s,
                    architecture_id = %s,
                    h_code = %s,
                    support_group = %s,
                    updated_at = NOW()
                WHERE app_id = %s
            """, (snow_sys_id, snow_name, owner_id, sector_id, 
                  architecture_id, h_code, support_group, appd_id))
            
            # Now delete the ServiceNow-only record since we've merged its data
            cursor.execute("DELETE FROM applications_dim WHERE app_id = %s", (snow_id,))
            
            # Update any foreign key references that pointed to the deleted ServiceNow record
            # (though there shouldn't be any since it had no AppD data)
            cursor.execute("""
                UPDATE license_usage_fact
                SET app_id = %s
                WHERE app_id = %s
            """, (appd_id, snow_id))
            
            cursor.execute("""
                UPDATE license_cost_fact
                SET app_id = %s
                WHERE app_id = %s
            """, (appd_id, snow_id))
            
            cursor.execute("""
                UPDATE chargeback_fact
                SET app_id = %s
                WHERE app_id = %s
            """, (appd_id, snow_id))
            
            cursor.execute("""
                UPDATE forecast_fact
                SET app_id = %s
                WHERE app_id = %s
            """, (appd_id, snow_id))
            
            # Log the match
            cursor.execute("""
                INSERT INTO reconciliation_log 
                (source_a, source_b, match_key_a, match_key_b, confidence_score, match_status, resolved_app_id)
                VALUES ('AppDynamics', 'ServiceNow', %s, %s, %s, 'auto_matched', %s)
            """, (appd_name, snow_name, best_score, appd_id))
            
            matches_made += 1
            # Remove matched ServiceNow service from available list
            snow_services = [s for s in snow_services if s[0] != snow_id]
        
        # Manual review threshold: 50-80%
        elif best_score >= 50:
            cursor.execute("""
                INSERT INTO reconciliation_log 
                (source_a, source_b, match_key_a, match_key_b, confidence_score, match_status)
                VALUES ('AppDynamics', 'ServiceNow', %s, %s, %s, 'needs_review')
            """, (appd_name, best_match[2], best_score))
    
    conn.commit()
    cursor.close()
    
    print(f"✅ Reconciliation complete: {matches_made} automatic matches")
    return matches_made

def generate_reconciliation_report(conn):
    """Generate summary report of match status"""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT 
            COUNT(CASE WHEN appd_application_id IS NOT NULL AND sn_sys_id IS NOT NULL THEN 1 END) as matched,
            COUNT(CASE WHEN appd_application_id IS NOT NULL AND sn_sys_id IS NULL THEN 1 END) as appd_only,
            COUNT(CASE WHEN appd_application_id IS NULL AND sn_sys_id IS NOT NULL THEN 1 END) as snow_only,
            COUNT(*) as total
        FROM applications_dim
    """)
    
    stats = cursor.fetchone()
    match_rate = (stats[0] / stats[3] * 100) if stats[3] > 0 else 0
    
    print("=" * 60)
    print("RECONCILIATION REPORT")
    print("=" * 60)
    print(f"Matched Applications: {stats[0]}")
    print(f"AppD Only (unmatched): {stats[1]}")
    print(f"ServiceNow Only (unmatched): {stats[2]}")
    print(f"Total Applications: {stats[3]}")
    print(f"Match Rate: {match_rate:.1f}%")
    
    # AppD-specific match rate
    cursor.execute("""
        SELECT 
            COUNT(*) as total_appd_apps,
            COUNT(CASE WHEN sn_sys_id IS NOT NULL THEN 1 END) as matched_appd_apps
        FROM applications_dim
        WHERE appd_application_id IS NOT NULL
    """)
    appd_stats = cursor.fetchone()
    
    if appd_stats and appd_stats[0] > 0:
        appd_match_rate = (appd_stats[1] / appd_stats[0] * 100)
        print(f"\nAppD Applications Match Rate: {appd_match_rate:.1f}% ({appd_stats[1]}/{appd_stats[0]} apps)")
        print("(This is the key metric - % of monitored apps matched to CMDB)")
    
    print("=" * 60)
    
    cursor.close()
    return match_rate

def run_reconciliation():
    """Main reconciliation orchestration function"""
    print("=" * 60)
    print("Reconciliation Engine Starting")
    print("=" * 60)
    
    conn = None
    run_id = None
    
    try:
        # Step 1: Connect to database
        conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)
        
        # Step 2: Log ETL start
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('reconciliation_engine', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cursor.fetchone()[0]
        conn.commit()
        cursor.close()
        
        # Step 3: Perform reconciliation
        matches_made = reconcile_applications(conn)
        
        # Step 4: Generate report
        match_rate = generate_reconciliation_report(conn)
        
        # Step 5: Update ETL log
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE etl_execution_log 
            SET finished_at = NOW(), 
                status = 'success',
                rows_ingested = %s
            WHERE run_id = %s
        """, (matches_made, run_id))
        conn.commit()
        cursor.close()
        
        if match_rate < 95:
            print(f"⚠️  Overall match rate {match_rate:.1f}% is below 95% target")
            print("    (This is expected when ServiceNow has more apps than AppDynamics monitors)")
        
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
    run_reconciliation()
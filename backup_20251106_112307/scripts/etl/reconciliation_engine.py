#!/usr/bin/env python3
"""
Reconciliation Engine - Fuzzy Matching Between AppD and ServiceNow
Run after both appd_etl.py and snow_etl.py complete
"""
import psycopg2
from difflib import SequenceMatcher
from datetime import datetime
import os

DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_NAME = os.getenv('DB_NAME', 'appd_licensing')
DB_USER = os.getenv('DB_USER', 'appd_ro')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'appd_pass')

def fuzzy_match_score(str1, str2):
    """Calculate similarity score (0-100)"""
    if not str1 or not str2:
        return 0
    return SequenceMatcher(None, str1.lower(), str2.lower()).ratio() * 100

def reconcile_applications(conn):
    """Match AppD apps with ServiceNow services"""
    cursor = conn.cursor()
    
    # Get unmatched AppD applications (have AppD data but no ServiceNow link)
    cursor.execute("""
        SELECT app_id, appd_application_name 
        FROM applications_dim 
        WHERE sn_sys_id IS NULL AND appd_application_name IS NOT NULL
    """)
    appd_apps = cursor.fetchall()
    
    # Get unmatched ServiceNow services (have ServiceNow data but no AppD link)
    cursor.execute("""
        SELECT app_id, sn_sys_id, sn_service_name 
        FROM applications_dim 
        WHERE appd_application_id IS NULL AND sn_service_name IS NOT NULL
    """)
    snow_services = cursor.fetchall()
    
    matches_made = 0
    
    for appd_id, appd_name in appd_apps:
        best_match = None
        best_score = 0
        
        for snow_id, snow_sys_id, snow_name in snow_services:
            score = fuzzy_match_score(appd_name, snow_name)
            if score > best_score:
                best_score = score
                best_match = (snow_id, snow_sys_id, snow_name)
        
        # Auto-match threshold: 80%
        if best_score >= 80:
            snow_id, snow_sys_id, snow_name = best_match
            
            # FIXED: Merge the two records properly
            # Strategy: Instead of copying sn_sys_id to AppD record (which violates unique constraint),
            # we'll do the opposite - copy AppD data to ServiceNow record, then delete AppD record
            
            # Step 1: Copy AppD fields to the ServiceNow record
            cursor.execute("""
                UPDATE applications_dim 
                SET appd_application_id = (SELECT appd_application_id FROM applications_dim WHERE app_id = %s),
                    appd_application_name = (SELECT appd_application_name FROM applications_dim WHERE app_id = %s),
                    updated_at = NOW()
                WHERE app_id = %s
            """, (appd_id, appd_id, snow_id))
            
            # Step 2: Update any foreign key references that point to the AppD record
            # to now point to the ServiceNow record (which now has both sets of data)
            
            # Update usage facts (move from AppD record to ServiceNow record)
            cursor.execute("""
                UPDATE license_usage_fact
                SET app_id = %s
                WHERE app_id = %s
            """, (snow_id, appd_id))
            
            # Update cost facts
            cursor.execute("""
                UPDATE license_cost_fact
                SET app_id = %s
                WHERE app_id = %s
            """, (snow_id, appd_id))
            
            # Update chargeback facts
            cursor.execute("""
                UPDATE chargeback_fact
                SET app_id = %s
                WHERE app_id = %s
            """, (snow_id, appd_id))
            
            # Update forecast facts
            cursor.execute("""
                UPDATE forecast_fact
                SET app_id = %s
                WHERE app_id = %s
            """, (snow_id, appd_id))
            
            # Step 3: Log the successful match BEFORE deleting the AppD record
            cursor.execute("""
                INSERT INTO reconciliation_log 
                (source_a, source_b, match_key_a, match_key_b, confidence_score, match_status, resolved_app_id)
                VALUES ('AppDynamics', 'ServiceNow', %s, %s, %s, 'auto_matched', %s)
            """, (appd_name, snow_name, best_score, snow_id))
            
            # Step 4: Now safe to delete the AppD-only record
            cursor.execute("DELETE FROM applications_dim WHERE app_id = %s", (appd_id,))
            
            matches_made += 1
            
            # Remove this matched ServiceNow service from the list to avoid re-matching
            snow_services = [(sid, ssid, sname) for sid, ssid, sname in snow_services if sid != snow_id]
        
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
    
    # Additional detail: Show match rate for apps with AppD monitoring
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

if __name__ == '__main__':
    conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)
    try:
        reconcile_applications(conn)
        match_rate = generate_reconciliation_report(conn)
        
        if match_rate < 95:
            print(f"⚠️  Overall match rate {match_rate:.1f}% is below 95% target")
            print("    (This is expected when ServiceNow has more apps than AppDynamics monitors)")
    finally:
        conn.close()
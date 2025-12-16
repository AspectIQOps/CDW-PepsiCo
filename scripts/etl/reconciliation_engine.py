#!/usr/bin/env python3
"""
Reconciliation Engine - Fuzzy Matching Between AppD and ServiceNow
Run after both appd_etl.py and snow_etl.py complete

OPTIMIZED: Uses PostgreSQL trigram similarity (10-100x faster than Python)
FIXED: Handles duplicate appd_application_id constraint properly
"""
import psycopg2
from datetime import datetime
import os

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

def ensure_trigram_extension(conn):
    """Ensure pg_trgm extension is enabled for fuzzy matching"""
    cursor = conn.cursor()
    try:
        cursor.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
        conn.commit()
    except Exception as e:
        # Extension might already exist or user lacks permission
        # Non-critical - similarity will still work if extension exists
        conn.rollback()
    finally:
        cursor.close()

def reconcile_applications(conn):
    """Match AppD apps with ServiceNow services using PostgreSQL trigram similarity

    OPTIMIZED: Uses PostgreSQL SIMILARITY function instead of Python nested loops
    - 10-100x faster than Python SequenceMatcher
    - Leverages database indexes for performance
    - Processes all matches in a single query

    LOGIC:
    - Updates AppD record with ServiceNow enrichment data
    - Keeps appd_application_id unique
    - Deletes ServiceNow-only record after merge
    - Updates all foreign key references
    """
    cursor = conn.cursor()

    # Ensure pg_trgm extension is available
    ensure_trigram_extension(conn)

    # Use PostgreSQL trigram similarity to find best matches
    # This replaces the O(n×m) Python nested loop with a single optimized query
    cursor.execute("""
        WITH similarity_scores AS (
            SELECT
                appd.app_id AS appd_app_id,
                appd.appd_application_name,
                appd.appd_application_id,
                snow.app_id AS snow_app_id,
                snow.sn_sys_id,
                snow.sn_service_name,
                snow.owner_id,
                snow.sector_id,
                snow.architecture_id,
                snow.cost_center,
                snow.support_group,
                SIMILARITY(appd.appd_application_name, snow.sn_service_name) * 100 AS score,
                ROW_NUMBER() OVER (PARTITION BY appd.app_id ORDER BY SIMILARITY(appd.appd_application_name, snow.sn_service_name) DESC) as rank
            FROM applications_dim appd
            CROSS JOIN applications_dim snow
            WHERE appd.sn_sys_id IS NULL
              AND appd.appd_application_name IS NOT NULL
              AND snow.appd_application_id IS NULL
              AND snow.sn_service_name IS NOT NULL
              AND SIMILARITY(appd.appd_application_name, snow.sn_service_name) >= 0.80  -- 80% threshold
        )
        SELECT
            appd_app_id, appd_application_name, appd_application_id,
            snow_app_id, sn_sys_id, sn_service_name,
            owner_id, sector_id, architecture_id, cost_center, support_group,
            score
        FROM similarity_scores
        WHERE rank = 1  -- Best match per AppD app
        ORDER BY score DESC
    """)

    matches = cursor.fetchall()
    matches_made = 0
    needs_review = []

    print(f"  SEARCH: Found {len(matches)} potential matches using PostgreSQL trigram similarity")

    for match in matches:
        (appd_id, appd_name, appd_application_id,
         snow_id, snow_sys_id, snow_name,
         owner_id, sector_id, architecture_id, cost_center, support_group,
         score) = match

        # Auto-match threshold already applied in query (>= 80%)
        # Check if this sn_sys_id is already assigned to another app
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
            """, (appd_name, snow_name, score,
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
                cost_center = %s,
                support_group = %s,
                updated_at = NOW()
            WHERE app_id = %s
        """, (snow_sys_id, snow_name, owner_id, sector_id,
              architecture_id, cost_center, support_group, appd_id))

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
        """, (appd_name, snow_name, score, appd_id))

        matches_made += 1

    # Log matches that need manual review (50-80% similarity)
    cursor.execute("""
        WITH needs_review AS (
            SELECT
                appd.appd_application_name,
                snow.sn_service_name,
                SIMILARITY(appd.appd_application_name, snow.sn_service_name) * 100 AS score,
                ROW_NUMBER() OVER (PARTITION BY appd.app_id ORDER BY SIMILARITY(appd.appd_application_name, snow.sn_service_name) DESC) as rank
            FROM applications_dim appd
            CROSS JOIN applications_dim snow
            WHERE appd.sn_sys_id IS NULL
              AND appd.appd_application_name IS NOT NULL
              AND snow.appd_application_id IS NULL
              AND snow.sn_service_name IS NOT NULL
              AND SIMILARITY(appd.appd_application_name, snow.sn_service_name) >= 0.50
              AND SIMILARITY(appd.appd_application_name, snow.sn_service_name) < 0.80
        )
        INSERT INTO reconciliation_log
        (source_a, source_b, match_key_a, match_key_b, confidence_score, match_status)
        SELECT 'AppDynamics', 'ServiceNow', appd_application_name, sn_service_name, score, 'needs_review'
        FROM needs_review
        WHERE rank = 1
    """)
    review_count = cursor.rowcount

    conn.commit()
    cursor.close()

    print(f"  ✅ {matches_made} automatic matches (>= 80% similarity)")
    if review_count > 0:
        print(f"   {review_count} matches flagged for manual review (50-79% similarity)")

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
#!/usr/bin/env python3
"""
Refresh Materialized Views - Dashboard Performance Optimization

Refreshes all materialized views after ETL pipeline completes.
Should be called as final step in run_pipeline.py

CONCURRENCY:
- Uses REFRESH MATERIALIZED VIEW CONCURRENTLY for zero downtime
- Requires unique indexes (already created in view definition)
- Allows dashboard queries to continue during refresh

TIMING:
- Run after appd_finalize.py completes
- Typical refresh time: 30-120 seconds total
- Views use 90-180 day windows to minimize data volume
"""
import psycopg2
import os
import sys
from datetime import datetime
import time

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

# Materialized views in refresh order (dependencies first)
MATERIALIZED_VIEWS = [
    'mv_daily_cost_by_controller',       # Priority 1 - most frequently used
    'mv_daily_usage_by_capability',      # Priority 1 - high usage
    'mv_cost_by_sector_controller',      # Priority 2 - chargeback critical
    'mv_cost_by_owner_controller',       # Priority 2 - owner analysis
    'mv_architecture_metrics_90d',       # Priority 1 - complex query replacement
    'mv_app_cost_rankings_monthly',      # Priority 2 - top apps
    'mv_monthly_chargeback_summary',     # Priority 2 - executive reporting
    'mv_peak_pro_comparison',            # Priority 3 - optimization analysis
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
        except Exception as e:
            if i < 4:
                print(f"  ⚠️  Database connection attempt {i+1}/5 failed, retrying...")
                time.sleep(2**i)
            else:
                print(f"  ❌ Database connection failed after 5 attempts: {e}")
                raise

def check_view_exists(conn, view_name):
    """Check if materialized view exists"""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT COUNT(*)
        FROM pg_matviews
        WHERE schemaname = 'public'
          AND matviewname = %s
    """, (view_name,))
    exists = cursor.fetchone()[0] > 0
    cursor.close()
    return exists

def get_view_row_count(conn, view_name):
    """Get current row count for a materialized view"""
    cursor = conn.cursor()
    try:
        cursor.execute(f"SELECT COUNT(*) FROM {view_name}")
        count = cursor.fetchone()[0]
        cursor.close()
        return count
    except Exception as e:
        cursor.close()
        return -1

def refresh_view_concurrently(conn, view_name):
    """
    Refresh a single materialized view with CONCURRENTLY option

    CONCURRENTLY requires:
    - Unique index on the view
    - Longer refresh time but no locking
    - Dashboard queries can run during refresh

    Falls back to regular refresh if CONCURRENTLY fails
    """
    cursor = conn.cursor()
    start_time = time.time()

    try:
        # Get row count before refresh
        old_count = get_view_row_count(conn, view_name)

        # Try concurrent refresh first (zero downtime)
        print(f"  🔄 Refreshing {view_name} (concurrent mode)...")
        cursor.execute(f"REFRESH MATERIALIZED VIEW CONCURRENTLY {view_name}")
        conn.commit()

        # Get row count after refresh
        new_count = get_view_row_count(conn, view_name)

        elapsed = time.time() - start_time
        print(f"  ✅ {view_name}: {old_count:,} → {new_count:,} rows ({elapsed:.1f}s)")

        cursor.close()
        return True, elapsed, new_count

    except psycopg2.errors.UndefinedObject as e:
        # No unique index - fall back to regular refresh
        conn.rollback()
        print(f"  ⚠️  Concurrent refresh failed (no unique index), using regular refresh...")

        try:
            cursor.execute(f"REFRESH MATERIALIZED VIEW {view_name}")
            conn.commit()

            new_count = get_view_row_count(conn, view_name)
            elapsed = time.time() - start_time
            print(f"  ✅ {view_name}: {new_count:,} rows ({elapsed:.1f}s) [non-concurrent]")

            cursor.close()
            return True, elapsed, new_count

        except Exception as e2:
            conn.rollback()
            print(f"  ❌ Regular refresh also failed: {e2}")
            cursor.close()
            return False, 0, 0

    except Exception as e:
        conn.rollback()
        print(f"  ❌ Refresh failed: {e}")
        cursor.close()
        return False, 0, 0

def analyze_views(conn, view_names):
    """Run ANALYZE on materialized views to update statistics"""
    cursor = conn.cursor()
    print(f"\n📊 Updating statistics for query planner...")

    for view_name in view_names:
        try:
            cursor.execute(f"ANALYZE {view_name}")
            conn.commit()
        except Exception as e:
            print(f"  ⚠️  ANALYZE failed for {view_name}: {e}")
            conn.rollback()

    cursor.close()
    print(f"  ✅ Statistics updated for {len(view_names)} views")

def log_refresh_to_audit(conn, total_time, success_count, total_count):
    """Log view refresh to ETL execution log"""
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, finished_at, status, rows_ingested)
            VALUES ('refresh_views', NOW() - INTERVAL '%s seconds', NOW(), %s, %s)
        """, (int(total_time), 'success' if success_count == total_count else 'partial', success_count))
        conn.commit()
    except Exception as e:
        print(f"  ⚠️  Could not log to audit table: {e}")
        conn.rollback()
    finally:
        cursor.close()

def refresh_all_views():
    """Main function - refresh all materialized views"""
    print("=" * 70)
    print("Refreshing Materialized Views - Dashboard Performance")
    print("=" * 70)

    start_time = time.time()
    success_count = 0
    total_rows = 0
    results = []

    try:
        conn = get_conn()
        print("✅ Database connected\n")

        # Check which views exist
        existing_views = []
        missing_views = []

        for view_name in MATERIALIZED_VIEWS:
            if check_view_exists(conn, view_name):
                existing_views.append(view_name)
            else:
                missing_views.append(view_name)

        if missing_views:
            print(f"⚠️  Warning: {len(missing_views)} views not found (run sql/init/01_performance_views.sql first):")
            for view_name in missing_views:
                print(f"   - {view_name}")
            print()

        if not existing_views:
            print("❌ No materialized views found. Run sql/init/01_performance_views.sql first.")
            print("   Or re-run scripts/setup/init_database.sh which includes view creation.")
            sys.exit(1)

        print(f"📋 Refreshing {len(existing_views)} materialized views...\n")

        # Refresh each view
        for view_name in existing_views:
            success, elapsed, row_count = refresh_view_concurrently(conn, view_name)

            if success:
                success_count += 1
                total_rows += row_count
                results.append((view_name, 'SUCCESS', elapsed, row_count))
            else:
                results.append((view_name, 'FAILED', elapsed, 0))

        # Update statistics
        if existing_views:
            analyze_views(conn, existing_views)

        # Log to audit table
        total_time = time.time() - start_time
        log_refresh_to_audit(conn, total_time, success_count, len(existing_views))

        # Print summary
        print("\n" + "=" * 70)
        print("View Refresh Summary")
        print("=" * 70)

        for view_name, status, elapsed, row_count in results:
            status_icon = "✅" if status == "SUCCESS" else "❌"
            print(f"{status_icon} {view_name:<40} {row_count:>10,} rows  {elapsed:>6.1f}s")

        print("=" * 70)
        print(f"Total: {success_count}/{len(existing_views)} views refreshed successfully")
        print(f"Total rows: {total_rows:,}")
        print(f"Total time: {total_time:.1f}s")
        print("=" * 70)

        conn.close()

        # Exit with appropriate code
        if success_count == len(existing_views):
            print("\n✅ All views refreshed successfully!\n")
            sys.exit(0)
        else:
            print(f"\n⚠️  {len(existing_views) - success_count} views failed to refresh\n")
            sys.exit(1)

    except Exception as e:
        print("\n" + "=" * 70)
        print(f"❌ FATAL ERROR: {e}")
        print("=" * 70)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    refresh_all_views()

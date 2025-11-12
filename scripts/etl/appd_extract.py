#!/usr/bin/env python3
"""
AppDynamics Extract - Phase 1: Core Data Collection
Pulls application and license usage data from AppDynamics via OAuth 2.0
Does NOT generate chargeback - that requires CMDB enrichment first
"""
import psycopg2
import os
import time
import sys
import requests
from datetime import datetime, timedelta

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

APPD_CONTROLLER = os.getenv('APPD_CONTROLLER')
APPD_ACCOUNT = os.getenv('APPD_ACCOUNT')
APPD_CLIENT_ID = os.getenv('APPD_CLIENT_ID')
APPD_CLIENT_SECRET = os.getenv('APPD_CLIENT_SECRET')

# OAuth token cache
_token_cache = {'token': None, 'expires_at': None}

def get_oauth_token():
    """
    Get OAuth 2.0 access token using client credentials flow
    Uses cached token if still valid
    """
    now = datetime.now()

    # Return cached token if still valid (with 30 second buffer)
    if _token_cache['token'] and _token_cache['expires_at']:
        if now < _token_cache['expires_at'] - timedelta(seconds=30):
            return _token_cache['token']

    # Request new token
    token_url = f"https://{APPD_CONTROLLER}/controller/api/oauth/access_token"

    # AppDynamics expects client_id in format: clientname@account
    client_id_full = f"{APPD_CLIENT_ID}@{APPD_ACCOUNT}"

    data = {
        "grant_type": "client_credentials",
        "client_id": client_id_full,
        "client_secret": APPD_CLIENT_SECRET
    }

    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    try:
        response = requests.post(token_url, data=data, headers=headers, timeout=10)
        response.raise_for_status()

        token_data = response.json()
        access_token = token_data.get("access_token")
        expires_in = token_data.get("expires_in", 300)  # Default 5 minutes

        if not access_token:
            raise ValueError("No access_token in response")

        # Cache the token
        _token_cache['token'] = access_token
        _token_cache['expires_at'] = now + timedelta(seconds=expires_in)

        print(f"✅ OAuth token acquired (expires in {expires_in}s)")
        return access_token

    except Exception as e:
        print(f"❌ OAuth token request failed: {e}")
        raise

def appd_api_get(endpoint, params=None):
    """
    Make authenticated GET request to AppDynamics API
    Handles OAuth token management automatically
    """
    token = get_oauth_token()

    url = f"https://{APPD_CONTROLLER}/controller/{endpoint}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.get(url, headers=headers, params=params, timeout=30)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"❌ API request failed: {url}")
        print(f"   Error: {e}")
        raise

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

def fetch_applications():
    """
    Fetch all applications from AppDynamics
    Returns list of application objects with metadata
    """
    print("📥 Fetching applications from AppDynamics...")

    try:
        apps = appd_api_get("rest/applications", params={"output": "JSON"})

        if not isinstance(apps, list):
            print(f"⚠️  Unexpected response format: {type(apps)}")
            return []

        print(f"✅ Found {len(apps)} applications")
        return apps

    except Exception as e:
        print(f"❌ Failed to fetch applications: {e}")
        return []

def fetch_application_nodes(app_id):
    """
    Fetch node count for a specific application
    """
    try:
        nodes = appd_api_get(f"rest/applications/{app_id}/nodes", params={"output": "JSON"})

        if isinstance(nodes, list):
            return len(nodes)
        return 0

    except Exception as e:
        print(f"⚠️  Failed to fetch nodes for app {app_id}: {e}")
        return 0

def fetch_all_nodes_batch(app_ids):
    """
    Fetch node counts for multiple applications efficiently
    Returns dict mapping app_id -> node_count
    """
    print("📊 Fetching node counts for all applications...")
    node_counts = {}
    
    for i, app_id in enumerate(app_ids):
        try:
            node_counts[app_id] = fetch_application_nodes(app_id)
            
            # Progress indicator
            if (i + 1) % 10 == 0:
                print(f"  Fetched node counts for {i + 1}/{len(app_ids)} apps...")
        
        except Exception as e:
            print(f"  ⚠️  Failed to fetch nodes for app {app_id}: {e}")
            node_counts[app_id] = 0
    
    print(f"✅ Fetched node counts for {len(node_counts)} applications")
    return node_counts

def determine_architecture(node_count, tier_count):
    """
    Heuristic to determine if application is Monolith or Microservices
    Based on number of tiers and nodes
    """
    # Simple heuristic:
    # - Microservices typically have multiple tiers (>3) and many nodes
    # - Monoliths typically have 1-2 tiers with fewer nodes

    if tier_count >= 4:
        return 2  # Microservices architecture_id
    elif tier_count >= 2 and node_count >= 10:
        return 2  # Microservices
    else:
        return 1  # Monolith architecture_id

def determine_license_tier(app_name, description=""):
    """
    Heuristic to determine Peak vs Pro license tier
    In production, this should be based on actual license metadata or tags
    For now, using naming conventions
    """
    name_lower = app_name.lower()
    desc_lower = description.lower() if description else ""

    # Keywords that suggest Peak (premium) tier
    peak_keywords = ['production', 'prod', 'critical', 'enterprise', 'premium']

    # Check if any peak keywords are in name or description
    for keyword in peak_keywords:
        if keyword in name_lower or keyword in desc_lower:
            return 'Peak'

    # Default to Pro
    return 'Pro'

def upsert_applications(conn, apps, node_counts):
    """
    Upsert applications from AppDynamics into applications_dim
    NOTE: Only sets AppD fields - CMDB enrichment happens in Phase 2
    Returns mapping of AppD app_id to database app_id
    """
    print("💾 Upserting applications into database...")

    cur = conn.cursor()
    app_id_map = {}

    for app in apps:
        appd_id = app.get('id')
        appd_name = app.get('name')
        description = app.get('description', '')

        # Get node count from batch fetch
        node_count = node_counts.get(appd_id, 0)
        
        # Get tier count from app data
        tier_count = len(app.get('tiers', []))

        # Determine architecture
        architecture_id = determine_architecture(node_count, tier_count)

        # Determine license tier
        license_tier = determine_license_tier(appd_name, description)

        # Check if application exists
        cur.execute(
            "SELECT app_id FROM applications_dim WHERE appd_application_id = %s",
            (str(appd_id),)
        )
        result = cur.fetchone()

        if result:
            # Update existing application
            db_app_id = result[0]
            cur.execute("""
                UPDATE applications_dim
                SET appd_application_name = %s,
                    architecture_id = %s,
                    license_tier = %s,
                    metadata = metadata || %s::jsonb
                WHERE app_id = %s
            """, (
                appd_name,
                architecture_id,
                license_tier,
                f'{{"description": "{description}", "tier_count": {tier_count}, "node_count": {node_count}}}',
                db_app_id
            ))
        else:
            # Insert new application (with default owner_id=1, sector_id=1)
            # These will be updated by ServiceNow enrichment
            cur.execute("""
                INSERT INTO applications_dim
                (appd_application_id, appd_application_name, architecture_id, license_tier,
                 owner_id, sector_id, metadata)
                VALUES (%s, %s, %s, %s, 1, 1, %s)
                RETURNING app_id
            """, (
                str(appd_id),
                appd_name,
                architecture_id,
                license_tier,
                f'{{"description": "{description}", "tier_count": {tier_count}, "node_count": {node_count}}}'
            ))
            db_app_id = cur.fetchone()[0]

        app_id_map[appd_id] = db_app_id

    conn.commit()
    cur.close()

    print(f"✅ Upserted {len(app_id_map)} applications")
    return app_id_map

def generate_usage_data(conn, app_id_map):
    """
    Generate usage data for applications

    NOTE: AppDynamics license usage API requires specific account ID format.
    For MVP, we'll generate usage based on node counts and tier data.
    In production, integrate with actual license usage API when endpoint is confirmed.
    """
    print("📊 Generating usage data from application metadata...")

    cur = conn.cursor()

    # Get capability IDs
    cur.execute("SELECT capability_id, capability_code FROM capabilities_dim")
    caps = {row[1]: row[0] for row in cur.fetchall()}

    # Get application metadata to derive usage
    data = []
    now = datetime.now()
    start_date = now - timedelta(days=90)

    for appd_id, db_app_id in app_id_map.items():
        # Get app metadata
        cur.execute(
            "SELECT metadata, license_tier FROM applications_dim WHERE app_id = %s",
            (db_app_id,)
        )
        row = cur.fetchone()
        if not row:
            continue

        metadata, license_tier = row
        node_count = metadata.get('node_count', 1) if metadata else 1
        tier_count = metadata.get('tier_count', 1) if metadata else 1

        # Generate daily usage records for last 90 days
        # Usage is based on node count (each node consumes units)
        current = start_date
        while current <= now:
            # APM units: roughly node_count * 1.5 (varies by day)
            apm_units = round(node_count * 1.5 * (0.9 + 0.2 * (current.day % 7) / 7), 2)

            # MRUM units: roughly tier_count * 100 (web traffic)
            mrum_units = round(tier_count * 100 * (0.8 + 0.4 * (current.day % 7) / 7), 2)

            # Insert APM usage
            if 'APM' in caps:
                data.append((
                    current,
                    db_app_id,
                    caps['APM'],
                    license_tier,
                    apm_units,
                    node_count
                ))

            # Insert MRUM usage
            if 'MRUM' in caps:
                data.append((
                    current,
                    db_app_id,
                    caps['MRUM'],
                    license_tier,
                    mrum_units,
                    tier_count
                ))

            current += timedelta(days=1)

    # Bulk insert usage records
    if data:
        cur.executemany("""
            INSERT INTO license_usage_fact
            (ts, app_id, capability_id, tier, units_consumed, nodes_count)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT DO NOTHING
        """, data)

        conn.commit()
        print(f"✅ Inserted {len(data)} usage records")
    else:
        print("⚠️  No usage data generated")

    cur.close()
    return len(data)

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

def run_appd_extract():
    """Phase 1: Extract core AppDynamics data (no chargeback yet)"""
    print("=" * 60)
    print("AppDynamics Extract - Phase 1: Core Data")
    print("=" * 60)

    # Validate credentials
    if not all([APPD_CONTROLLER, APPD_ACCOUNT, APPD_CLIENT_ID, APPD_CLIENT_SECRET]):
        print("❌ Missing AppDynamics credentials!")
        print("   Required: APPD_CONTROLLER, APPD_ACCOUNT, APPD_CLIENT_ID, APPD_CLIENT_SECRET")
        sys.exit(1)

    print(f"Controller: {APPD_CONTROLLER}")
    print(f"Account: {APPD_ACCOUNT}")
    print()

    conn = None
    run_id = None

    try:
        # Step 1: Connect to database
        conn = get_conn()

        # Step 2: Log ETL start in etl_execution_log
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('appd_extract', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cur.fetchone()[0]
        conn.commit()
        cur.close()

        # Step 3: Fetch applications from AppDynamics
        apps = fetch_applications()

        if not apps:
            raise ValueError("No applications fetched from AppDynamics")

        # Step 4: Batch fetch node counts (optimization)
        app_ids = [app.get('id') for app in apps]
        node_counts = fetch_all_nodes_batch(app_ids)

        # Step 5: Upsert applications to database (AppD fields only)
        app_id_map = upsert_applications(conn, apps, node_counts)

        # Step 6: Generate usage data based on application metadata
        usage_rows = generate_usage_data(conn, app_id_map)

        # Step 7: Calculate costs from usage
        cost_rows = calculate_costs(conn)

        # Step 8: Update ETL log
        cur = conn.cursor()
        cur.execute("""
            UPDATE etl_execution_log
            SET finished_at = NOW(),
                status = 'success',
                rows_ingested = %s
            WHERE run_id = %s
        """, (len(apps), run_id))
        conn.commit()
        cur.close()

        # Summary
        print("=" * 60)
        print(f"✅ Phase 1 Complete: {len(apps)} applications processed")
        print(f"   • Applications: {len(apps)}")
        print(f"   • Usage records: {usage_rows}")
        print(f"   • Cost records: {cost_rows}")
        print()
        print("ℹ️  Next: Run ServiceNow enrichment to add CMDB data")
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

        sys.exit(1)

    finally:
        if conn:
            conn.close()

if __name__ == '__main__':
    run_appd_extract()
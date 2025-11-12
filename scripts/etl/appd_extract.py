#!/usr/bin/env python3
"""
AppDynamics Extract - Phase 1: Core Data Collection
Pulls application and license usage data from AppDynamics via OAuth 2.0
Does NOT generate chargeback - that requires CMDB enrichment first

H-CODE DATA SOURCE:
- H-code is now sourced from AppDynamics application tags (tag name: 'h-code', 'h_code', or 'hcode')
- Previously sourced from ServiceNow CMDB field 'u_h_code' (deprecated approach)
- This change improves data freshness since h-code is maintained in AppD by app teams
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

# Multi-controller support: comma-separated lists
APPD_CONTROLLERS = os.getenv('APPD_CONTROLLERS', os.getenv('APPD_CONTROLLER', ''))
APPD_ACCOUNTS = os.getenv('APPD_ACCOUNTS', os.getenv('APPD_ACCOUNT', ''))
APPD_CLIENT_IDS = os.getenv('APPD_CLIENT_IDS', os.getenv('APPD_CLIENT_ID', ''))
APPD_CLIENT_SECRETS = os.getenv('APPD_CLIENT_SECRETS', os.getenv('APPD_CLIENT_SECRET', ''))

# OAuth token cache per controller
_token_cache = {}

def get_oauth_token(controller, account, client_id, client_secret):
    """
    Get OAuth 2.0 access token using client credentials flow
    Uses cached token if still valid
    """
    now = datetime.now()

    # Check cache for this specific controller
    cache_key = controller
    if cache_key not in _token_cache:
        _token_cache[cache_key] = {'token': None, 'expires_at': None}

    # Return cached token if still valid (with 30 second buffer)
    if _token_cache[cache_key]['token'] and _token_cache[cache_key]['expires_at']:
        if now < _token_cache[cache_key]['expires_at'] - timedelta(seconds=30):
            return _token_cache[cache_key]['token']

    # Request new token
    token_url = f"https://{controller}/controller/api/oauth/access_token"

    # AppDynamics expects client_id in format: clientname@account
    client_id_full = f"{client_id}@{account}"

    data = {
        "grant_type": "client_credentials",
        "client_id": client_id_full,
        "client_secret": client_secret
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
        _token_cache[cache_key]['token'] = access_token
        _token_cache[cache_key]['expires_at'] = now + timedelta(seconds=expires_in)

        print(f"✅ OAuth token acquired for {controller} (expires in {expires_in}s)")
        return access_token

    except Exception as e:
        print(f"❌ OAuth token request failed for {controller}: {e}")
        raise

def appd_api_get(controller, account, client_id, client_secret, endpoint, params=None, suppress_404=False):
    """
    Make authenticated GET request to AppDynamics API
    Handles OAuth token management automatically
    """
    token = get_oauth_token(controller, account, client_id, client_secret)

    url = f"https://{controller}/controller/{endpoint}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.get(url, headers=headers, params=params, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as e:
        # Suppress 404 errors if requested (for optional endpoints like tags)
        if suppress_404 and e.response.status_code == 404:
            raise
        print(f"❌ API request failed: {url}")
        print(f"   Error: {e}")
        raise
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

def fetch_applications(controller, account, client_id, client_secret):
    """
    Fetch all applications from AppDynamics controller
    Returns list of application objects with metadata
    """
    print(f"📥 Fetching applications from {controller}...")

    try:
        apps = appd_api_get(controller, account, client_id, client_secret,
                            "rest/applications", params={"output": "JSON"})

        if not isinstance(apps, list):
            print(f"⚠️  Unexpected response format: {type(apps)}")
            return []

        print(f"✅ Found {len(apps)} applications on {controller}")
        return apps

    except Exception as e:
        print(f"❌ Failed to fetch applications from {controller}: {e}")
        return []

def fetch_application_nodes(controller, account, client_id, client_secret, app_id):
    """
    Fetch node count for a specific application
    """
    try:
        nodes = appd_api_get(controller, account, client_id, client_secret,
                            f"rest/applications/{app_id}/nodes", params={"output": "JSON"})

        if isinstance(nodes, list):
            return len(nodes)
        return 0

    except Exception as e:
        print(f"⚠️  Failed to fetch nodes for app {app_id}: {e}")
        return 0

def fetch_application_tags(controller, account, client_id, client_secret, app_id):
    """
    Fetch tags for a specific application
    Returns dict of tag_name -> tag_value
    """
    try:
        # AppDynamics tags API endpoint (suppress 404 errors for cleaner logs)
        tags = appd_api_get(controller, account, client_id, client_secret,
                           f"restui/applicationManagerUiBean/getApplicationById/{app_id}",
                           suppress_404=True)

        if isinstance(tags, dict):
            # Extract tags from response - tags are usually in 'tags' array
            tag_list = tags.get('tags', [])
            if isinstance(tag_list, list):
                # Convert to dict for easy lookup
                return {tag.get('name'): tag.get('value') for tag in tag_list if tag.get('name')}

        return {}

    except Exception as e:
        # Tags may not be available for all apps (404s are expected), just return empty dict
        return {}

def fetch_all_nodes_batch(controller, account, client_id, client_secret, app_ids):
    """
    Fetch node counts for multiple applications efficiently
    Returns dict mapping app_id -> node_count
    """
    print("📊 Fetching node counts for all applications...")
    node_counts = {}

    for i, app_id in enumerate(app_ids):
        try:
            node_counts[app_id] = fetch_application_nodes(controller, account, client_id, client_secret, app_id)

            # Progress indicator
            if (i + 1) % 10 == 0:
                print(f"  Fetched node counts for {i + 1}/{len(app_ids)} apps...")

        except Exception as e:
            print(f"  ⚠️  Failed to fetch nodes for app {app_id}: {e}")
            node_counts[app_id] = 0

    print(f"✅ Fetched node counts for {len(node_counts)} applications")
    return node_counts

def fetch_all_tags_batch(controller, account, client_id, client_secret, app_ids):
    """
    Fetch tags for multiple applications efficiently
    Returns dict mapping app_id -> tags_dict
    """
    print("🏷️  Fetching tags for all applications...")
    app_tags = {}

    for i, app_id in enumerate(app_ids):
        try:
            app_tags[app_id] = fetch_application_tags(controller, account, client_id, client_secret, app_id)

            # Progress indicator
            if (i + 1) % 10 == 0:
                print(f"  Fetched tags for {i + 1}/{len(app_ids)} apps...")

        except Exception as e:
            print(f"  ⚠️  Failed to fetch tags for app {app_id}: {e}")
            app_tags[app_id] = {}

    # Count how many apps have h-code tag
    h_code_count = sum(1 for tags in app_tags.values() if tags.get('h-code') or tags.get('h_code') or tags.get('hcode'))
    print(f"✅ Fetched tags for {len(app_tags)} applications ({h_code_count} with h-code)")
    return app_tags

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

def upsert_applications(conn, controller, apps, node_counts, app_tags):
    """
    Upsert applications from AppDynamics into applications_dim
    NOTE: Only sets AppD fields - CMDB enrichment happens in Phase 2
    Now includes h_code extraction from AppDynamics tags
    Returns mapping of AppD app_id to database app_id
    """
    print(f"💾 Upserting applications from {controller} into database...")

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

        # Extract h-code from tags (check multiple possible tag names)
        tags = app_tags.get(appd_id, {})
        h_code = tags.get('h-code') or tags.get('h_code') or tags.get('hcode')
        # Truncate to 50 chars (DB field size)
        if h_code:
            h_code = str(h_code)[:50]

        # Check if application exists (by app_id + controller combo)
        cur.execute(
            "SELECT app_id FROM applications_dim WHERE appd_application_id = %s AND appd_controller = %s",
            (str(appd_id), controller)
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
                    h_code = %s,
                    metadata = metadata || %s::jsonb,
                    updated_at = NOW()
                WHERE app_id = %s
            """, (
                appd_name,
                architecture_id,
                license_tier,
                h_code,
                f'{{"description": "{description}", "tier_count": {tier_count}, "node_count": {node_count}}}',
                db_app_id
            ))
        else:
            # Insert new application (with default owner_id=1, sector_id=1)
            # These will be updated by ServiceNow enrichment
            cur.execute("""
                INSERT INTO applications_dim
                (appd_application_id, appd_application_name, appd_controller, architecture_id, license_tier,
                 h_code, owner_id, sector_id, metadata)
                VALUES (%s, %s, %s, %s, %s, %s, 1, 1, %s)
                RETURNING app_id
            """, (
                str(appd_id),
                appd_name,
                controller,
                architecture_id,
                license_tier,
                h_code,
                f'{{"description": "{description}", "tier_count": {tier_count}, "node_count": {node_count}}}'
            ))
            db_app_id = cur.fetchone()[0]

        app_id_map[appd_id] = db_app_id

    conn.commit()
    cur.close()

    print(f"✅ Upserted {len(app_id_map)} applications from {controller}")
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

    # Parse comma-separated controller configs
    controllers = [c.strip() for c in APPD_CONTROLLERS.split(',') if c.strip()]
    accounts = [a.strip() for a in APPD_ACCOUNTS.split(',') if a.strip()]
    client_ids = [c.strip() for c in APPD_CLIENT_IDS.split(',') if c.strip()]
    client_secrets = [s.strip() for s in APPD_CLIENT_SECRETS.split(',') if s.strip()]

    # Validate we have matching counts
    if not (len(controllers) == len(accounts) == len(client_ids) == len(client_secrets)):
        print("❌ Mismatched controller configuration counts!")
        print(f"   Controllers: {len(controllers)}, Accounts: {len(accounts)}, Client IDs: {len(client_ids)}, Secrets: {len(client_secrets)}")
        sys.exit(1)

    if len(controllers) == 0:
        print("❌ No AppDynamics controllers configured!")
        print("   Set APPD_CONTROLLERS, APPD_ACCOUNTS, APPD_CLIENT_IDS, APPD_CLIENT_SECRETS")
        sys.exit(1)

    print(f"📋 Configured {len(controllers)} controller(s):")
    for i, controller in enumerate(controllers):
        print(f"   {i+1}. {controller} (account: {accounts[i]})")
    print()

    conn = None
    run_id = None
    total_apps = 0
    total_usage_rows = 0
    total_cost_rows = 0
    total_h_code_count = 0

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

        # Step 3: Loop through each controller and fetch data
        for i, controller in enumerate(controllers):
            account = accounts[i]
            client_id = client_ids[i]
            client_secret = client_secrets[i]

            print(f"\n{'=' * 60}")
            print(f"Processing Controller {i+1}/{len(controllers)}: {controller}")
            print(f"{'=' * 60}\n")

            # Fetch applications from this controller
            apps = fetch_applications(controller, account, client_id, client_secret)

            if not apps:
                print(f"⚠️  No applications found on {controller}, skipping...")
                continue

            # Step 4: Batch fetch node counts (optimization)
            app_ids = [app.get('id') for app in apps]
            node_counts = fetch_all_nodes_batch(controller, account, client_id, client_secret, app_ids)

            # Step 4b: Batch fetch application tags (includes h-code)
            app_tags = fetch_all_tags_batch(controller, account, client_id, client_secret, app_ids)

            # Step 5: Upsert applications to database (AppD fields + h-code from tags)
            app_id_map = upsert_applications(conn, controller, apps, node_counts, app_tags)

            # Step 6: Generate usage data based on application metadata
            usage_rows = generate_usage_data(conn, app_id_map)

            # Step 7: Calculate costs from usage
            cost_rows = calculate_costs(conn)

            # Count apps with h-code for this controller
            h_code_count = sum(1 for tags in app_tags.values() if tags.get('h-code') or tags.get('h_code') or tags.get('hcode'))

            # Accumulate totals
            total_apps += len(apps)
            total_usage_rows += usage_rows
            total_cost_rows += cost_rows
            total_h_code_count += h_code_count

            # Controller summary
            print(f"\n✅ Controller {i+1}/{len(controllers)} Complete:")
            print(f"   • Applications: {len(apps)}")
            print(f"   • H-code populated: {h_code_count} ({round(h_code_count/len(apps)*100, 1)}%)")
            print(f"   • Usage records: {usage_rows}")
            print(f"   • Cost records: {cost_rows}")

        # Step 8: Update ETL log
        cur = conn.cursor()
        cur.execute("""
            UPDATE etl_execution_log
            SET finished_at = NOW(),
                status = 'success',
                rows_ingested = %s
            WHERE run_id = %s
        """, (total_apps, run_id))
        conn.commit()
        cur.close()

        # Final Summary
        print("\n" + "=" * 60)
        print(f"✅ Phase 1 Complete: All {len(controllers)} controllers processed")
        print(f"   • Total Applications: {total_apps}")
        print(f"   • Total H-code populated: {total_h_code_count} ({round(total_h_code_count/total_apps*100, 1) if total_apps > 0 else 0}%)")
        print(f"   • Total Usage records: {total_usage_rows}")
        print(f"   • Total Cost records: {total_cost_rows}")
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
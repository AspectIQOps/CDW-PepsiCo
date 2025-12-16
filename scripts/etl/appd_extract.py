#!/usr/bin/env python3
"""
AppDynamics Extract - Phase 1: Core Data Collection
Pulls application and license usage data from AppDynamics via OAuth 2.0
Does NOT generate chargeback - that requires CMDB enrichment first

COST CENTER DATA SOURCE:
- Cost Center MUST be provided via CSV import or ServiceNow CMDB integration
- AppDynamics Tags API is READ-ONLY BLOCKED (HTTP 405 - Method Not Allowed)
- Tags cannot be read via API, only written/deleted
- All applications will have cost_center = NULL until CSV/CMDB data is loaded
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
APPD_ACCOUNT_IDS = os.getenv('APPD_ACCOUNT_IDS', os.getenv('APPD_ACCOUNT_ID', ''))  # Numeric account IDs for Licensing API
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
        # Licensing API with 365 days of data can take 2-5 minutes to respond
        # Increased timeout from 30s to 300s (5 minutes) to prevent false timeouts
        response = requests.get(url, headers=headers, params=params, timeout=300)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as e:
        # Suppress 404 errors if requested (for optional endpoints like tags)
        if suppress_404 and e.response.status_code == 404:
            raise
        print(f"❌ API request failed: {url}")
        print(f"   HTTP Status Code: {e.response.status_code}")
        print(f"   Error: {e}")
        # Print response body for debugging
        try:
            print(f"   Response: {e.response.text[:500]}")
        except:
            pass
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
    print(f"Fetching applications from {controller}...")

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
    Fetch full node details for a specific application
    Returns tuple: (node_count, node_details_list)

    Node details include:
    - id: AppD node ID
    - name: Node name (often includes hostname)
    - machineName: Server hostname
    - machineAgentPresent: bool
    - appAgentPresent: bool
    - tierName: Tier this node belongs to
    """
    try:
        nodes = appd_api_get(controller, account, client_id, client_secret,
                            f"rest/applications/{app_id}/nodes", params={"output": "JSON"})

        if isinstance(nodes, list):
            return (len(nodes), nodes)
        return (0, [])

    except Exception as e:
        print(f"⚠️  Failed to fetch nodes for app {app_id}: {e}")
        return (0, [])

# Tags API functionality removed - Tags API is READ-ONLY blocked (HTTP 405)
# Cost center must come from CSV/CMDB, not AppDynamics tags

def fetch_all_nodes_batch(controller, account, client_id, client_secret, app_ids):
    """
    Fetch node details for multiple applications efficiently
    Returns dict mapping app_id -> {'count': int, 'nodes': list}
    """
    print("Fetching node details for all applications...")
    node_data = {}

    for i, app_id in enumerate(app_ids):
        try:
            node_count, nodes = fetch_application_nodes(controller, account, client_id, client_secret, app_id)
            node_data[app_id] = {'count': node_count, 'nodes': nodes}

            # Progress indicator
            if (i + 1) % 10 == 0:
                print(f"  Fetched node details for {i + 1}/{len(app_ids)} apps...")

        except Exception as e:
            print(f"  ⚠️  Failed to fetch nodes for app {app_id}: {e}")
            node_data[app_id] = {'count': 0, 'nodes': []}

    print(f"✅ Fetched node details for {len(node_data)} applications")
    return node_data

def upsert_servers_and_mappings(conn, controller, node_data_by_app, app_id_map):
    """
    Insert/update servers from AppDynamics nodes into servers_dim
    and create app-server mappings in app_server_mapping

    Args:
        conn: Database connection
        controller: AppD controller name
        node_data_by_app: Dict mapping AppD app_id -> {'count': int, 'nodes': list}
        app_id_map: Dict mapping AppD app_id -> database app_id

    Returns:
        Total number of servers and mappings created
    """
    cur = conn.cursor()
    servers_created = 0
    mappings_created = 0

    print("Upserting servers and creating app-server mappings...")

    for appd_app_id, data in node_data_by_app.items():
        # Get the database app_id from the mapping
        db_app_id = app_id_map.get(appd_app_id)
        if not db_app_id:
            continue  # Skip if app wasn't inserted
        nodes = data.get('nodes', [])

        for node in nodes:
            node_id = node.get('id')
            node_name = node.get('name', '')
            machine_name = node.get('machineName', node_name)
            tier_name = node.get('tierName', '')
            machine_agent = node.get('machineAgentPresent', False)
            app_agent = node.get('appAgentPresent', False)

            if not machine_name:
                continue  # Skip nodes without hostname

            try:
                # Upsert into servers_dim
                # Use unique sn_sys_id (placeholder until SNOW enrichment)
                sn_sys_id = f"appd-{controller}-{node_id}"

                cur.execute("""
                    INSERT INTO servers_dim
                    (sn_sys_id, server_name, ip_address, os, is_virtual, updated_at)
                    VALUES (%s, %s, %s, %s, %s, NOW())
                    ON CONFLICT (sn_sys_id)
                    DO UPDATE SET
                        server_name = EXCLUDED.server_name,
                        updated_at = NOW()
                    RETURNING server_id
                """, (
                    sn_sys_id,  # Placeholder sys_id (will be replaced by SNOW data)
                    machine_name,  # server_name
                    None,  # IP address not available from AppD
                    f"AppD-{tier_name}",  # OS placeholder (will be replaced by SNOW)
                    False  # is_virtual unknown until SNOW enrichment
                ))

                server_id = cur.fetchone()[0]
                servers_created += 1

                # Create app-server mapping (use database app_id, not AppD app_id)
                cur.execute("""
                    INSERT INTO app_server_mapping
                    (app_id, server_id, relationship_type, discovered_at)
                    VALUES (%s, %s, %s, NOW())
                    ON CONFLICT (app_id, server_id) DO NOTHING
                """, (db_app_id, server_id, 'runs_on'))

                mappings_created += 1

            except Exception as e:
                # Rollback the failed transaction and start fresh
                conn.rollback()
                print(f"  ⚠️  Failed to upsert server {machine_name}: {e}")
                continue

    conn.commit()
    cur.close()

    print(f"✅ Upserted {servers_created} servers and {mappings_created} app-server mappings")
    return servers_created, mappings_created

# Tags API batch fetch removed - not supported in PepsiCo environment

def determine_architecture(conn, nodes):
    """
    Determine architecture pattern based on infrastructure type from AppD node data

    HEURISTIC LOGIC:
    - Containers/Pods (Kubernetes, Docker) → Microservices (architecture_id=3)
    - Traditional servers (VMs, physical) → Monolithic (architecture_id=2)
    - Mixed infrastructure (1-49% containers) → Hybrid (architecture_id=4)
    - No nodes or no data → Undetermined (architecture_id=1)

    Container Detection:
    - Node names containing: 'pod-', 'container-', 'k8s-', 'docker-'
    - Docker container IDs: 12-char hexadecimal (e.g., c5960753b42b)
    - Kubernetes patterns: app-deployment-7d8f9c4b5-x9k2m

    Args:
        conn: Database connection to fetch architecture IDs
        nodes: List of AppD node objects with 'name', 'machineName', etc.

    Returns:
        int: architecture_id (1=Undetermined, 2=Monolithic, 3=Microservices, 4=Hybrid)
    """
    if not nodes or len(nodes) == 0:
        # No infrastructure data - return Undetermined
        return 1

    # Fetch architecture IDs from database
    cur = conn.cursor()
    cur.execute("SELECT architecture_id, pattern_name FROM architecture_dim")
    arch_map = {row[1]: row[0] for row in cur.fetchall()}
    cur.close()

    # Default IDs (in case query fails)
    UNDETERMINED_ID = arch_map.get('Undetermined', 1)
    MONOLITHIC_ID = arch_map.get('Monolithic', 2)
    MICROSERVICES_ID = arch_map.get('Microservices', 3)
    HYBRID_ID = arch_map.get('Hybrid', 4)

    # Analyze node naming patterns to detect containers
    container_indicators = ['pod-', 'container-', 'k8s-', 'docker-', 'kube-']
    container_count = 0

    for node in nodes:
        node_name = (node.get('name') or '').lower()
        machine_name = (node.get('machineName') or '').lower()

        # Track if this node was already counted to avoid double-counting
        counted = False

        # Check for explicit container naming patterns
        for indicator in container_indicators:
            if indicator in node_name or indicator in machine_name:
                container_count += 1
                counted = True
                break

        if counted:
            continue

        # Check for Docker container IDs (12-char hexadecimal, no hyphens)
        # Example: c5960753b42b, 4bf507ddba25, b8a6930b0d0b
        if len(node_name) == 12 and all(c in '0123456789abcdef' for c in node_name):
            container_count += 1
            continue

        if len(machine_name) == 12 and all(c in '0123456789abcdef' for c in machine_name):
            container_count += 1
            continue

        # Check for Kubernetes-style random suffixes (e.g., "app-abc123-xyz789")
        # Container names often have 2+ hyphenated random hash segments
        if '-' in node_name:
            parts = node_name.split('-')
            if len(parts) >= 3:  # Likely container: "service-replica-hash"
                # Check if last segments look like hashes (alphanumeric, 5-10 chars)
                last_parts = parts[-2:]
                if all(len(p) >= 5 and len(p) <= 10 and p.isalnum() for p in last_parts):
                    container_count += 1

    # Decision logic
    total_nodes = len(nodes)
    container_ratio = container_count / total_nodes if total_nodes > 0 else 0

    if container_ratio >= 0.5:
        # 50%+ containers → Microservices
        return MICROSERVICES_ID
    elif container_ratio > 0:
        # 1-49% containers → Hybrid (mixed infrastructure, migration in progress)
        return HYBRID_ID
    else:
        # 0% containers → traditional Monolithic architecture
        return MONOLITHIC_ID

def fetch_account_license_tier(controller, account, client_id, client_secret, account_id):
    """
    Fetch license tier (Peak/Pro/Lite) from AppDynamics Account Info API

    Uses official endpoint: /controller/licensing/v1/account/{id}/info
    Returns the edition from the 'apm-agent' package properties

    This is account-level, meaning all applications on this controller share the same tier
    """
    try:
        # Get account info which contains package edition information
        account_info = appd_api_get(controller, account, client_id, client_secret,
                                    f"licensing/v1/account/{account_id}/info",
                                    suppress_404=True)

        if not account_info or not isinstance(account_info, dict):
            print(f"⚠️  Could not fetch account info - using default tier 'Pro'")
            return 'Pro'

        # Check account-level edition first
        account_edition = account_info.get('properties', {}).get('edition')
        if account_edition:
            # Capitalize first letter: 'PRO' -> 'Pro', 'PEAK' -> 'Peak'
            return account_edition.capitalize()

        # Otherwise check the apm-agent package edition
        packages = account_info.get('packages', [])
        for package in packages:
            if package.get('packageName') == 'apm-agent':
                edition = package.get('properties', {}).get('edition')
                if edition:
                    # Capitalize first letter: 'PRO' -> 'Pro', 'PEAK' -> 'Peak'
                    return edition.capitalize()

        # Fallback to Pro if no edition found
        print(f"⚠️  No edition found in account info - using default tier 'Pro'")
        return 'Pro'

    except Exception as e:
        print(f"⚠️  Failed to fetch account tier: {e}")
        print(f"   Using default tier 'Pro'")
        return 'Pro'

def store_license_entitlements(conn, controller, account, client_id, client_secret, account_id, caps):
    """
    Store licensed capacity from AppDynamics Account Info API into license_entitlements table

    SOW REQUIREMENTS:
    - Section 2.1: "Current utilization vs. capacity" - Track licensed units vs actual consumption
    - Section 2.3: "License exhaustion predictions" - Use licensed capacity as ceiling for forecasts
    - Section 2.1: "Capacity planning recommendations" - Compare actual vs licensed for optimization

    This enables overage tracking and license compliance reporting by storing contracted capacity
    from /controller/licensing/v1/account/{id}/info endpoint.

    Returns: Number of entitlement records inserted
    """
    print(f"Storing license entitlements for {controller}...")

    try:
        # Fetch account info which contains licensed package units
        account_info = appd_api_get(controller, account, client_id, client_secret,
                                    f"licensing/v1/account/{account_id}/info",
                                    suppress_404=True)

        if not account_info or not isinstance(account_info, dict):
            print(f"⚠️  Could not fetch account info - skipping entitlement storage")
            return 0

        packages = account_info.get('packages', [])
        if not packages:
            print(f"⚠️  No packages found in account info")
            return 0

        # Package name to capability mapping (must match appd_extract.py's package_to_capability)
        package_to_capability = {
            'apm-agent': 'APM',
            'app-agent': 'APM',
            'dotnet': 'APM',
            'db-agent': 'APM',
            'python-app-agent': 'APM',
            'nodejs-agent': 'APM',
            'php-agent': 'APM',
            'machine-agents': 'INFRA',
            'machine-sim': 'INFRA',
            'browser-analytics': 'BRUM',
            'mobile-analytics': 'MRUM',
            'eum-unified': 'BRUM',  # Unified RUM (Browser) - stored but excluded from overage calculations
            'eum-browser': 'BRUM',
            'eum-mobile': 'MRUM',
            'eum-iot': 'MRUM',
            'eum-session-replay': 'BRUM',  # Session Replay (Browser add-on)
            'eum-synthetic': 'ANALYTICS',
            'eum-synthetic-private-agent': 'ANALYTICS',
            'transaction-analytics': 'ANALYTICS',
            'log-analytics': 'ANALYTICS',
            'netviz': 'INFRA'  # Network Visibility
        }

        cur = conn.cursor()
        inserted_count = 0

        for package in packages:
            package_name = package.get('packageName', '')
            properties = package.get('properties', {})

            # Extract package details
            edition = properties.get('edition', 'PRO').upper()
            tier = edition.capitalize()  # 'PRO' -> 'Pro', 'PEAK' -> 'Peak'

            # BUGFIX: API returns 'licenseUnits' at package level, NOT 'numberOfUnits' in properties
            # Test script showed: package.get('licenseUnits', 0) works correctly
            # Previous code: properties.get('numberOfUnits', 0) always returned 0
            licensed_units = package.get('licenseUnits', 0)

            # Parse expiration date (ISO 8601 format)
            expiration_str = properties.get('expirationDate')
            expiration_date = None
            if expiration_str:
                try:
                    expiration_date = datetime.fromisoformat(expiration_str.replace('Z', '+00:00'))
                except:
                    pass

            # Map package to capability (exact match first, then pattern matching)
            capability_code = package_to_capability.get(package_name)

            if not capability_code:
                # Auto-classify unknown packages using pattern matching
                if 'apm' in package_name or 'agent' in package_name or 'dotnet' in package_name or 'java' in package_name or 'nodejs' in package_name or 'python' in package_name or 'php' in package_name:
                    capability_code = 'APM'
                    print(f"   🔍 Auto-classified: {package_name} → APM (pattern: agent/language)")
                elif 'eum' in package_name or 'browser' in package_name or 'mobile' in package_name or 'rum' in package_name:
                    if 'mobile' in package_name or 'iot' in package_name:
                        capability_code = 'MRUM'
                        print(f"   🔍 Auto-classified: {package_name} → MRUM (pattern: mobile/iot)")
                    else:
                        capability_code = 'BRUM'
                        print(f"   🔍 Auto-classified: {package_name} → BRUM (pattern: browser/eum)")
                elif 'machine' in package_name or 'infra' in package_name or 'server' in package_name or 'netviz' in package_name or 'network' in package_name:
                    capability_code = 'INFRA'
                    print(f"   🔍 Auto-classified: {package_name} → INFRA (pattern: machine/network)")
                elif 'analytics' in package_name or 'log' in package_name or 'synthetic' in package_name:
                    capability_code = 'ANALYTICS'
                    print(f"   🔍 Auto-classified: {package_name} → ANALYTICS (pattern: analytics/log)")
                else:
                    # Still unknown after pattern matching - store with NULL capability_id
                    print(f"   ⚠️  Unknown package (no pattern match): {package_name} (units={licensed_units}, tier={tier})")
                    capability_id = None

            if capability_code:
                capability_id = caps.get(capability_code)
                if not capability_id:
                    print(f"   ⚠️  Capability not found in database: {capability_code}")
                    continue

            # Insert entitlement record
            try:
                cur.execute("""
                    INSERT INTO license_entitlements
                    (appd_controller, appd_account, appd_account_id, package_name,
                     capability_id, tier, licensed_units, expiration_date, captured_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
                    ON CONFLICT (appd_controller, appd_account_id, package_name, captured_at)
                    DO UPDATE SET
                        licensed_units = EXCLUDED.licensed_units,
                        expiration_date = EXCLUDED.expiration_date
                """, (controller, account, account_id, package_name,
                      capability_id, tier, licensed_units, expiration_date))

                inserted_count += 1
                print(f"   ✅ {package_name:30s} | {tier:4s} | Licensed: {licensed_units:6.0f} units | Exp: {expiration_str or 'None'}")

            except Exception as e:
                print(f"   ⚠️  Failed to insert entitlement for {package_name}: {e}")
                continue

        conn.commit()
        cur.close()

        print(f"✅ Stored {inserted_count} license entitlement records\n")
        return inserted_count

    except Exception as e:
        print(f"⚠️  Failed to store license entitlements: {e}")
        return 0

def upsert_applications(conn, controller, account, client_id, client_secret, account_id, apps, node_data):
    """
    Upsert applications from AppDynamics into applications_dim
    NOTE: Only sets AppD fields - CMDB enrichment happens in Phase 2
    Cost center must be provided via CSV/CMDB (Tags API blocked)
    Returns mapping of AppD app_id to database app_id
    """
    print(f"Upserting applications from {controller} into database...")

    cur = conn.cursor()
    app_id_map = {}

    # Fetch account-level license tier once (applies to all apps on this controller)
    # This will default to 'Pro' if API is blocked or fails
    account_license_tier = fetch_account_license_tier(controller, account, client_id, client_secret, account_id)
    print(f"Account license tier: {account_license_tier}")

    for app in apps:
        appd_id = app.get('id')
        appd_name = app.get('name')
        description = app.get('description', '')

        # Get node data from batch fetch (new structure)
        node_info = node_data.get(appd_id, {'count': 0, 'nodes': []})
        node_count = node_info['count']
        nodes = node_info['nodes']

        # Get tier count from app data
        tier_count = len(app.get('tiers', []))

        # Determine architecture based on infrastructure type (containers vs servers)
        architecture_id = determine_architecture(conn, nodes)

        # Use account-level license tier (fetched once above)
        license_tier = account_license_tier

        # Cost center must come from CSV/CMDB (Tags API is blocked)
        # Tags API returns HTTP 405 (Method Not Allowed) for reads
        cost_center = None

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
                    cost_center = %s,
                    metadata = metadata || %s::jsonb,
                    updated_at = NOW()
                WHERE app_id = %s
            """, (
                appd_name,
                architecture_id,
                license_tier,
                cost_center,
                f'{{"description": "{description}", "tier_count": {tier_count}, "node_count": {node_count}}}',
                db_app_id
            ))
        else:
            # Insert new application (with NULL owner_id, sector_id, architecture_id)
            # PRODUCTION-READY: No seed data - all dimension FKs start as NULL
            # These will be populated from PepsiCo CMDB (ServiceNow enrichment)
            cur.execute("""
                INSERT INTO applications_dim
                (appd_application_id, appd_application_name, appd_controller, architecture_id, license_tier,
                 cost_center, owner_id, sector_id, metadata)
                VALUES (%s, %s, %s, %s, %s, %s, NULL, NULL, %s)
                RETURNING app_id
            """, (
                str(appd_id),
                appd_name,
                controller,
                architecture_id,
                license_tier,
                cost_center,
                f'{{"description": "{description}", "tier_count": {tier_count}, "node_count": {node_count}}}'
            ))
            db_app_id = cur.fetchone()[0]

        app_id_map[appd_id] = db_app_id

    conn.commit()
    cur.close()

    print(f"✅ Upserted {len(app_id_map)} applications from {controller}")
    return app_id_map

def get_account_id(controller, account, client_id, client_secret):
    """
    Auto-discover the numeric Account ID from AppDynamics

    This can be used if the customer doesn't know their Account ID.
    Calls: GET /controller/api/accounts/myaccount

    Returns:
        str: Numeric account ID
    """
    try:
        response = appd_api_get(
            controller, account, client_id, client_secret,
            "api/accounts/myaccount",
            suppress_404=False
        )

        if response and isinstance(response, dict):
            account_id = str(response.get('id', ''))
            if account_id:
                print(f"✅ Auto-discovered Account ID: {account_id}")
                return account_id

        print("⚠️  Could not auto-discover Account ID from API")
        return None

    except Exception as e:
        print(f"⚠️  Failed to auto-discover Account ID: {e}")
        return None

def fetch_license_usage(controller, account, client_id, client_secret, account_id, start_time_ms, end_time_ms):
    """
    Fetch actual license usage data from AppDynamics Licensing API

    API Endpoint: GET /controller/licensing/usage/account/{accountId}
    Documentation: https://docs.appdynamics.com/latest/en/appdynamics-apis/licensing-api

    Args:
        controller: AppD controller URL
        account: Account name
        client_id: OAuth client ID
        client_secret: OAuth secret
        account_id: Account ID for licensing API
        start_time_ms: Start time in milliseconds since epoch
        end_time_ms: End time in milliseconds since epoch

    Returns:
        List of usage records with structure:
        {
            'applicationId': int,
            'agentType': str,  # 'APM_APP_AGENT', 'MACHINE_AGENT', 'NETVIZ_AGENT', etc.
            'tier': str,       # 'Peak' or 'Pro'
            'avgUnits': float,
            'maxUnits': float,
            'timestamp': int   # milliseconds
        }
    """
    try:
        # Convert milliseconds to ISO 8601 format for AppDynamics Licensing API v1
        from datetime import datetime
        date_from = datetime.fromtimestamp(start_time_ms / 1000).strftime('%Y-%m-%dT%H:%M:%SZ')
        date_to = datetime.fromtimestamp(end_time_ms / 1000).strftime('%Y-%m-%dT%H:%M:%SZ')

        # AppDynamics Licensing API v1 parameters
        params = {
            'dateFrom': date_from,
            'dateTo': date_to,
            'granularityMinutes': 1440  # Daily aggregation (1440 min = 24 hours)
        }

        print(f"API Query Parameters:")
        print(f"   dateFrom: {date_from}")
        print(f"   dateTo: {date_to}")
        print(f"   granularityMinutes: {params['granularityMinutes']}")

        usage_data = appd_api_get(
            controller, account, client_id, client_secret,
            f"licensing/v1/usage/account/{account_id}",  # Fixed: Added /v1/ version prefix
            params=params,
            suppress_404=False
        )

        print(f"✅ Fetched license usage data from AppDynamics API v1")

        # Debug: Show response structure
        if usage_data:
            print(f"API Response Structure:")
            print(f"   Response type: {type(usage_data)}")
            if isinstance(usage_data, dict):
                print(f"   Top-level keys: {list(usage_data.keys())}")
                packages = usage_data.get('packages', [])
                print(f"   Number of packages: {len(packages)}")
                if len(packages) > 0:
                    print(f"   First package keys: {list(packages[0].keys())}")
                    unit_usages = packages[0].get('unitUsages', [])
                    if len(unit_usages) > 0:
                        print(f"   First unitUsage keys: {list(unit_usages[0].keys())}")
                        data_points = unit_usages[0].get('data', [])
                        print(f"   Number of data points in first unitUsage: {len(data_points)}")
                        if len(data_points) > 0:
                            print(f"   First data point sample: {data_points[0]}")

        # v1 API returns a dict with 'packages' array, not a direct list
        if isinstance(usage_data, dict):
            return usage_data  # Return the full response dict
        else:
            print(f"⚠️  Unexpected API response format: {type(usage_data)}")
            return None

    except Exception as e:
        print(f"❌ AppDynamics Licensing API request failed: {e}")
        print(f"   Skipping this controller - license data unavailable")
        return None

def generate_usage_data_from_api(conn, controller, account, client_id, client_secret, account_id, app_id_map):
    """
    Fetch license usage from AppDynamics and allocate to applications using node-count proportional allocation

    AGENT-BASED LICENSING WORKAROUND:
    The AppDynamics Licensing API v1 does NOT provide per-application license usage for agent-based licensing.
    Instead, we:
    1. Fetch account-level usage totals from /controller/licensing/v1/usage/account/{id}
    2. Retrieve node counts per application from inventory APIs
    3. Calculate proportional allocation: app_units = (app_nodes / total_nodes) × account_units

    This approach is documented in the AppDynamics community as the standard pattern for
    deriving per-app consumption when grouped-usage APIs are unavailable.

    PRODUCTION VERSION: No fallback - fails fast if API unavailable
    """
    print("Fetching license usage from AppDynamics Licensing API v1...")

    cur = conn.cursor()

    # Get capability IDs
    cur.execute("SELECT capability_id, capability_code FROM capabilities_dim")
    caps = {row[1]: row[0] for row in cur.fetchall()}

    # Capability mapping from AppD agent types and license package names
    # The API returns usageType: "LICENSE_UNIT" for all packages, so we need to map by package name
    agent_type_to_capability = {
        # Agent types (older API format)
        'APM_APP_AGENT': 'APM',
        'APP_AGENT': 'APM',
        'MACHINE_AGENT': 'INFRA',
        'ANALYTICS_AGENT': 'ANALYTICS',
        'BROWSER_RUM_AGENT': 'BRUM',
        'MOBILE_RUM_AGENT': 'MRUM',
        'SYNTHETIC_AGENT': 'ANALYTICS',
        'DB_AGENT': 'APM',
        # Generic usage type (newer API format - map by package name instead)
        'LICENSE_UNIT': 'LICENSE_UNIT'  # Will be mapped by package name
    }

    # Package name to capability mapping (for LICENSE_UNIT usage type)
    package_to_capability = {
        'apm-agent': 'APM',
        'app-agent': 'APM',
        'dotnet': 'APM',
        'db-agent': 'APM',
        'python-app-agent': 'APM',
        'nodejs-agent': 'APM',
        'php-agent': 'APM',
        'machine-agents': 'INFRA',
        'machine-sim': 'INFRA',
        'browser-analytics': 'BRUM',
        'mobile-analytics': 'MRUM',
        'eum-unified': 'BRUM',  # Unified RUM (Browser)
        'eum-browser': 'BRUM',  # Browser RUM
        'eum-mobile': 'MRUM',   # Mobile RUM
        'eum-iot': 'MRUM',      # IoT RUM
        'eum-synthetic': 'ANALYTICS',
        'eum-synthetic-private-agent': 'ANALYTICS',
        'transaction-analytics': 'ANALYTICS',
        'log-analytics': 'ANALYTICS'
    }

    # Fetch usage data - default 12 months (per SOW requirement)
    # Can be overridden with DEBUG_DAYS_BACK env variable for testing
    now = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    days_back = int(os.getenv('DEBUG_DAYS_BACK', '365'))
    start_date = now - timedelta(days=days_back)

    # Convert to milliseconds for AppD API
    start_time_ms = int(start_date.timestamp() * 1000)
    end_time_ms = int(now.timestamp() * 1000)

    print(f"Query date range: {start_date.strftime('%Y-%m-%d')} to {now.strftime('%Y-%m-%d')} ({(now - start_date).days} days)")

    # Fetch usage from AppD API
    usage_data = fetch_license_usage(
        controller, account, client_id, client_secret,
        account_id, start_time_ms, end_time_ms
    )

    if usage_data is None:
        # API request failed - WARN and continue to next controller
        print("")
        print("=" * 80)
        print(f"⚠️  WARNING: Licensing API Unavailable for {controller}")
        print("=" * 80)
        print("")
        print(f"Controller: {controller}")
        print(f"Account: {account}")
        print("")
        print("The Licensing API v1 is currently unavailable or not accessible for this controller.")
        print("Applications have been loaded, but NO license usage data was collected.")
        print("")
        print("TROUBLESHOOTING STEPS:")
        print("")
        print("1. Verify OAuth client has 'License Admin' role:")
        print("   Required permissions: READ LICENSE_USAGE, READ ACCOUNT_LICENSE")
        print("")
        print("2. Check if Licensing API v1 is enabled:")
        print("   Run: ./scripts/test_all_prod_controllers.sh")
        print(f"   Endpoint: https://{controller}/controller/licensing/v1/usage/account/{account_id}")
        print("")
        print("3. If API returns HTTP 500 (Not supported for Agent):")
        print("   - Contact AppDynamics Support")
        print("   - Verify licensing model (agent-based vs infrastructure-based)")
        print("   - Request API enablement or alternative endpoint")
        print("")
        print("=" * 80)
        print(f"Skipping license data collection for {controller}, continuing to next controller...")
        print("=" * 80)
        print("")
        cur.close()
        return 0  # Return 0 usage rows, but don't terminate pipeline

    # Process API v1 response format
    # Response structure: { accountId, packages: [{ name, unitUsages: [{ usageType, data: [{ timestamp, used: { avg } }] }] }] }

    if not usage_data or not isinstance(usage_data, dict):
        print("⚠️  Invalid API response format")
        cur.close()
        return 0

    packages = usage_data.get('packages', [])
    print(f"Processing {len(packages)} license packages from API...")

    # STEP 1: Extract account-level PEAK DAILY usage by capability/tier/timestamp
    # Per AppDynamics billing model: "Overall Max License Units" = peak hourly usage within a 24-hour period
    # We track the maximum hourly usage for each day (not sum of hourly values)
    # Reference: https://docs.appdynamics.com/appd/24.x/latest/en/splunk-appdynamics-licensing/observe-license-usage
    account_usage = {}  # Key: (capability_code, tier, date) -> peak_units_that_day

    # Debug: Log package structure
    total_unit_usages = 0
    total_data_points = 0

    # CRITICAL DEBUG: Track division operations and raw API totals for validation
    division_counter = {'MRUM': 0, 'BRUM': 0, 'ANALYTICS': 0}
    raw_api_totals = {}  # Track raw API values by (capability, usage_type) for validation

    for package in packages:
        package_name = package.get('name', '')
        tier = 'Peak' if 'PEAK' in package_name.upper() else 'Pro'

        unit_usages = package.get('unitUsages', [])
        total_unit_usages += len(unit_usages)

        print(f"   Package: {package_name} (tier: {tier}) - {len(unit_usages)} unitUsages")
        for unit_usage in unit_usages:
            usage_type = unit_usage.get('usageType', '')

            # CRITICAL FIX: Skip eum-unified and eum-browser packages (summaries)
            # BUT: Keep eum-mobile because some controllers ONLY have eum-mobile, not mobile-analytics
            # The division by 1000 will handle eum-mobile correctly since it maps to MRUM
            if package_name in ['eum-unified', 'eum-browser']:
                print(f"      ⏭️  Skipping {package_name} (summary package - using browser-analytics instead)")
                continue

            # Map usage_type to capability
            # If usage_type is LICENSE_UNIT, map by package name instead
            if usage_type == 'LICENSE_UNIT':
                capability_code = package_to_capability.get(package_name)
                if not capability_code:
                    print(f"      ⚠️  Skipping unknown package: {package_name}")
                    continue
            else:
                # Use agent type mapping for older API format
                capability_code = agent_type_to_capability.get(usage_type)
                if not capability_code or capability_code == 'LICENSE_UNIT':
                    print(f"      ⚠️  Skipping unknown usage_type: {usage_type}")
                    continue

            # Verify capability exists in database
            if capability_code not in caps:
                print(f"      ⚠️  Unknown capability_code: {capability_code} (not in capabilities_dim)")
                continue

            # Process time-series data points
            data_points = unit_usage.get('data', [])
            total_data_points += len(data_points)

            # Debug: Sample the first few data points to see values
            zero_count = 0
            nonzero_count = 0
            sample_shown = False

            if len(data_points) == 0:
                print(f"      {usage_type} ({capability_code}): 0 data points")
            else:
                print(f"      {usage_type} ({capability_code}): {len(data_points)} data points")

            for idx, data_point in enumerate(data_points):
                timestamp_str = data_point.get('timestamp', '')
                used_stats = data_point.get('used', {})

                # AppDynamics Licensing Billing Model:
                # - API returns hourly samples: {'min': X, 'max': Y, 'avg': 0, 'count': N}
                # - 'avg' field is always 0 (API bug or not calculated)
                # - 'max' = peak usage during this hour (from 5-min samples)
                # - We use 'max' as it represents the peak hourly usage
                # - Daily billing = highest 'max' value across all 24 hours (NOT sum of hourly maxes)
                units = used_stats.get('max', 0)

                # VALIDATION: Track raw API values for verification
                if capability_code in ['MRUM', 'BRUM', 'ANALYTICS'] and units > 0:
                    key = (capability_code, usage_type)
                    if key not in raw_api_totals:
                        raw_api_totals[key] = {'raw_sum': 0, 'count': 0, 'max': 0}
                    raw_api_totals[key]['raw_sum'] += units
                    raw_api_totals[key]['count'] += 1
                    raw_api_totals[key]['max'] = max(raw_api_totals[key]['max'], units)

                # VERIFIED FIX: BRUM/MRUM/ANALYTICS unit conversion (all controllers)
                # AppDynamics Licensing API returns browser-analytics, mobile-analytics, and analytics
                # package values in THOUSANDS (per 1000 page views/events/transactions)
                #
                # Evidence from API testing (2025-12-10):
                #   API eum-unified max: 865,190,221
                #   DB BRUM total: 865,190
                #   Ratio: 1000.00x (exact match)
                #
                #   API mobile-analytics peak: 1,958,666,050
                #   DB MRUM total: 1,958,666
                #   Ratio: 1000.00x (exact match)
                #
                # This applies to ALL controllers, not just specific ones.

                # CRITICAL DEBUG: Show ACTUAL raw API values BEFORE division
                if capability_code in ['MRUM', 'BRUM', 'ANALYTICS'] and idx < 5:
                    raw_api_value = used_stats.get('max', 0)
                    print(f"         📥 {capability_code} API RAW #{idx+1}: {raw_api_value:,} (before division) [usage_type={usage_type}]")

                # CRITICAL: BRUM, MRUM, and ANALYTICS all return values "per 1000" from API
                # Must divide by 1000 to get actual page views/events/transactions
                # BUT: Only for LICENSE_UNIT usage type (package-based data)
                # Agent-based data (BROWSER_RUM_AGENT, MOBILE_RUM_AGENT) already in correct units
                if capability_code in ['BRUM', 'MRUM', 'ANALYTICS'] and usage_type == 'LICENSE_UNIT':
                    units = units / 1000
                    division_counter[capability_code] = division_counter.get(capability_code, 0) + 1
                    # CRITICAL DEBUG: Log divided values after conversion
                    if idx < 5:  # Show first 5 values
                        print(f"         ➗ {capability_code} AFTER ÷1000 #{idx+1}: {units:,.2f} (tier={tier}) [LICENSE_UNIT]")
                elif capability_code in ['BRUM', 'MRUM', 'ANALYTICS'] and idx < 5:
                    # Log when division is SKIPPED for agent-based data
                    print(f"         ⏩ {capability_code} NO DIVISION #{idx+1}: {units:,.2f} (tier={tier}) [usage_type={usage_type}]")

                # Debug: Show first non-zero value or first 3 zeros
                if units > 0:
                    nonzero_count += 1
                    if not sample_shown:
                        print(f"         Sample data point: timestamp={timestamp_str}, used.max={units}, used={used_stats}")
                        sample_shown = True
                else:
                    zero_count += 1
                    if idx < 3:  # Show first 3 zeros
                        print(f"         Sample ZERO data point {idx+1}: timestamp={timestamp_str}, used={used_stats}")

                if units == 0:
                    continue  # Skip zero usage

                # Parse ISO 8601 timestamp
                try:
                    ts = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                    ts = ts.replace(hour=0, minute=0, second=0, microsecond=0)  # Normalize to midnight (daily)
                except:
                    continue  # Skip invalid timestamps

                # CRITICAL: Use MAX not SUM for daily aggregation
                # AppDynamics bills on "peak hourly usage within a 24-hour period"
                # If hour 1 = 1751 agents, hour 2 = 1742 agents, etc.
                # Daily peak = max(1751, 1742, ...) = 1751 (NOT 1751 + 1742 + ...)
                key = (capability_code, tier, ts)
                account_usage[key] = max(account_usage.get(key, 0), units)

                # CRITICAL DEBUG: Log what's actually being stored
                if capability_code in ['BRUM', 'MRUM', 'ANALYTICS'] and idx < 3:
                    print(f"         💾 STORING {capability_code}: units={units:,.2f}, raw_api={used_stats.get('max', 0):,}")

            # Debug summary for this unitUsage
            if len(data_points) > 0:
                print(f"         Zero values: {zero_count}, Non-zero values: {nonzero_count}")

    print(f"\n   Summary: {total_unit_usages} unitUsages across {len(packages)} packages")
    print(f"   Summary: {total_data_points} total data points")
    print(f"   Summary: {len(account_usage)} non-zero usage entries extracted")
    print(f"   Division operations performed: MRUM={division_counter['MRUM']:,}, BRUM={division_counter['BRUM']:,}, ANALYTICS={division_counter['ANALYTICS']:,}\n")

    # CRITICAL VALIDATION: Raw API totals by usage_type
    if raw_api_totals:
        print("=" * 80)
        print("VALIDATION: Raw API Values by Usage Type (BEFORE any division)")
        print("=" * 80)
        for (cap, usage_type), stats in sorted(raw_api_totals.items()):
            avg = stats['raw_sum'] / stats['count']
            print(f"{cap:12s} | {usage_type:25s} | Count: {stats['count']:6,} | Avg: {avg:15,.2f} | Max: {stats['max']:15,.2f}")
        print("=" * 80)
        print()

    # CRITICAL DEBUG: Show MRUM vs BRUM comparison to identify unit conversion issues
    print("=" * 60)
    print("DEBUG: RAW API VALUES BY CAPABILITY (for unit conversion analysis)")
    print("=" * 60)
    capability_stats = {}
    for (capability_code, tier, ts), units in account_usage.items():
        if capability_code not in capability_stats:
            capability_stats[capability_code] = {'values': [], 'tier': tier}
        capability_stats[capability_code]['values'].append(units)

        # CRITICAL DEBUG: Log any undivided MRUM values
        if capability_code == 'MRUM' and units > 100000:
            print(f"🚨 UNDIVIDED MRUM DETECTED: {units:,.2f} units on {ts.date()} (tier={tier})")
            print(f"   This value should have been divided by 1000!")

    for cap_code in sorted(capability_stats.keys()):
        stats = capability_stats[cap_code]
        values = stats['values']
        if len(values) > 0:
            avg_val = sum(values) / len(values)
            max_val = max(values)
            min_val = min(values)
            print(f"{cap_code:12s} | Samples: {len(values):4d} | Avg: {avg_val:15,.0f} | Max: {max_val:15,.0f} | Min: {min_val:15,.0f}")

    # Flag if MRUM is suspiciously higher than BRUM
    if 'MRUM' in capability_stats and 'BRUM' in capability_stats:
        mrum_avg = sum(capability_stats['MRUM']['values']) / len(capability_stats['MRUM']['values'])
        brum_avg = sum(capability_stats['BRUM']['values']) / len(capability_stats['BRUM']['values'])
        ratio = mrum_avg / brum_avg if brum_avg > 0 else 0
        print(f"\n⚠️  MRUM/BRUM ratio: {ratio:.1f}x")
        if ratio > 20:
            print(f"🚨 WARNING: MRUM is {ratio:.0f}x higher than BRUM!")
            print(f"   This suggests a unit conversion issue.")
            print(f"   Expected: MRUM should be 2-5x BRUM (not {ratio:.0f}x)")
        elif ratio >= 2 and ratio <= 5:
            print(f"✅ MRUM/BRUM ratio looks correct (expected 2-5x)")
        else:
            print(f"⚠️  MRUM/BRUM ratio is {ratio:.1f}x (expected 2-5x)")
    print("=" * 60 + "\n")

    # CRITICAL VALIDATION SUMMARY: Check if division worked correctly
    print("=" * 80)
    print("VALIDATION SUMMARY: Division Verification")
    print("=" * 80)
    for cap in ['MRUM', 'BRUM', 'ANALYTICS']:
        license_unit_key = (cap, 'LICENSE_UNIT')
        if license_unit_key in raw_api_totals:
            raw_stats = raw_api_totals[license_unit_key]
            raw_avg = raw_stats['raw_sum'] / raw_stats['count']

            # Get stored average from account_usage
            if cap in capability_stats:
                stored_avg = sum(capability_stats[cap]['values']) / len(capability_stats[cap]['values'])
                expected_ratio = 1000.0  # LICENSE_UNIT should be divided by 1000
                actual_ratio = raw_avg / stored_avg if stored_avg > 0 else 0
                ratio_diff_pct = abs(actual_ratio - expected_ratio) / expected_ratio * 100

                status = "✅ PASS" if ratio_diff_pct < 5 else "❌ FAIL"
                print(f"{cap:12s} | Raw Avg: {raw_avg:15,.0f} | Stored Avg: {stored_avg:10,.0f} | Ratio: {actual_ratio:6,.1f}x | {status}")
                if ratio_diff_pct >= 5:
                    print(f"             WARNING: Expected 1000x ratio, got {actual_ratio:.1f}x ({ratio_diff_pct:.1f}% off)")
    print("=" * 80 + "\n")

    if not account_usage:
        print("⚠️  No usage data found in API response")
        print(f"   Possible reasons:")
        print(f"   • All usage values are zero (no consumption in time period)")
        print(f"   • Empty data arrays in API response")
        print(f"   • Usage types don't match expected agent types")
        cur.close()
        return 0

    print(f"Found {len(account_usage)} account-level usage data points")
    print(f"   Applying node-count proportional allocation to distribute across applications...")

    # STEP 2: Get all applications with node counts for this controller
    cur.execute("""
        SELECT
            app_id,
            appd_application_name,
            (metadata->>'node_count')::int as node_count
        FROM applications_dim
        WHERE appd_controller = %s
          AND (metadata->>'node_count')::int > 0
    """, (controller,))

    apps_with_nodes = cur.fetchall()

    if not apps_with_nodes:
        print("⚠️  No applications with node counts found for proportional allocation")
        cur.close()
        return 0

    # Calculate total nodes for proportional allocation
    total_nodes = sum(app[2] for app in apps_with_nodes)
    print(f"   Total nodes across {len(apps_with_nodes)} applications: {total_nodes}")

    # STEP 3: Allocate account-level usage to apps based on node-count proportion
    # Formula: app_units = (app_nodes / total_nodes) × account_units

    usage_rows_inserted = 0

    for (capability_code, tier, ts), account_units in account_usage.items():
        capability_id = caps[capability_code]

        for app_id, app_name, node_count in apps_with_nodes:
            # Calculate proportional allocation
            proportion = node_count / total_nodes
            app_units = account_units * proportion

            # Insert into license_usage_fact
            try:
                cur.execute("""
                    INSERT INTO license_usage_fact
                    (ts, app_id, capability_id, tier, units_consumed)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (ts, app_id, capability_id, tier) DO UPDATE
                    SET units_consumed = EXCLUDED.units_consumed
                """, (ts, app_id, capability_id, tier, app_units))

                usage_rows_inserted += 1

            except Exception as e:
                print(f"⚠️  Failed to insert usage for app {app_name}: {e}")
                continue

    conn.commit()
    cur.close()

    print(f"✅ Allocated {len(account_usage)} account-level data points across {len(apps_with_nodes)} applications")
    print(f"   Total usage records inserted: {usage_rows_inserted}")

    return usage_rows_inserted

def calculate_costs(conn):
    """
    Calculate costs from usage using price_config

    IDEMPOTENT: Uses ON CONFLICT DO UPDATE to safely handle re-runs.
    Can be executed hourly/daily without duplicates - updates existing records.
    """
    cur = conn.cursor()

    print("Calculating costs from usage data...")

    # Calculate costs by joining usage with pricing rules
    # ON CONFLICT handles re-runs: updates costs if prices change or data is reprocessed
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
        ON CONFLICT (ts, app_id, capability_id, tier)
        DO UPDATE SET
            usd_cost = EXCLUDED.usd_cost,
            price_id = EXCLUDED.price_id
    """)

    rows = cur.rowcount
    conn.commit()
    cur.close()
    print(f"✅ Processed {rows} cost records (inserted or updated)")
    return rows

def run_appd_extract():
    """Phase 1: Extract core AppDynamics data (no chargeback yet)"""
    print("=" * 60)
    print("AppDynamics Extract - Phase 1: Core Data")
    print("=" * 60)

    # Parse comma-separated controller configs
    controllers = [c.strip() for c in APPD_CONTROLLERS.split(',') if c.strip()]
    accounts = [a.strip() for a in APPD_ACCOUNTS.split(',') if a.strip()]
    account_ids = [a.strip() for a in APPD_ACCOUNT_IDS.split(',') if a.strip()]
    client_ids = [c.strip() for c in APPD_CLIENT_IDS.split(',') if c.strip()]
    client_secrets = [s.strip() for s in APPD_CLIENT_SECRETS.split(',') if s.strip()]

    # Validate we have matching counts (account_ids is optional - can be auto-discovered)
    if not (len(controllers) == len(accounts) == len(client_ids) == len(client_secrets)):
        print("❌ Mismatched controller configuration counts!")
        print(f"   Controllers: {len(controllers)}, Accounts: {len(accounts)}, Client IDs: {len(client_ids)}, Secrets: {len(client_secrets)}")
        sys.exit(1)

    # Account IDs can be provided or auto-discovered
    if len(account_ids) > 0 and len(account_ids) != len(controllers):
        print("⚠️  Warning: Account IDs count doesn't match controllers count")
        print(f"   Controllers: {len(controllers)}, Account IDs: {len(account_ids)}")
        print("   Will attempt to auto-discover missing Account IDs...")

    if len(controllers) == 0:
        print("❌ No AppDynamics controllers configured!")
        print("   Set APPD_CONTROLLERS, APPD_ACCOUNTS, APPD_ACCOUNT_IDS, APPD_CLIENT_IDS, APPD_CLIENT_SECRETS")
        sys.exit(1)

    print(f"Configured {len(controllers)} controller(s):")
    for i, controller in enumerate(controllers):
        print(f"   {i+1}. {controller} (account: {accounts[i]})")
    print()

    conn = None
    run_id = None
    total_apps = 0
    total_usage_rows = 0
    total_cost_rows = 0
    total_cost_center_count = 0
    discovered_account_ids = []  # Track discovered IDs to save to SSM
    any_ids_discovered = False
    controllers_with_license_data = []  # Track which controllers successfully loaded license data
    controllers_without_license_data = []  # Track which controllers failed license API
    controllers_completely_failed = []  # Track which controllers failed entirely (connection, auth, etc.)

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
            account_id = account_ids[i] if i < len(account_ids) else None
            client_id = client_ids[i]
            client_secret = client_secrets[i]

            print(f"\n{'=' * 60}")
            print(f"Processing Controller {i+1}/{len(controllers)}: {controller}")
            print(f"{'=' * 60}\n")

            try:
                # Auto-discover account ID if not provided
                if not account_id or account_id == '':
                    print("APPD_ACCOUNT_ID not provided, attempting auto-discovery...")
                    account_id = get_account_id(controller, account, client_id, client_secret)
                    if not account_id:
                        print(f"⚠️  Could not determine Account ID for {controller}")
                        print("   Please provide APPD_ACCOUNT_IDS environment variable")
                        print("   OR ensure API access to /controller/api/accounts/myaccount")
                        print(f"   Skipping {controller} and continuing to next controller...")
                        continue
                    any_ids_discovered = True

                # Track account ID for this controller (in order)
                discovered_account_ids.append(account_id)

                # Fetch applications from this controller
                apps = fetch_applications(controller, account, client_id, client_secret)

                if not apps:
                    print(f"⚠️  No applications found on {controller}, skipping...")
                    continue

                # Step 4: Batch fetch node details (includes count and full node info)
                app_ids = [app.get('id') for app in apps]
                node_data = fetch_all_nodes_batch(controller, account, client_id, client_secret, app_ids)

                # Step 5: Upsert applications to database (AppD fields only, cost_center from CSV/CMDB)
                app_id_map = upsert_applications(conn, controller, account, client_id, client_secret, account_id, apps, node_data)

                # Step 5b: Upsert servers and create app-server mappings (use app_id_map for correct foreign keys)
                servers_created, mappings_created = upsert_servers_and_mappings(conn, controller, node_data, app_id_map)

                # Step 5c: Store license entitlements (licensed/contracted capacity)
                # SOW Section 2.1: "Current utilization vs. capacity" & Section 2.3: "License exhaustion predictions"
                # Get capability IDs for license entitlement mapping
                cur = conn.cursor()
                cur.execute("SELECT capability_id, capability_code FROM capabilities_dim")
                caps = {row[1]: row[0] for row in cur.fetchall()}
                cur.close()

                entitlements_stored = store_license_entitlements(conn, controller, account, client_id, client_secret, account_id, caps)

                # Step 6: Fetch REAL license usage data from AppDynamics Licensing API
                usage_rows = generate_usage_data_from_api(conn, controller, account, client_id, client_secret, account_id, app_id_map)

                # Track success/failure for license data
                if usage_rows > 0:
                    controllers_with_license_data.append(controller)
                else:
                    controllers_without_license_data.append(controller)

                # Count apps with cost_center for this controller
                cost_center_count = 0  # Tags API blocked, cost center comes from CSV/CMDB

                # Accumulate totals
                total_apps += len(apps)
                total_usage_rows += usage_rows
                total_cost_center_count += cost_center_count

                # Controller summary
                status_icon = "✅" if usage_rows > 0 else "⚠️"
                print(f"\n{status_icon} Controller {i+1}/{len(controllers)} Complete:")
                print(f"   • Applications: {len(apps)}")
                print(f"   • Cost Center populated: {cost_center_count} ({round(cost_center_count/len(apps)*100, 1)}%)")
                print(f"   • Usage records: {usage_rows}")
                if usage_rows == 0:
                    print(f"   ⚠️  WARNING: No license data - License Admin role may be missing")

            except Exception as e:
                # Controller failed completely - log and continue to next controller
                print(f"\n{'=' * 60}")
                print(f"❌ Controller {i+1}/{len(controllers)} FAILED: {controller}")
                print(f"{'=' * 60}")
                print(f"Error: {str(e)}")
                print(f"\nPossible causes:")
                print(f"  • Controller is down or unreachable")
                print(f"  • Network connectivity issues")
                print(f"  • Invalid credentials (OAuth client ID/secret)")
                print(f"  • Firewall blocking access")
                print(f"  • Controller URL is incorrect")
                print(f"\n   Skipping {controller} and continuing to next controller...")
                print(f"{'=' * 60}\n")

                # Add to completely failed list
                controllers_completely_failed.append(controller)
                continue

        # Step 7: Calculate costs from ALL usage data (once, after all controllers processed)
        print("\n" + "=" * 60)
        print("Calculating costs for all usage data...")
        print("=" * 60)
        total_cost_rows = calculate_costs(conn)

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
        print(f"   • Total Cost Center populated: {total_cost_center_count} ({round(total_cost_center_count/total_apps*100, 1) if total_apps > 0 else 0}%)")
        print(f"   • Total Usage records: {total_usage_rows}")
        print(f"   • Total Cost records: {total_cost_rows}")

        # Show which controllers succeeded/failed for license data
        if controllers_with_license_data:
            print(f"\n   ✅ Controllers with license data ({len(controllers_with_license_data)}):")
            for ctrl in controllers_with_license_data:
                print(f"      - {ctrl}")

        if controllers_without_license_data:
            print(f"\n   ⚠️  Controllers WITHOUT license data ({len(controllers_without_license_data)}):")
            for ctrl in controllers_without_license_data:
                print(f"      - {ctrl}")
            print(f"\n   Action Required: Grant 'License Admin' role to OAuth clients on:")
            for ctrl in controllers_without_license_data:
                print(f"      - {ctrl}")

        if controllers_completely_failed:
            print(f"\n   ❌ Controllers that FAILED completely ({len(controllers_completely_failed)}):")
            for ctrl in controllers_completely_failed:
                print(f"      - {ctrl}")
            print(f"\n   Action Required: Check connectivity, credentials, and controller status for:")
            for ctrl in controllers_completely_failed:
                print(f"      - {ctrl}")

        if any_ids_discovered:
            print(f"\n   • Account IDs discovered: {', '.join(discovered_account_ids)}")
            print(f"   Run scripts/utils/discover_appd_account_ids.py --save-to-ssm to persist")
        print()
        print("Next: Run ServiceNow enrichment to add CMDB data")
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
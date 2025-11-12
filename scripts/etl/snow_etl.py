#!/usr/bin/env python3
"""
ServiceNow ETL - Production-Grade with Intelligent Load Strategy
Auto-detects first run vs incremental and optimizes accordingly
"""
import requests
import psycopg2
from psycopg2.extras import execute_values
import os
from datetime import datetime, timedelta
import time
import sys

# ========================================
# Configuration
# ========================================

DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

SN_INSTANCE = os.getenv('SN_INSTANCE')
SN_CLIENT_ID = os.getenv('SN_CLIENT_ID')
SN_CLIENT_SECRET = os.getenv('SN_CLIENT_SECRET')

# Fallback to basic auth if OAuth not available
SN_USER = os.getenv('SN_USER')
SN_PASS = os.getenv('SN_PASS')

# Safety limits
MAX_SERVERS_INITIAL_LOAD = 10000  # Prevent timeout on first run
BATCH_SIZE_APPS = 500
BATCH_SIZE_SERVERS = 250
REQUEST_TIMEOUT = 60
MAX_EXECUTION_TIME = 600  # 10 minutes total

# ========================================
# Authentication
# ========================================

_oauth_token_cache = {'token': None, 'expires_at': None}

def get_oauth_token():
    """Get OAuth 2.0 access token with caching"""
    now = datetime.now()
    
    # Return cached token if valid
    if _oauth_token_cache['token'] and _oauth_token_cache['expires_at']:
        if now < _oauth_token_cache['expires_at'] - timedelta(seconds=30):
            return _oauth_token_cache['token']
    
    # Request new token
    token_url = f"https://{SN_INSTANCE}.service-now.com/oauth_token.do"
    
    try:
        response = requests.post(
            token_url,
            auth=(SN_CLIENT_ID, SN_CLIENT_SECRET),
            data={'grant_type': 'client_credentials'},
            timeout=30
        )
        response.raise_for_status()
        
        token_data = response.json()
        access_token = token_data.get('access_token')
        expires_in = token_data.get('expires_in', 1800)
        
        if not access_token:
            raise ValueError("No access_token in response")
        
        # Cache token
        _oauth_token_cache['token'] = access_token
        _oauth_token_cache['expires_at'] = now + timedelta(seconds=expires_in)
        
        return access_token
        
    except Exception as e:
        print(f"❌ OAuth authentication failed: {e}")
        raise

def get_auth_headers():
    """Get authentication headers (OAuth or Basic)"""
    if SN_CLIENT_ID and SN_CLIENT_SECRET:
        token = get_oauth_token()
        return {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json"
        }
    elif SN_USER and SN_PASS:
        import base64
        creds = base64.b64encode(f"{SN_USER}:{SN_PASS}".encode()).decode()
        return {
            "Authorization": f"Basic {creds}",
            "Content-Type": "application/json",
            "Accept": "application/json"
        }
    else:
        raise ValueError("No ServiceNow credentials configured")

# ========================================
# API Helpers
# ========================================

def query_snow_paginated(table, fields, query=None, limit=100, max_records=None):
    """
    Paginated ServiceNow API query with timeout protection
    
    Args:
        table: ServiceNow table name
        fields: List of field names to retrieve
        query: ServiceNow query string (optional)
        limit: Page size (default 100)
        max_records: Maximum records to fetch (safety limit)
    
    Returns:
        List of records
    """
    base_url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/{table}"
    headers = get_auth_headers()
    
    all_records = []
    offset = 0
    batch_count = 0
    start_time = time.time()
    
    while True:
        # Timeout check
        elapsed = time.time() - start_time
        if elapsed > MAX_EXECUTION_TIME:
            print(f"  ⚠️  Query timeout after {elapsed:.0f}s. Returning {len(all_records)} records.")
            break
        
        # Max records check
        if max_records and len(all_records) >= max_records:
            print(f"  ⚠️  Reached max records limit ({max_records}). Stopping fetch.")
            break
        
        params = {
            "sysparm_fields": ','.join(fields),
            "sysparm_limit": limit,
            "sysparm_offset": offset,
            "sysparm_exclude_reference_link": "true",
            "sysparm_no_count": "true"
        }
        if query:
            params["sysparm_query"] = query
        
        try:
            response = requests.get(base_url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
            response.raise_for_status()
            
            records = response.json().get("result", [])
            if not records:
                break
            
            all_records.extend(records)
            batch_count += 1
            offset += limit
            
            # Progress update
            if batch_count % 5 == 0:
                rate = len(all_records) / elapsed if elapsed > 0 else 0
                print(f"    Fetched {len(all_records):,} records ({rate:.0f}/sec)...")
            
        except requests.exceptions.Timeout:
            print(f"  ⚠️  Request timeout at offset {offset}. Returning {len(all_records)} records.")
            break
        except requests.exceptions.RequestException as e:
            print(f"  ⚠️  Request error: {e}")
            break
        except Exception as e:
            print(f"  ❌ Unexpected error: {e}")
            break
    
    return all_records

def extract_sys_id(item):
    """Extract sys_id from dict or string"""
    if isinstance(item, dict):
        return item.get('value') or item.get('sys_id')
    return item

def safe_truncate(value, max_length, field_name="field"):
    """Safely truncate string values with logging"""
    if not value:
        return None
    s = str(value)
    if len(s) > max_length:
        return s[:max_length]
    return s

# ========================================
# Load Strategy Detection
# ========================================

def determine_load_strategy(conn):
    """
    Intelligently determine which load strategy to use
    
    Returns:
        'INITIAL_FULL': First run or incomplete data - load with filters
        'INCREMENTAL_OPTIMIZED': Normal operation - only AppD-related servers
    """
    cursor = conn.cursor()
    
    try:
        # Check for AppD applications
        cursor.execute("""
            SELECT COUNT(*) FROM applications_dim 
            WHERE appd_application_id IS NOT NULL
        """)
        appd_count = cursor.fetchone()[0]
        
        # Check total applications
        cursor.execute("SELECT COUNT(*) FROM applications_dim")
        total_count = cursor.fetchone()[0]
        
        # Check for matched applications (reconciliation completed)
        cursor.execute("""
            SELECT COUNT(*) FROM applications_dim 
            WHERE appd_application_id IS NOT NULL 
            AND sn_sys_id IS NOT NULL
        """)
        matched_count = cursor.fetchone()[0]
        
        cursor.close()
        
        # Decision logic
        if total_count == 0:
            return 'INITIAL_FULL', f"Empty database - first run"
        elif appd_count == 0:
            return 'INITIAL_FULL', f"No AppDynamics data yet ({total_count} SN apps exist)"
        elif matched_count == 0:
            return 'INITIAL_FULL', f"No matched apps yet (reconciliation not run)"
        elif matched_count < 50:
            return 'INITIAL_FULL', f"Only {matched_count} matched apps - incomplete data"
        else:
            return 'INCREMENTAL_OPTIMIZED', f"{matched_count} matched apps - using optimized mode"
    
    except Exception as e:
        print(f"  ⚠️  Error detecting strategy: {e}")
        return 'INITIAL_FULL', "Error checking database - defaulting to initial load"

# ========================================
# Initial Load Strategy
# ========================================

def load_applications_full(conn):
    """Load all ServiceNow applications (needed for enrichment data)"""
    print("\n[1/3] Loading ServiceNow Applications (All)")
    print("-" * 70)
    
    # Query for operational applications
    query = "operational_status=1^ORoperational_status=2"
    
    apps = query_snow_paginated(
        table='cmdb_ci_service',
        fields=['sys_id', 'name', 'short_description', 'operational_status'],
        query=query,
        limit=250
    )
    
    if not apps:
        print("  ⚠️  No applications found")
        return 0
    
    print(f"  ✓ Retrieved {len(apps):,} applications")
    
    # Batch upsert
    cursor = conn.cursor()
    records = []
    
    for app in apps:
        sys_id = extract_sys_id(app.get('sys_id'))
        name = safe_truncate(extract_sys_id(app.get('name')), 255, "app name")
        
        if sys_id and name:
            records.append((sys_id, name))
    
    if records:
        insert_query = """
            INSERT INTO applications_dim (sn_sys_id, sn_service_name)
            VALUES %s
            ON CONFLICT (sn_sys_id) DO UPDATE SET
                sn_service_name = EXCLUDED.sn_service_name,
                updated_at = CURRENT_TIMESTAMP
        """
        execute_values(cursor, insert_query, records, page_size=BATCH_SIZE_APPS)
        conn.commit()
        print(f"  ✓ Upserted {len(records):,} applications")
    
    cursor.close()
    return len(records)

def load_servers_filtered_initial(conn):
    """
    Load servers with smart filtering for initial run
    Strategy: Only operational, recently updated servers
    """
    print("\n[2/3] Loading Servers (Filtered Initial Load)")
    print("-" * 70)
    print(f"  Strategy: Operational servers updated in last 90 days")
    print(f"  Safety limit: {MAX_SERVERS_INITIAL_LOAD:,} servers max")
    
    # Calculate date 90 days ago
    date_90_days_ago = (datetime.now() - timedelta(days=90)).strftime('%Y-%m-%d')
    
    # Query for operational, recently updated servers
    query = f"operational_status=1^sys_updated_on>={date_90_days_ago}"
    
    servers = query_snow_paginated(
        table='cmdb_ci_server',
        fields=['sys_id', 'name', 'os', 'ip_address', 'virtual'],
        query=query,
        limit=250,
        max_records=MAX_SERVERS_INITIAL_LOAD
    )
    
    if not servers:
        print("  ⚠️  No servers found")
        return 0
    
    print(f"  ✓ Retrieved {len(servers):,} servers")
    
    # Batch upsert
    cursor = conn.cursor()
    success = 0
    
    for server in servers:
        try:
            sys_id = extract_sys_id(server.get('sys_id'))
            name = safe_truncate(extract_sys_id(server.get('name')), 255, "server name")
            os_type = safe_truncate(extract_sys_id(server.get('os')), 255, "OS")
            ip_address = safe_truncate(extract_sys_id(server.get('ip_address')), 100, "IP")
            
            virtual_raw = extract_sys_id(server.get('virtual'))
            is_virtual = virtual_raw in ['true', 'True', '1', 'yes', True]
            
            if sys_id and name:
                cursor.execute("""
                    INSERT INTO servers_dim (sn_sys_id, server_name, os, ip_address, is_virtual)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (sn_sys_id) DO UPDATE SET
                        server_name = EXCLUDED.server_name,
                        os = EXCLUDED.os,
                        ip_address = EXCLUDED.ip_address,
                        is_virtual = EXCLUDED.is_virtual,
                        updated_at = CURRENT_TIMESTAMP
                """, (sys_id, name, os_type, ip_address, is_virtual))
                success += 1
                
                if success % 500 == 0:
                    conn.commit()
                    print(f"    Committed {success:,} servers...")
        
        except Exception as e:
            print(f"    ⚠️  Error upserting server: {str(e)[:100]}")
            conn.rollback()
    
    conn.commit()
    cursor.close()
    
    print(f"  ✓ Upserted {success:,} servers")
    return success

# ========================================
# Incremental/Optimized Load Strategy
# ========================================

def load_servers_optimized(conn):
    """
    Load ONLY servers for AppDynamics-monitored applications
    This is the production optimization strategy
    """
    print("\n[2/3] Loading Servers (Optimized for AppD Apps)")
    print("-" * 70)
    
    cursor = conn.cursor()
    
    # Get matched AppD applications
    cursor.execute("""
        SELECT sn_sys_id, appd_application_name, sn_service_name
        FROM applications_dim
        WHERE sn_sys_id IS NOT NULL 
          AND appd_application_id IS NOT NULL
    """)
    
    results = cursor.fetchall()
    
    if not results:
        print("  ⚠️  No matched AppD applications found")
        print("     Run reconciliation first, or use initial load mode")
        cursor.close()
        return 0
    
    app_sys_ids = [row[0] for row in results]
    print(f"  ✓ Found {len(app_sys_ids)} AppD-monitored applications")
    print(f"    (Only fetching servers for these apps, not all {len(app_sys_ids):,})")
    
    # Fetch relationships for AppD apps only
    print(f"\n  Step 1: Fetching app-to-server relationships...")
    all_relationships = []
    batch_size = 100
    
    for i in range(0, len(app_sys_ids), batch_size):
        batch = app_sys_ids[i:i+batch_size]
        query = f"type.name=Depends on::Used by^parentIN{','.join(batch)}"
        
        rels = query_snow_paginated(
            table='cmdb_rel_ci',
            fields=['parent', 'child', 'type'],
            query=query,
            limit=250
        )
        all_relationships.extend(rels)
        
        if (i // batch_size + 1) % 5 == 0:
            print(f"    Processed {i + len(batch)}/{len(app_sys_ids)} apps...")
    
    print(f"  ✓ Retrieved {len(all_relationships):,} relationships")
    
    if not all_relationships:
        print("  ⚠️  No relationships found - CMDB may not track app-to-server links")
        cursor.close()
        return 0
    
    # Extract unique server sys_ids
    server_sys_ids = set()
    for rel in all_relationships:
        child = rel.get('child', {})
        child_sys_id = extract_sys_id(child)
        if child_sys_id:
            server_sys_ids.add(child_sys_id)
    
    print(f"  ✓ Identified {len(server_sys_ids):,} unique servers")
    
    # Fetch only these servers
    print(f"\n  Step 2: Fetching {len(server_sys_ids):,} servers...")
    success = 0
    server_list = list(server_sys_ids)
    batch_size = 50
    
    for i in range(0, len(server_list), batch_size):
        batch = server_list[i:i+batch_size]
        query = f"sys_idIN{','.join(batch)}"
        
        servers = query_snow_paginated(
            table='cmdb_ci_server',
            fields=['sys_id', 'name', 'os', 'ip_address', 'virtual'],
            query=query,
            limit=250
        )
        
        for server in servers:
            try:
                sys_id = extract_sys_id(server.get('sys_id'))
                name = safe_truncate(extract_sys_id(server.get('name')), 255, "server name")
                os_type = safe_truncate(extract_sys_id(server.get('os')), 255, "OS")
                ip_address = safe_truncate(extract_sys_id(server.get('ip_address')), 100, "IP")
                
                virtual_raw = extract_sys_id(server.get('virtual'))
                is_virtual = virtual_raw in ['true', 'True', '1', 'yes', True]
                
                if sys_id and name:
                    cursor.execute("""
                        INSERT INTO servers_dim (sn_sys_id, server_name, os, ip_address, is_virtual)
                        VALUES (%s, %s, %s, %s, %s)
                        ON CONFLICT (sn_sys_id) DO UPDATE SET
                            server_name = EXCLUDED.server_name,
                            os = EXCLUDED.os,
                            ip_address = EXCLUDED.ip_address,
                            is_virtual = EXCLUDED.is_virtual,
                            updated_at = CURRENT_TIMESTAMP
                    """, (sys_id, name, os_type, ip_address, is_virtual))
                    success += 1
            
            except Exception as e:
                print(f"    ⚠️  Error: {str(e)[:100]}")
                conn.rollback()
        
        if (i // batch_size + 1) % 10 == 0:
            conn.commit()
            print(f"    Committed {success:,} servers...")
    
    conn.commit()
    cursor.close()
    
    print(f"  ✓ Upserted {success:,} servers (only for AppD apps)")
    return success

# ========================================
# Relationships (Common to Both Strategies)
# ========================================

def load_relationships(conn):
    """Load app-to-server relationship mappings"""
    print("\n[3/3] Loading Application-Server Relationships")
    print("-" * 70)
    
    cursor = conn.cursor()
    
    # Get all apps and servers from database
    cursor.execute("SELECT app_id, sn_sys_id FROM applications_dim WHERE sn_sys_id IS NOT NULL")
    app_map = {row[1]: row[0] for row in cursor.fetchall()}
    
    cursor.execute("SELECT server_id, sn_sys_id FROM servers_dim WHERE sn_sys_id IS NOT NULL")
    server_map = {row[1]: row[0] for row in cursor.fetchall()}
    
    if not app_map or not server_map:
        print("  ⚠️  No apps or servers to map")
        cursor.close()
        return 0
    
    # Fetch relationships
    app_sys_ids = list(app_map.keys())
    all_relationships = []
    batch_size = 100
    
    for i in range(0, len(app_sys_ids), batch_size):
        batch = app_sys_ids[i:i+batch_size]
        query = f"type.name=Depends on::Used by^parentIN{','.join(batch)}"
        
        rels = query_snow_paginated(
            table='cmdb_rel_ci',
            fields=['parent', 'child', 'type'],
            query=query,
            limit=250
        )
        all_relationships.extend(rels)
    
    print(f"  ✓ Retrieved {len(all_relationships):,} relationships")
    
    # Map to database IDs
    records = []
    for rel in all_relationships:
        parent_sys_id = extract_sys_id(rel.get('parent'))
        child_sys_id = extract_sys_id(rel.get('child'))
        rel_type = safe_truncate(extract_sys_id(rel.get('type')), 100, "relationship")
        
        app_id = app_map.get(parent_sys_id)
        server_id = server_map.get(child_sys_id)
        
        if app_id and server_id:
            records.append((app_id, server_id, rel_type or 'Unknown'))
    
    if records:
        insert_query = """
            INSERT INTO app_server_mapping (app_id, server_id, relationship_type)
            VALUES %s
            ON CONFLICT (app_id, server_id) DO UPDATE SET
                relationship_type = EXCLUDED.relationship_type,
                created_at = CURRENT_TIMESTAMP
        """
        execute_values(cursor, insert_query, records)
        conn.commit()
        print(f"  ✓ Mapped {len(records):,} app-server relationships")
    
    cursor.close()
    return len(records)

# ========================================
# Main Orchestration
# ========================================

def main():
    """
    Production-grade ServiceNow ETL with intelligent load strategy
    """
    print("=" * 70)
    print("ServiceNow CMDB ETL - Production Grade")
    print("=" * 70)
    print()
    
    # Validate credentials
    if not SN_INSTANCE:
        print("❌ SN_INSTANCE not configured")
        sys.exit(1)
    
    if not (SN_CLIENT_ID and SN_CLIENT_SECRET) and not (SN_USER and SN_PASS):
        print("❌ No authentication credentials configured")
        print("   Set either SN_CLIENT_ID/SN_CLIENT_SECRET or SN_USER/SN_PASS")
        sys.exit(1)
    
    if not all([DB_HOST, DB_NAME, DB_USER, DB_PASSWORD]):
        print("❌ Database credentials not configured")
        sys.exit(1)
    
    print(f"ServiceNow Instance: {SN_INSTANCE}")
    print(f"Authentication: {'OAuth 2.0' if SN_CLIENT_ID else 'Basic Auth'}")
    print()
    
    # Connect to database
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        print("✓ Database connected")
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        sys.exit(1)
    
    # Log ETL start
    run_id = None
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('snow_etl', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cursor.fetchone()[0]
        conn.commit()
    except Exception as e:
        print(f"⚠️  Could not log ETL start: {e}")
    finally:
        cursor.close()
    
    try:
        # Determine load strategy
        print("\n🔍 Analyzing Database State...")
        print("-" * 70)
        strategy, reason = determine_load_strategy(conn)
        print(f"  Strategy: {strategy}")
        print(f"  Reason: {reason}")
        
        # Execute appropriate strategy
        if strategy == 'INITIAL_FULL':
            print(f"\n🆕 INITIAL LOAD MODE")
            print("=" * 70)
            apps_loaded = load_applications_full(conn)
            servers_loaded = load_servers_filtered_initial(conn)
            relationships_loaded = load_relationships(conn)
        
        else:  # INCREMENTAL_OPTIMIZED
            print(f"\n🔄 OPTIMIZED MODE (AppD Apps Only)")
            print("=" * 70)
            apps_loaded = load_applications_full(conn)  # Still load all apps for enrichment
            servers_loaded = load_servers_optimized(conn)
            relationships_loaded = load_relationships(conn)
        
        # Update ETL log
        if run_id:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE etl_execution_log 
                SET finished_at = NOW(), 
                    status = 'success',
                    rows_ingested = %s
                WHERE run_id = %s
            """, (apps_loaded + servers_loaded + relationships_loaded, run_id))
            conn.commit()
            cursor.close()
        
        # Summary
        print("\n" + "=" * 70)
        print("✅ ServiceNow ETL Complete")
        print("=" * 70)
        print(f"  Applications: {apps_loaded:,}")
        print(f"  Servers: {servers_loaded:,}")
        print(f"  Relationships: {relationships_loaded:,}")
        print(f"  Strategy: {strategy}")
        print("=" * 70)
        
    except Exception as e:
        print("\n" + "=" * 70)
        print(f"❌ FATAL ERROR: {e}")
        print("=" * 70)
        import traceback
        traceback.print_exc()
        
        # Update ETL log with error
        if run_id:
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
        conn.close()


if __name__ == "__main__":
    main()
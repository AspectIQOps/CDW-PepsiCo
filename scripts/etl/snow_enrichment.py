#!/usr/bin/env python3
"""
ServiceNow Enrichment - Phase 2: Targeted CMDB Lookups
Only fetches ServiceNow data for AppDynamics-monitored applications
Optimizes for minimal API calls and data transfer
"""
import requests
import psycopg2
from psycopg2.extras import execute_values
import os
from datetime import datetime, timedelta
import sys

# Configuration - credentials loaded from SSM via entrypoint.sh
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
REQUEST_TIMEOUT = 60
MAX_BATCH_SIZE = 50  # Apps per ServiceNow query

# OAuth token cache
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

def extract_sys_id(item):
    """Extract sys_id from dict or string"""
    if isinstance(item, dict):
        return item.get('value') or item.get('sys_id')
    return item

def safe_truncate(value, max_length, field_name="field"):
    """Safely truncate string values"""
    if not value:
        return None
    s = str(value)
    if len(s) > max_length:
        return s[:max_length]
    return s

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

def get_appd_applications(conn):
    """Get list of AppDynamics application names to enrich"""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT app_id, appd_application_name, appd_application_id
        FROM applications_dim
        WHERE appd_application_id IS NOT NULL
    """)
    
    apps = cursor.fetchall()
    cursor.close()
    
    return apps

def query_snow_by_names(app_names, fields):
    """
    Query ServiceNow for specific application names (batched)
    Returns list of matching CMDB records
    """
    base_url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/cmdb_ci_service"
    headers = get_auth_headers()
    
    all_records = []
    
    # Batch app names to avoid URL length limits
    for i in range(0, len(app_names), MAX_BATCH_SIZE):
        batch = app_names[i:i+MAX_BATCH_SIZE]
        
        # Build query: nameIN{app1,app2,app3}
        query = f"nameIN{','.join(batch)}"
        
        params = {
            "sysparm_fields": ','.join(fields),
            "sysparm_query": query,
            "sysparm_exclude_reference_link": "true",
            "sysparm_limit": 1000  # Should be more than enough per batch
        }
        
        try:
            response = requests.get(base_url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
            response.raise_for_status()
            
            records = response.json().get("result", [])
            all_records.extend(records)
            
            print(f"    Batch {i//MAX_BATCH_SIZE + 1}: Found {len(records)} matches")
            
        except Exception as e:
            print(f"    ⚠️  Batch {i//MAX_BATCH_SIZE + 1} failed: {e}")
            continue
    
    return all_records

def enrich_applications(conn):
    """
    Enrich AppDynamics applications with ServiceNow CMDB data
    Uses targeted queries (only for AppD apps)
    """
    print("\n[Phase 2.1] Enriching Applications with CMDB Data")
    print("-" * 70)
    
    # Get AppD apps that need enrichment
    appd_apps = get_appd_applications(conn)
    
    if not appd_apps:
        print("  ⚠️  No AppDynamics applications found")
        print("     Run appd_extract.py first")
        return 0
    
    print(f"  ℹ️  Found {len(appd_apps)} AppD applications to enrich")
    
    # Extract just the names for ServiceNow lookup
    app_names = [app[1] for app in appd_apps]  # appd_application_name
    
    print(f"\n  🔍 Querying ServiceNow for {len(app_names)} applications...")
    
    # Query ServiceNow with batched name lookup
    cmdb_records = query_snow_by_names(
        app_names, 
        fields=['sys_id', 'name', 'short_description', 'operational_status',
                'owned_by', 'business_service', 'support_group', 'u_h_code']
    )
    
    print(f"  ✅ Retrieved {len(cmdb_records)} CMDB records")
    
    # Build name-to-record mapping for matching
    cmdb_by_name = {}
    for record in cmdb_records:
        name = extract_sys_id(record.get('name'))
        if name:
            cmdb_by_name[name.lower()] = record
    
    # Update applications with CMDB enrichment
    cursor = conn.cursor()
    enriched_count = 0
    
    for app_id, appd_name, appd_id in appd_apps:
        # Try to find matching CMDB record
        cmdb_record = cmdb_by_name.get(appd_name.lower())
        
        if cmdb_record:
            sys_id = extract_sys_id(cmdb_record.get('sys_id'))
            sn_name = safe_truncate(extract_sys_id(cmdb_record.get('name')), 255)
            h_code = safe_truncate(extract_sys_id(cmdb_record.get('u_h_code')), 100)
            support_group = safe_truncate(extract_sys_id(cmdb_record.get('support_group')), 255)
            
            # Update the AppD record with ServiceNow enrichment
            cursor.execute("""
                UPDATE applications_dim
                SET sn_sys_id = %s,
                    sn_service_name = %s,
                    h_code = %s,
                    support_group = %s,
                    updated_at = NOW()
                WHERE app_id = %s
            """, (sys_id, sn_name, h_code, support_group, app_id))
            
            enriched_count += 1
            
            # Log successful match
            cursor.execute("""
                INSERT INTO reconciliation_log 
                (source_a, source_b, match_key_a, match_key_b, confidence_score, 
                 match_status, resolved_app_id)
                VALUES ('AppDynamics', 'ServiceNow', %s, %s, 100, 'auto_matched', %s)
                ON CONFLICT DO NOTHING
            """, (appd_name, sn_name, app_id))
    
    conn.commit()
    cursor.close()
    
    match_rate = (enriched_count / len(appd_apps) * 100) if appd_apps else 0
    
    print(f"\n  ✅ Enriched {enriched_count}/{len(appd_apps)} applications ({match_rate:.1f}%)")
    
    if match_rate < 80:
        print(f"  ⚠️  Match rate below 80% - some apps may not exist in CMDB")
        print(f"     This is expected for dev/test environments")
    
    return enriched_count

def load_servers_for_matched_apps(conn):
    """
    Load servers only for applications that were successfully matched
    Much more efficient than loading all CMDB servers
    """
    print("\n[Phase 2.2] Loading Servers for Matched Applications")
    print("-" * 70)
    
    cursor = conn.cursor()
    
    # Get matched applications (have both AppD and ServiceNow data)
    cursor.execute("""
        SELECT app_id, sn_sys_id, appd_application_name
        FROM applications_dim
        WHERE sn_sys_id IS NOT NULL 
          AND appd_application_id IS NOT NULL
    """)
    
    matched_apps = cursor.fetchall()
    
    if not matched_apps:
        print("  ⚠️  No matched applications found")
        print("     Check ServiceNow instance and application names")
        cursor.close()
        return 0
    
    app_sys_ids = [row[1] for row in matched_apps]
    print(f"  ℹ️  Loading servers for {len(app_sys_ids)} matched applications")
    
    # Fetch app-to-server relationships
    print(f"\n  🔍 Fetching app-to-server relationships...")
    
    base_url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/cmdb_rel_ci"
    headers = get_auth_headers()
    
    all_relationships = []
    batch_size = 50
    
    for i in range(0, len(app_sys_ids), batch_size):
        batch = app_sys_ids[i:i+batch_size]
        query = f"type.name=Depends on::Used by^parentIN{','.join(batch)}"
        
        params = {
            "sysparm_fields": "parent,child,type",
            "sysparm_query": query,
            "sysparm_limit": 1000
        }
        
        try:
            response = requests.get(base_url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
            response.raise_for_status()
            
            rels = response.json().get("result", [])
            all_relationships.extend(rels)
            
            if (i // batch_size + 1) % 5 == 0:
                print(f"    Processed {i + len(batch)}/{len(app_sys_ids)} apps...")
                
        except Exception as e:
            print(f"    ⚠️  Batch failed: {e}")
            continue
    
    print(f"  ✅ Retrieved {len(all_relationships)} relationships")
    
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
    
    print(f"  ✅ Identified {len(server_sys_ids)} unique servers")
    
    # Fetch only these servers
    print(f"\n  📥 Fetching {len(server_sys_ids)} servers...")
    
    server_url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/cmdb_ci_server"
    success = 0
    server_list = list(server_sys_ids)
    
    for i in range(0, len(server_list), batch_size):
        batch = server_list[i:i+batch_size]
        query = f"sys_idIN{','.join(batch)}"
        
        params = {
            "sysparm_fields": "sys_id,name,os,ip_address,virtual",
            "sysparm_query": query,
            "sysparm_limit": 1000
        }
        
        try:
            response = requests.get(server_url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
            response.raise_for_status()
            
            servers = response.json().get("result", [])
            
            for server in servers:
                sys_id = extract_sys_id(server.get('sys_id'))
                name = safe_truncate(extract_sys_id(server.get('name')), 255)
                os_type = safe_truncate(extract_sys_id(server.get('os')), 255)
                ip_address = safe_truncate(extract_sys_id(server.get('ip_address')), 100)
                
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
            
            if (i // batch_size + 1) % 10 == 0:
                conn.commit()
                print(f"    Committed {success} servers...")
                
        except Exception as e:
            print(f"    ⚠️  Batch failed: {e}")
            conn.rollback()
            continue
    
    conn.commit()
    cursor.close()
    
    print(f"  ✅ Loaded {success} servers")
    return success

def load_relationships(conn):
    """Map applications to servers"""
    print("\n[Phase 2.3] Mapping Application-Server Relationships")
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
    
    base_url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/cmdb_rel_ci"
    headers = get_auth_headers()
    
    all_relationships = []
    batch_size = 50
    
    for i in range(0, len(app_sys_ids), batch_size):
        batch = app_sys_ids[i:i+batch_size]
        query = f"type.name=Depends on::Used by^parentIN{','.join(batch)}"
        
        params = {
            "sysparm_fields": "parent,child,type",
            "sysparm_query": query,
            "sysparm_limit": 1000
        }
        
        try:
            response = requests.get(base_url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
            response.raise_for_status()
            
            rels = response.json().get("result", [])
            all_relationships.extend(rels)
            
        except Exception as e:
            print(f"    ⚠️  Batch failed: {e}")
            continue
    
    print(f"  ✅ Retrieved {len(all_relationships)} relationships")
    
    # Map to database IDs
    records = []
    for rel in all_relationships:
        parent_sys_id = extract_sys_id(rel.get('parent'))
        child_sys_id = extract_sys_id(rel.get('child'))
        rel_type = safe_truncate(extract_sys_id(rel.get('type')), 100)
        
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
        print(f"  ✅ Mapped {len(records)} app-server relationships")
    
    cursor.close()
    return len(records)

def run_snow_enrichment():
    """Phase 2: Enrich AppD apps with targeted ServiceNow CMDB data"""
    print("=" * 70)
    print("ServiceNow Enrichment - Phase 2: Targeted CMDB Lookups")
    print("=" * 70)
    
    # Validate credentials
    if not SN_INSTANCE:
        print("❌ SN_INSTANCE not configured")
        sys.exit(1)
    
    if not (SN_CLIENT_ID and SN_CLIENT_SECRET) and not (SN_USER and SN_PASS):
        print("❌ No authentication credentials configured")
        sys.exit(1)
    
    print(f"ServiceNow Instance: {SN_INSTANCE}")
    print(f"Authentication: {'OAuth 2.0' if SN_CLIENT_ID else 'Basic Auth'}")
    print()
    
    # Connect to database
    try:
        conn = get_conn()
        print("✅ Database connected")
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        sys.exit(1)
    
    # Log ETL start
    run_id = None
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('snow_enrichment', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cursor.fetchone()[0]
        conn.commit()
    except Exception as e:
        print(f"⚠️  Could not log ETL start: {e}")
    finally:
        cursor.close()
    
    try:
        # Enrich applications with CMDB data
        apps_enriched = enrich_applications(conn)
        
        # Load servers for matched apps
        servers_loaded = load_servers_for_matched_apps(conn)
        
        # Map relationships
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
            """, (apps_enriched + servers_loaded + relationships_loaded, run_id))
            conn.commit()
            cursor.close()
        
        # Summary
        print("\n" + "=" * 70)
        print("✅ Phase 2 Complete: ServiceNow Enrichment")
        print("=" * 70)
        print(f"  Applications enriched: {apps_enriched}")
        print(f"  Servers loaded: {servers_loaded}")
        print(f"  Relationships mapped: {relationships_loaded}")
        print()
        print("ℹ️  Next: Run appd_finalize.py to generate chargeback and forecasts")
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
    run_snow_enrichment()
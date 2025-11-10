#!/usr/bin/env python3
"""ServiceNow ETL - Real API Integration with OAuth 2.0 Support"""
import psycopg2
from datetime import datetime
import os, time, requests
from requests.auth import HTTPBasicAuth

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')
SN_INSTANCE = os.getenv('SN_INSTANCE')
# OAuth 2.0 credentials (preferred)
SN_CLIENT_ID = os.getenv('SN_CLIENT_ID')
SN_CLIENT_SECRET = os.getenv('SN_CLIENT_SECRET')
# Legacy basic auth credentials (fallback)
SN_USER = os.getenv('SN_USER')
SN_PASS = os.getenv('SN_PASS')
SN_BASE_URL = f"https://{SN_INSTANCE}.service-now.com/api/now/table"
SN_TOKEN_URL = f"https://{SN_INSTANCE}.service-now.com/oauth_token.do"

# Global token cache
_access_token = None
_token_expiry = None

def connect_db(max_retries=5):
    for i in range(max_retries):
        try:
            return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)
        except psycopg2.OperationalError as e:
            if i < max_retries - 1: time.sleep(2 ** i)
            else: raise

def get_oauth_token():
    """Get OAuth 2.0 access token using client credentials flow"""
    global _access_token, _token_expiry

    # Check if we have a valid cached token
    if _access_token and _token_expiry and datetime.now().timestamp() < _token_expiry:
        return _access_token

    print("Fetching new OAuth token from ServiceNow...")
    print(f"Token URL: {SN_TOKEN_URL}")
    print(f"Client ID: {SN_CLIENT_ID[:10]}..." if SN_CLIENT_ID else "Client ID: None")

    payload = {
        'grant_type': 'client_credentials',
        'client_id': SN_CLIENT_ID,
        'client_secret': SN_CLIENT_SECRET
    }

    try:
        response = requests.post(SN_TOKEN_URL, data=payload, timeout=30)

        # Debug output
        print(f"Token Response Status: {response.status_code}")
        if response.status_code != 200:
            print(f"Token Response Body: {response.text[:500]}")

        response.raise_for_status()
        token_data = response.json()

        if 'access_token' not in token_data:
            print(f"ERROR: No access_token in response. Got keys: {token_data.keys()}")
            raise ValueError("No access_token in OAuth response")

        _access_token = token_data['access_token']
        # Set expiry with 60 second buffer
        expires_in = token_data.get('expires_in', 3600)
        _token_expiry = datetime.now().timestamp() + expires_in - 60

        print(f"✓ OAuth token obtained (expires in {expires_in}s)")
        return _access_token

    except requests.exceptions.HTTPError as e:
        print(f"ERROR: OAuth token request failed with status {e.response.status_code}")
        print(f"Response: {e.response.text[:500]}")
        raise
    except Exception as e:
        print(f"ERROR: Failed to get OAuth token: {e}")
        raise

def get_auth_headers():
    """Get authentication headers - OAuth or Basic Auth"""
    if SN_CLIENT_ID and SN_CLIENT_SECRET:
        # Use OAuth 2.0
        token = get_oauth_token()
        return {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/json'
        }
    elif SN_USER and SN_PASS:
        # Use Basic Auth (legacy)
        return {'Accept': 'application/json'}
    else:
        raise ValueError("No ServiceNow authentication credentials available")

def get_auth():
    """Get authentication object for requests"""
    if SN_CLIENT_ID and SN_CLIENT_SECRET:
        # OAuth uses headers only, no auth parameter
        return None
    elif SN_USER and SN_PASS:
        # Basic auth
        return HTTPBasicAuth(SN_USER, SN_PASS)
    else:
        return None

def fetch_snow_table(table_name, fields, query=None):
    if not SN_INSTANCE:
        raise ValueError("ServiceNow instance not configured")

    if not ((SN_CLIENT_ID and SN_CLIENT_SECRET) or (SN_USER and SN_PASS)):
        raise ValueError("ServiceNow credentials missing - need either CLIENT_ID/SECRET or USER/PASS")

    params = {'sysparm_fields': ','.join(fields), 'sysparm_limit': 1000, 'sysparm_offset': 0}
    if query: params['sysparm_query'] = query
    all_records = []

    auth_headers = get_auth_headers()
    auth = get_auth()

    while True:
        r = requests.get(
            f"{SN_BASE_URL}/{table_name}",
            auth=auth,
            headers=auth_headers,
            params=params,
            timeout=60
        )

        # Check for HTTP errors
        if r.status_code != 200:
            print(f"ERROR: ServiceNow API returned status {r.status_code}")
            print(f"Response: {r.text[:500]}")
            r.raise_for_status()

        # Check for valid JSON response
        try:
            data = r.json()
        except requests.exceptions.JSONDecodeError as e:
            print(f"ERROR: ServiceNow returned invalid JSON")
            print(f"Status Code: {r.status_code}")
            print(f"Response Text: {r.text[:500]}")
            print(f"URL: {r.url}")
            raise ValueError(f"Invalid JSON response from ServiceNow: {str(e)}")

        records = data.get('result', [])
        if not records: break
        all_records.extend(records)
        if len(records) < 1000: break
        params['sysparm_offset'] += 1000
    return all_records

def _upsert_dim(cursor, table_name, name_field, name_value):
    pk_map = {'owners_dim': 'owner_id', 'sectors_dim': 'sector_id', 
              'architecture_dim': 'architecture_id', 'capabilities_dim': 'capability_id'}
    pk = pk_map.get(table_name, table_name.replace('_dim', '_id'))
    cursor.execute(f'SELECT {pk} FROM {table_name} WHERE {name_field} = %s', (name_value,))
    result = cursor.fetchone()
    if result: return result[0]
    cursor.execute(f"INSERT INTO {table_name} ({name_field}) VALUES (%s) RETURNING {pk}", (name_value,))
    return cursor.fetchone()[0]

def _upsert_server(conn, server):
    """Insert or update a server in servers_dim"""
    cursor = conn.cursor()
    sys_id = server.get('sys_id')
    if not sys_id:
        cursor.close()
        return None
    
    try:
        data = {
            'server_name': server.get('name'),
            'ip_address': server.get('ip_address'),
            'os': server.get('os'),
            'is_virtual': server.get('virtual', 'false').lower() == 'true'
        }
        
        cursor.execute("SELECT server_id FROM servers_dim WHERE sn_sys_id = %s", (sys_id,))
        
        if cursor.fetchone():
            set_clause = ', '.join([f"{k} = %s" for k in data.keys()])
            cursor.execute(f"UPDATE servers_dim SET {set_clause}, updated_at = NOW() WHERE sn_sys_id = %s", 
                          list(data.values()) + [sys_id])
        else:
            data['sn_sys_id'] = sys_id
            fields = ', '.join(data.keys())
            placeholders = ', '.join(['%s'] * len(data))
            cursor.execute(f"INSERT INTO servers_dim ({fields}) VALUES ({placeholders}) RETURNING server_id", 
                          list(data.values()))
            server_id = cursor.fetchone()[0]
            conn.commit()
            cursor.close()
            return server_id
        
        conn.commit()
        cursor.execute("SELECT server_id FROM servers_dim WHERE sn_sys_id = %s", (sys_id,))
        server_id = cursor.fetchone()[0]
        cursor.close()
        return server_id
        
    except Exception as e:
        conn.rollback()
        print(f"ERROR upserting server {sys_id}: {e}")
        cursor.close()
        return None

def fetch_and_load_servers(conn):
    """Extract servers from ServiceNow and load into servers_dim"""
    try:
        print("Fetching servers from ServiceNow...")
        servers = fetch_snow_table('cmdb_ci_server', 
            ['sys_id', 'name', 'ip_address', 'os', 'virtual'],
            query='operational_status=1')
        
        print(f"Retrieved {len(servers)} servers")
        success = 0
        
        for server in servers:
            if _upsert_server(conn, server):
                success += 1
        
        print(f"✅ Loaded {success}/{len(servers)} servers")
        return success
        
    except Exception as e:
        print(f"ERROR fetching servers: {e}")
        return 0

def fetch_and_map_relationships(conn):
    """Extract app-to-server relationships and populate app_server_mapping"""
    try:
        print("Fetching application-server relationships...")
        relationships = fetch_snow_table('cmdb_rel_ci',
            ['parent', 'child', 'type'],
            query='type.name=Runs on::Runs')
        
        print(f"Retrieved {len(relationships)} relationships")
        
        cursor = conn.cursor()
        success = 0
        
        for rel in relationships:
            parent_sys_id = rel.get('parent', {}).get('value') if isinstance(rel.get('parent'), dict) else rel.get('parent')
            child_sys_id = rel.get('child', {}).get('value') if isinstance(rel.get('child'), dict) else rel.get('child')
            
            if not parent_sys_id or not child_sys_id:
                continue
            
            cursor.execute("SELECT app_id FROM applications_dim WHERE sn_sys_id = %s", (parent_sys_id,))
            app_result = cursor.fetchone()
            
            cursor.execute("SELECT server_id FROM servers_dim WHERE sn_sys_id = %s", (child_sys_id,))
            server_result = cursor.fetchone()
            
            if app_result and server_result:
                app_id = app_result[0]
                server_id = server_result[0]
                
                cursor.execute("""
                    INSERT INTO app_server_mapping (app_id, server_id, relationship_type)
                    VALUES (%s, %s, 'Runs on')
                    ON CONFLICT (app_id, server_id) DO NOTHING
                """, (app_id, server_id))
                success += 1
        
        conn.commit()
        cursor.close()
        
        print(f"✅ Mapped {success} application-server relationships")
        return success
        
    except Exception as e:
        print(f"ERROR mapping relationships: {e}")
        conn.rollback()
        return 0

def upsert_application(conn, svc):
    cursor = conn.cursor()
    sys_id = svc.get('sys_id')
    name = svc.get('name')
    if not sys_id or not name: return False
    
    def get_val(field):
        v = svc.get(field)
        return v.get('display_value') if isinstance(v, dict) else v
    
    try:
        owner_id = _upsert_dim(cursor, 'owners_dim', 'owner_name', 
                               get_val('owned_by') or get_val('managed_by') or 'Unassigned')
        sector_id = _upsert_dim(cursor, 'sectors_dim', 'sector_name', 
                                get_val('u_sector') or get_val('business_unit') or 'Unassigned')
        arch_id = _upsert_dim(cursor, 'architecture_dim', 'pattern_name', 
                              get_val('u_architecture_type') or 'Unknown')
        
        data = {'sn_service_name': name, 'owner_id': owner_id, 'sector_id': sector_id,
                'architecture_id': arch_id, 'h_code': get_val('u_h_code') or get_val('cost_center'),
                'support_group': get_val('support_group'), 'updated_at': datetime.now()}
        
        cursor.execute("SELECT app_id FROM applications_dim WHERE sn_sys_id = %s", (sys_id,))
     
        if cursor.fetchone():
            set_clause = ', '.join([f"{k} = %s" for k in data.keys()])
            cursor.execute(f"UPDATE applications_dim SET {set_clause} WHERE sn_sys_id = %s", 
                          list(data.values()) + [sys_id])
        else:
            data['sn_sys_id'] = sys_id
            fields = ', '.join(data.keys())
            placeholders = ', '.join(['%s'] * len(data))
            cursor.execute(f"INSERT INTO applications_dim ({fields}) VALUES ({placeholders})", 
                          list(data.values()))
        conn.commit()
        return True
    except Exception as e:
        conn.rollback()
        print(f"ERROR: {sys_id}: {e}")
        return False
    finally:
        cursor.close()

def run_snow_etl():
    """Main ETL orchestration function"""
    print("=" * 60)
    print("ServiceNow ETL Starting")
    print("=" * 60)
    
    conn = None
    run_id = None
    total_rows = 0
    
    try:
        # Step 1: Connect to database
        conn = connect_db()
        
        # Step 2: Log ETL start
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO etl_execution_log (job_name, started_at, status)
            VALUES ('snow_etl', NOW(), 'running')
            RETURNING run_id
        """)
        run_id = cursor.fetchone()[0]
        conn.commit()
        cursor.close()
        
        # Step 3: Load applications
        print("\n[1/3] Loading applications from cmdb_ci_service...")
        services = fetch_snow_table('cmdb_ci_service', 
            ['sys_id','name','owned_by','managed_by','u_sector','business_unit',
             'u_architecture_type','u_h_code','cost_center','support_group'], 
            query='install_status=1^operational_status=1')
        print(f"Retrieved {len(services)} services")
        
        success = sum(1 for s in services if upsert_application(conn, s))
        print(f"✅ Applications: {success}/{len(services)}")
        total_rows += success
        
        # Step 4: Load servers
        print("\n[2/3] Loading servers from cmdb_ci_server...")
        servers_loaded = fetch_and_load_servers(conn)
        total_rows += servers_loaded
        
        # Step 5: Map relationships
        print("\n[3/3] Mapping application-server relationships...")
        relationships_mapped = fetch_and_map_relationships(conn)
        total_rows += relationships_mapped
        
        # Step 6: Update ETL log
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE etl_execution_log 
            SET finished_at = NOW(), 
                status = 'success',
                rows_ingested = %s
            WHERE run_id = %s
        """, (total_rows, run_id))
        conn.commit()
        cursor.close()
        
        print("=" * 60)
        print(f"✅ ServiceNow ETL Complete")
        print(f"   • Applications: {success}")
        print(f"   • Servers: {servers_loaded}")
        print(f"   • Relationships: {relationships_mapped}")
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
    run_snow_etl()
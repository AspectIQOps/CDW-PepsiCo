#!/usr/bin/env python3
"""ServiceNow ETL - Real API Integration with Standard _id Naming"""
import psycopg2
from datetime import datetime
import os, time, requests
from requests.auth import HTTPBasicAuth

# Configuration
DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_NAME = os.getenv('DB_NAME', 'cost_analytics_db')
DB_USER = os.getenv('DB_USER', 'etl_analytics')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'appd_pass')
SN_INSTANCE = os.getenv('SN_INSTANCE')
SN_USER = os.getenv('SN_USER')
SN_PASS = os.getenv('SN_PASS')
SN_BASE_URL = f"https://{SN_INSTANCE}.service-now.com/api/now/table"

def connect_db(max_retries=5):
    for i in range(max_retries):
        try:
            return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)
        except psycopg2.OperationalError as e:
            if i < max_retries - 1: time.sleep(2 ** i)
            else: raise

def fetch_snow_table(table_name, fields, query=None):
    if not all([SN_INSTANCE, SN_USER, SN_PASS]):
        raise ValueError("ServiceNow credentials missing")
    params = {'sysparm_fields': ','.join(fields), 'sysparm_limit': 1000, 'sysparm_offset': 0}
    if query: params['sysparm_query'] = query
    all_records = []
    while True:
        r = requests.get(f"{SN_BASE_URL}/{table_name}", auth=HTTPBasicAuth(SN_USER, SN_PASS), 
                        headers={'Accept': 'application/json'}, params=params, timeout=60)
        r.raise_for_status()
        records = r.json().get('result', [])
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
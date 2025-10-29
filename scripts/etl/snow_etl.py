#!/usr/bin/env python3
"""ServiceNow ETL - Real API Integration with Standard _id Naming"""
import psycopg2
from datetime import datetime
import os, time, requests
from requests.auth import HTTPBasicAuth

# Configuration
DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_NAME = os.getenv('DB_NAME', 'appd_licensing')
DB_USER = os.getenv('DB_USER', 'appd_ro')
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


def upsert_application(conn, svc):
    cursor = conn.cursor()
    sys_id = svc.get('sys_id')
    name = svc.get('name')
    if not sys_id or not name: return False
    
    # ADD THIS HELPER:
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
    try:
        print("ServiceNow ETL Starting")
        conn = connect_db()
        services = fetch_snow_table('cmdb_ci_service', 
            ['sys_id','name','owned_by','managed_by','u_sector','business_unit',
             'u_architecture_type','u_h_code','cost_center','support_group'], 
            'install_status=1^operational_status=1')
        print(f"Retrieved {len(services)} services")
        success = sum(1 for s in services if upsert_application(conn, s))
        print(f"✅ Success: {success}/{len(services)}")
    except Exception as e:
        print(f"❌ FATAL: {e}")
    finally:
        if conn: conn.close()

if __name__ == '__main__': run_snow_etl()
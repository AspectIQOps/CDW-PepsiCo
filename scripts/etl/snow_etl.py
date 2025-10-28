#!/usr/bin/env python3
"""
ServiceNow ETL Script - REAL API Integration
Pulls CMDB data from ServiceNow Table API and upserts into PostgreSQL
"""

import psycopg2
from datetime import datetime
import os
import time
import requests
from requests.auth import HTTPBasicAuth

# --- Configuration ---
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_NAME = os.environ.get('DB_NAME', 'appd_licensing')
DB_USER = os.environ.get('DB_USER', 'appd_ro')
DB_PASSWORD = os.environ.get('DB_PASSWORD', 'appd_pass')

SN_INSTANCE = os.environ.get('SN_INSTANCE')
SN_USER = os.environ.get('SN_USER')
SN_PASS = os.environ.get('SN_PASS')

# ServiceNow API Configuration
SN_BASE_URL = f"https://{SN_INSTANCE}.service-now.com/api/now/table"
SN_TIMEOUT = 60
SN_PAGE_SIZE = 1000  # Default ServiceNow limit

def connect_db(max_retries=5):
    """Establishes and returns a database connection with retries."""
    for i in range(max_retries):
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD
            )
            print("Successfully connected to the database.")
            return conn
        except psycopg2.OperationalError as e:
            print(f"Database connection failed (Attempt {i+1}/{max_retries}): {e}")
            if i < max_retries - 1:
                time.sleep(2 ** i)  # Exponential backoff
            else:
                raise


def fetch_snow_table(table_name, fields, query=None, limit=None):
    """
    Fetch data from ServiceNow Table API with pagination support
    
    Args:
        table_name: ServiceNow table name (e.g., 'cmdb_ci_service')
        fields: List of fields to retrieve
        query: Optional encoded query string (e.g., 'install_status=1^operational_status=1')
        limit: Maximum records to retrieve (None = all records with pagination)
    
    Returns:
        List of records
    """
    if not all([SN_INSTANCE, SN_USER, SN_PASS]):
        raise ValueError("ServiceNow credentials not configured (SN_INSTANCE, SN_USER, SN_PASS)")
    
    url = f"{SN_BASE_URL}/{table_name}"
    auth = HTTPBasicAuth(SN_USER, SN_PASS)
    
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
    }
    
    params = {
        'sysparm_fields': ','.join(fields),
        'sysparm_limit': limit or SN_PAGE_SIZE,
        'sysparm_offset': 0,
        'sysparm_exclude_reference_link': 'true'  # Exclude reference links for cleaner data
    }
    
    if query:
        params['sysparm_query'] = query
    
    all_records = []
    
    while True:
        try:
            print(f"  Fetching {table_name} (offset: {params['sysparm_offset']})...")
            response = requests.get(url, auth=auth, headers=headers, params=params, timeout=SN_TIMEOUT)
            response.raise_for_status()
            
            data = response.json()
            records = data.get('result', [])
            
            if not records:
                break
                
            all_records.extend(records)
            print(f"    Retrieved {len(records)} records (total: {len(all_records)})")
            
            # Check if we've hit the limit or exhausted records
            if limit and len(all_records) >= limit:
                break
            
            if len(records) < SN_PAGE_SIZE:
                # Last page
                break
            
            # Move to next page
            params['sysparm_offset'] += SN_PAGE_SIZE
            
        except requests.exceptions.HTTPError as e:
            print(f"ERROR: HTTP {e.response.status_code} - {e.response.text}")
            raise
        except requests.exceptions.RequestException as e:
            print(f"ERROR: Request failed - {e}")
            raise
    
    return all_records


def _upsert_dim(cursor, table_name, name_field, name_value, other_fields=None):
    """
    Generic function to INSERT or SELECT a dimension record and return its ID.
    """
    pk_field_map = {
        'owners_dim': 'owner_id',
        'sectors_dim': 'sector_id',
        'architecture_dim': 'architecture_id',
        'capabilities_dim': 'capability_id'
    }
    
    pk_field = pk_field_map.get(table_name)
    if not pk_field:
        pk_field = table_name.replace('_dim', '_id')
    
    # 1. Check if record exists
    query_select = f'SELECT {pk_field} FROM {table_name} WHERE {name_field} = %s'
    cursor.execute(query_select, (name_value,))
    
    result = cursor.fetchone()
    if result:
        return result[0]

    # 2. Record doesn't exist, insert it
    print(f"    -> Inserting new record into {table_name}: {name_value}")
    
    fields = [name_field]
    values = [name_value]
    
    if other_fields:
        for f, v in other_fields.items():
            fields.append(f)
            values.append(v)

    fields_str = ', '.join(fields)
    placeholders = ', '.join(['%s'] * len(values))
    
    query_insert = f"INSERT INTO {table_name} ({fields_str}) VALUES ({placeholders}) RETURNING {pk_field}"
    cursor.execute(query_insert, values)
    return cursor.fetchone()[0]


def extract_field_value(record, field_name):
    """
    Safely extract field value from ServiceNow record.
    ServiceNow may return reference fields as objects or strings.
    """
    value = record.get(field_name)
    
    if value is None:
        return None
    
    # If it's a dict (reference field), extract display_value or value
    if isinstance(value, dict):
        return value.get('display_value') or value.get('value')
    
    return value


def upsert_application(conn, service_record):
    """
    Processes a single ServiceNow service record and upserts into applications_dim
    
    Args:
        conn: Database connection
        service_record: Dictionary containing ServiceNow cmdb_ci_service data
        
    Returns:
        bool: True if successful, False otherwise
    """
    cursor = conn.cursor()
    
    # Extract core fields
    sn_sys_id = service_record.get('sys_id')
    sn_service_name = extract_field_value(service_record, 'name')
    
    if not sn_sys_id or not sn_service_name:
        print(f"WARN: Skipping record with missing sys_id or name")
        return False
    
    print(f"\nProcessing ServiceNow Service: {sn_service_name} (SN_ID: {sn_sys_id})")

    try:
        # --- 1. Extract and normalize fields ---
        
        # Owner information
        owner_name = extract_field_value(service_record, 'owned_by')
        if not owner_name:
            owner_name = extract_field_value(service_record, 'managed_by')
        if not owner_name:
            owner_name = 'Unassigned'
        
        # Sector/Business Unit (custom field - may vary per instance)
        sector_name = extract_field_value(service_record, 'u_sector')
        if not sector_name:
            sector_name = extract_field_value(service_record, 'business_unit')
        if not sector_name:
            sector_name = 'Unassigned'
        
        # Architecture pattern (custom field - may need mapping)
        architecture_pattern = extract_field_value(service_record, 'u_architecture_type')
        if not architecture_pattern:
            architecture_pattern = 'Unknown'
        
        # H-code (cost center - critical for chargeback)
        h_code = extract_field_value(service_record, 'u_h_code')
        if not h_code:
            h_code = extract_field_value(service_record, 'cost_center')
        
        # Support group
        support_group = extract_field_value(service_record, 'support_group')
        
        # Is critical?
        is_critical = service_record.get('business_criticality') in ['1 - most critical', '2 - somewhat critical']
        
        # --- 2. Dimension Lookups/Upserts ---
        
        owner_id = _upsert_dim(cursor, 'owners_dim', 'owner_name', owner_name)
        print(f"    -> Resolved owner_id: {owner_id}")

        sector_id = _upsert_dim(cursor, 'sectors_dim', 'sector_name', sector_name)
        print(f"    -> Resolved sector_id: {sector_id}")

        architecture_id = _upsert_dim(cursor, 'architecture_dim', 'pattern_name', architecture_pattern)
        print(f"    -> Resolved architecture_id: {architecture_id}")
        
        # --- 3. Main Application Upsert ---
        
        update_data = {
            'sn_service_name': sn_service_name,
            'owner_id': owner_id,
            'sector_id': sector_id,
            'architecture_id': architecture_id,
            'h_code': h_code,
            'support_group': support_group,
            'is_critical': is_critical,
            'updated_at': datetime.now()
        }
        
        # Check if record exists
        cursor.execute("SELECT app_id FROM applications_dim WHERE sn_sys_id = %s", (sn_sys_id,))
        existing_id = cursor.fetchone()
        
        if existing_id:
            # UPDATE existing record
            set_parts = [f"{k} = %s" for k in update_data.keys()]
            set_clause = ', '.join(set_parts)
            values = list(update_data.values())
            
            update_query = f"UPDATE applications_dim SET {set_clause} WHERE sn_sys_id = %s"
            cursor.execute(update_query, values + [sn_sys_id])
            print(f"    -> Successfully UPDATED application (ID: {existing_id[0]})")
            
        else:
            # INSERT new record
            insert_data = update_data.copy()
            insert_data['sn_sys_id'] = sn_sys_id
            
            fields = list(insert_data.keys())
            values = list(insert_data.values())
            
            fields_str = ', '.join(fields)
            placeholders = ', '.join(['%s'] * len(values))
            
            insert_query = f"INSERT INTO applications_dim ({fields_str}) VALUES ({placeholders})"
            cursor.execute(insert_query, values)
            print(f"    -> Successfully INSERTED new service from ServiceNow")

        conn.commit()
        return True

    except psycopg2.Error as e:
        conn.rollback()
        print(f"ERROR processing SNOW data for {sn_sys_id}: {e}")
        return False
    finally:
        cursor.close()


def run_snow_etl():
    """Main function to run the ServiceNow ETL process."""
    conn = None
    try:
        print("=" * 60)
        print("ServiceNow ETL Starting (REAL API MODE)")
        print("=" * 60)
        print(f"Instance: {SN_INSTANCE}")
        print("")
        
        conn = connect_db()
        
        # --- Fetch Services from CMDB ---
        print("📥 Fetching services from ServiceNow CMDB...")
        
        # Define fields to retrieve (adjust based on your ServiceNow instance)
        service_fields = [
            'sys_id',
            'name',
            'owned_by',
            'managed_by',
            'u_sector',
            'business_unit',
            'u_architecture_type',
            'u_h_code',
            'cost_center',
            'support_group',
            'business_criticality',
            'install_status',
            'operational_status'
        ]
        
        # Query for active, operational services
        query = 'install_status=1^operational_status=1'
        
        try:
            services = fetch_snow_table('cmdb_ci_service', service_fields, query=query)
        except Exception as e:
            print(f"\n❌ Failed to fetch services from ServiceNow: {e}")
            print("\nTroubleshooting tips:")
            print("  1. Verify SN_INSTANCE, SN_USER, SN_PASS are correct")
            print("  2. Check if ServiceNow instance is accessible")
            print("  3. Verify user has read access to cmdb_ci_service table")
            print("  4. Check if custom fields (u_sector, u_h_code, etc.) exist in your instance")
            raise
        
        if not services:
            print("\n⚠️  No services found matching criteria")
            print("   This could mean:")
            print("   - No services with install_status=1 and operational_status=1")
            print("   - User lacks permissions to cmdb_ci_service")
            return
        
        print(f"\n✅ Retrieved {len(services)} services from ServiceNow")
        print("")
        
        # --- Process each service ---
        success_count = 0
        for service_record in services:
            if upsert_application(conn, service_record):
                success_count += 1
        
        print("\n" + "=" * 60)
        print(f"ServiceNow ETL Finished")
        print(f"Successful operations: {success_count}/{len(services)}")
        
        if success_count < len(services):
            print(f"⚠️  {len(services) - success_count} records failed")
        
        print("=" * 60)

    except Exception as e:
        print(f"\n❌ FATAL ETL ERROR: {e}")
        import traceback
        traceback.print_exc()
    finally:
        if conn:
            conn.close()
            print("Database connection closed.")


if __name__ == '__main__':
    run_snow_etl()
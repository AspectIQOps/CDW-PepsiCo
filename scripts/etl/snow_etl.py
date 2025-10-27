import psycopg2
from psycopg2 import sql
from datetime import datetime
import os
import time
import random

# --- Configuration ---
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_NAME = os.environ.get('DB_NAME', 'appd_licensing')
DB_USER = os.environ.get('DB_USER', 'appd_ro')
DB_PASSWORD = os.environ.get('DB_PASSWORD', 'appd_pass')

# Mock data simulating a ServiceNow CMDB API response
MOCK_SNOW_DATA = [
    {
        'sn_sys_id': 'SN001001',
        'sn_service_name': 'MyPepsi Digital Commerce Platform', 
        'owner_name': 'Sarah Connor', 
        'sector_name': 'Beverages North America',
        'architecture_pattern': 'Microservices',
        'h_code': 'BEVNA-ECOM-100',
        'support_group': 'IT Ops Tier 3'
    },
    {
        'sn_sys_id': 'SN001002',
        'sn_service_name': 'PepsiCo SAP ERP',
        'owner_name': 'Bruce Wayne', 
        'sector_name': 'PepsiCo Global',
        'architecture_pattern': 'Monolith',
        'h_code': 'ERP-GLOB-001',
        'support_group': 'SAP Team'
    },
    {
        'sn_sys_id': 'SN001003',
        'sn_service_name': 'HR Payroll System',
        'owner_name': 'Harold Finch',
        'sector_name': 'Human Resources', 
        'architecture_pattern': 'SaaS', 
        'h_code': 'HR-PAY-300',
        'support_group': 'HR Support'
    },
]

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
                time.sleep(2 ** i) # Exponential backoff
            else:
                raise

def _upsert_dim(cursor, table_name, name_field, name_value, other_fields=None):
    """
    Generic function to INSERT or SELECT a dimension record and return its ID.
    """
    # FIX: Handle irregular pluralization
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

    # 2. Insert new record
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


def upsert_application(conn, app_data):
    """
    Processes a single ServiceNow application record, handles dimension lookups/upserts,
    and upserts the final record into applications_dim using sn_sys_id as the merge key.
    """
    cursor = conn.cursor()
    sn_id = app_data['sn_sys_id']
    
    print(f"\nProcessing ServiceNow Service: {app_data['sn_service_name']} (SN_ID: {sn_id})")

    try:
        # --- 1. Dimension Lookups/Upserts ---
        
        owner_id = _upsert_dim(
            cursor, 
            'owners_dim', 
            'owner_name', 
            app_data['owner_name']
        )
        print(f"    -> Resolved owner_id: {owner_id}")

        sector_id = _upsert_dim(
            cursor, 
            'sectors_dim', 
            'sector_name', 
            app_data['sector_name']
        )
        print(f"    -> Resolved sector_id: {sector_id}")

        architecture_id = _upsert_dim(
            cursor, 
            'architecture_dim', 
            'pattern_name', 
            app_data['architecture_pattern']
        )
        print(f"    -> Resolved architecture_id: {architecture_id}")
        
        
        # --- 2. Main Application Upsert ---
        
        update_data = {
            'sn_service_name': app_data['sn_service_name'],
            'owner_id': owner_id,
            'sector_id': sector_id,
            'architecture_id': architecture_id,
            'h_code': app_data['h_code'],
            'support_group': app_data['support_group'],
            'updated_at': datetime.now()
        }
        
        fields = list(update_data.keys())
        values = list(update_data.values())
        
        # Check if the record already exists based on sn_sys_id
        cursor.execute("SELECT app_id FROM applications_dim WHERE sn_sys_id = %s", (sn_id,))
        existing_id = cursor.fetchone()
        
        if existing_id:
            # Case 1: UPDATE (Update all SNOW-related fields and dimension FKs)
            set_clause = sql.SQL(', ').join([
                sql.SQL('{0} = %s').format(sql.Identifier(k)) for k in update_data.keys()
            ])
            update_query = sql.SQL("UPDATE applications_dim SET {set_clause} WHERE sn_sys_id = %s").format(set_clause=set_clause)
            
            cursor.execute(update_query, values + [sn_id])
            print(f"    -> Successfully UPDATED application (ID: {existing_id[0]}) using SNOW data.")
            
        else:
            # Case 2: INSERT (Must include temp values for NOT NULL AppDynamics fields)
            appd_name_placeholder = f"SNOW-TEMP-Service ({app_data['sn_service_name']})"
            appd_id_placeholder = random.randint(3000, 9000) 
            
            # Prepare fields and values for INSERT
            fields.extend(['sn_sys_id', 'appd_application_name', 'appd_application_id'])
            values.extend([sn_id, appd_name_placeholder, appd_id_placeholder])
            
            insert_query = sql.SQL("INSERT INTO applications_dim ({fields}) VALUES ({values})").format(
                fields=sql.SQL(', ').join(map(sql.Identifier, fields)),
                values=sql.SQL(', ').join(sql.Placeholder * len(values))
            )
            
            cursor.execute(insert_query, values)
            print(f"    -> Successfully INSERTED new service (Temp AppD link created).")


        conn.commit()
        return True

    except psycopg2.Error as e:
        conn.rollback()
        print(f"ERROR processing SNOW data for {sn_id}: {e}")
        return False
    finally:
        cursor.close()

def run_snow_etl():
    """Main function to run the ServiceNow ETL process."""
    conn = None
    try:
        conn = connect_db()
        print("Starting ServiceNow ETL Process...")
        
        success_count = 0
        for app_data in MOCK_SNOW_DATA:
            if upsert_application(conn, app_data):
                success_count += 1
                
        print(f"\nServiceNow ETL Finished. Successful operations: {success_count}/{len(MOCK_SNOW_DATA)}")

    except Exception as e:
        print(f"FATAL ETL ERROR: {e}")
    finally:
        if conn:
            conn.close()
            print("Database connection closed.")

if __name__ == '__main__':
    run_snow_etl()

import psycopg2
from psycopg2 import sql
from datetime import datetime
import os
import time
import random

# --- Configuration ---
DB_HOST = os.environ.get('POSTGRES_HOST', 'localhost')
DB_NAME = os.environ.get('POSTGRES_DB', 'aspectiq_db')
DB_USER = os.environ.get('POSTGRES_USER', 'devuser')
DB_PASSWORD = os.environ.get('POSTGRES_PASSWORD', 'devpassword')

# Mock data simulating an AppDynamics API response
# Includes dimension attributes: owner_name, sector_name, architecture_pattern
MOCK_APPD_DATA = [
    {
        'appd_application_id': 101,
        'appd_application_name': 'MyPepsi E-Commerce',
        'owner_name': 'Sarah Connor',
        'sector_name': 'Beverages North America',
        'architecture_pattern': 'Microservices',
        'h_code': 'BEVNA-ECOM-100',
        'is_critical': True
    },
    {
        'appd_application_id': 102,
        'appd_application_name': 'Global Finance Ledger',
        'owner_name': 'John Reese',
        'sector_name': 'PepsiCo Global',
        'architecture_pattern': 'Monolith',
        'h_code': 'FIN-GLOB-550',
        'is_critical': True
    },
    {
        'appd_application_id': 103,
        'appd_application_name': 'Frito Lay Logistics App',
        'owner_name': 'Harold Finch',
        'sector_name': 'Frito Lay',
        'architecture_pattern': 'Serverless',
        'h_code': 'FL-LOG-200',
        'is_critical': False
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
    # Dynamically determine the primary key field name (e.g., 'owners_dim' -> 'owner_id')
    pk_field = table_name[:-4] + '_id' 
    
    # 1. Check if the record exists
    query_select = sql.SQL("SELECT {pk} FROM {table} WHERE {name_f} = %s").format(
        pk=sql.Identifier(pk_field),
        table=sql.Identifier(table_name),
        name_f=sql.Identifier(name_field)
    )
    cursor.execute(query_select, (name_value,))
    
    result = cursor.fetchone()
    if result:
        return result[0]

    # 2. If it does not exist, insert it
    print(f"    -> Inserting new record into {table_name}: {name_value}")
    
    fields = [name_field]
    values = [name_value]
    
    if other_fields:
        for f, v in other_fields.items():
            fields.append(f)
            values.append(v)

    query_insert = sql.SQL("INSERT INTO {table} ({fields}) VALUES ({values}) RETURNING {pk}").format(
        table=sql.Identifier(table_name),
        fields=sql.SQL(', ').join(map(sql.Identifier, fields)),
        values=sql.SQL(', ').join(sql.Placeholder * len(values)),
        pk=sql.Identifier(pk_field)
    )

    cursor.execute(query_insert, values)
    return cursor.fetchone()[0]


def upsert_application(conn, app_data):
    """
    Processes a single AppDynamics application record, handles dimension lookups/upserts,
    and upserts the final record into applications_dim.
    """
    cursor = conn.cursor()
    app_name = app_data['appd_application_name']
    
    print(f"\nProcessing AppDynamics Application: {app_name}")

    try:
        # --- 1. Dimension Lookups/Upserts ---
        
        owner_id = _upsert_dim(
            cursor, 
            'owners_dim', 
            'owner_name', 
            app_data['owner_name'],
            other_fields={'organizational_hierarchy': 'Unknown Hierarchy'} 
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
            'appd_application_name': app_name,
            'appd_application_id': app_data['appd_application_id'],
            'owner_id': owner_id,
            'sector_id': sector_id,
            'architecture_id': architecture_id,
            'h_code': app_data['h_code'],
            'is_critical': app_data['is_critical'],
            'updated_at': datetime.now()
        }
        
        fields = list(update_data.keys())
        values = list(update_data.values())
        
        # Check if the record already exists based on appd_application_id
        cursor.execute("SELECT app_id FROM applications_dim WHERE appd_application_id = %s", (app_data['appd_application_id'],))
        existing_id = cursor.fetchone()
        
        if existing_id:
            # Case 1: UPDATE (Only update AppD-related fields and dimension FKs)
            set_clause = sql.SQL(', ').join([
                sql.SQL('{0} = %s').format(sql.Identifier(k)) for k in update_data.keys()
            ])
            update_query = sql.SQL("UPDATE applications_dim SET {set_clause} WHERE appd_application_id = %s").format(set_clause=set_clause)
            
            cursor.execute(update_query, values + [app_data['appd_application_id']])
            print(f"    -> Successfully UPDATED application (ID: {existing_id[0]}).")
            
        else:
            # Case 2: INSERT (Must include temp values for NOT NULL SNOW fields)
            # This is critical to avoid FK constraint errors later.
            sn_sys_id_placeholder = f"APPD-TEMP-{app_data['appd_application_id']}"
            sn_service_name_placeholder = f"APPD-Service ({app_name})"
            
            fields.extend(['sn_sys_id', 'sn_service_name'])
            values.extend([sn_sys_id_placeholder, sn_service_name_placeholder])
            
            insert_query = sql.SQL("INSERT INTO applications_dim ({fields}) VALUES ({values})").format(
                fields=sql.SQL(', ').join(map(sql.Identifier, fields)),
                values=sql.SQL(', ').join(sql.Placeholder * len(values))
            )
            
            cursor.execute(insert_query, values)
            print(f"    -> Successfully INSERTED new application (Temp SNOW link created).")


        conn.commit()
        return True

    except psycopg2.Error as e:
        conn.rollback()
        print(f"ERROR processing AppD data for {app_name}: {e}")
        return False
    finally:
        cursor.close()

def run_appd_etl():
    """Main function to run the AppDynamics ETL process."""
    conn = None
    try:
        conn = connect_db()
        print("Starting AppDynamics ETL Process...")
        
        success_count = 0
        for app_data in MOCK_APPD_DATA:
            if upsert_application(conn, app_data):
                success_count += 1
                
        print(f"\nAppDynamics ETL Finished. Successful operations: {success_count}/{len(MOCK_APPD_DATA)}")

    except Exception as e:
        print(f"FATAL ETL ERROR: {e}")
    finally:
        if conn:
            conn.close()
            print("Database connection closed.")

if __name__ == '__main__':
    run_appd_etl()

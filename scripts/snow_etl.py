import os
import requests
import psycopg2
from dotenv import load_dotenv

# --- Load .env ---
project_root = "/opt/appd-licensing"
load_dotenv(os.path.join(project_root, '.env'))

SN = os.getenv('SN_INSTANCE')
USER = os.getenv('SN_USER')
PWD = os.getenv('SN_PASS')

DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

PG_DSN = f"dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD} host={DB_HOST} port={DB_PORT}"
BASE = f"https://{SN}.service-now.com/api/now/table"

def pull(table, fields, query=None):
    try:
        params = {'sysparm_fields': ','.join(fields), 'sysparm_limit': 10000}
        if query:
            params['sysparm_query'] = query
        r = requests.get(BASE + f"/{table}", auth=(USER, PWD), params=params, timeout=60)
        r.raise_for_status()
        return r.json()['result']
    except Exception as e:
        print(f"❌ Failed to pull from ServiceNow: {e}")
        raise

def upsert_services(conn, services):
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO etl_execution_log(job_name, started_at, status)
        VALUES('snow_pull', now(), 'RUNNING')
        RETURNING run_id
    """)
    run_id = cur.fetchone()[0]
    rows = 0

    for s in services:
        # Upsert applications_dim
        cur.execute("""
            INSERT INTO applications_dim(appd_application_name, sn_sys_id, sn_service_name, h_code, sector)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (sn_sys_id) DO UPDATE SET
              appd_application_name = EXCLUDED.appd_application_name,
              sn_service_name = EXCLUDED.sn_service_name,
              h_code = EXCLUDED.h_code,
              sector = EXCLUDED.sector
            RETURNING app_id
        """, (s.get('name'), s.get('sys_id'), s.get('name'), s.get('u_h_code'), s.get('u_sector')))
        app_id = cur.fetchone()[0]

        # Log data lineage
        cur.execute("""
            INSERT INTO data_lineage(run_id, source_system, source_endpoint, target_table, target_pk)
            VALUES (%s, 'ServiceNow', 'cmdb_ci_service', 'applications_dim', json_build_object('sn_sys_id', %s))
        """, (run_id, s.get('sys_id')))

        rows += 1

    cur.execute("""
        UPDATE etl_execution_log
        SET finished_at = now(), status='SUCCESS', rows_ingested=%s
        WHERE run_id=%s
    """, (rows, run_id))

    conn.commit()
    return rows

if __name__ == '__main__':
    print("⏳ Pulling active operational services from ServiceNow...")
    services = pull('cmdb_ci_service', ['sys_id','name','owner','u_h_code','u_sector'], 'install_status=1^operational_status=1')
    print("⏳ Connecting to PostgreSQL...")
    with psycopg2.connect(PG_DSN) as conn:
        inserted = upsert_services(conn, services)
    print(f"✅ Loaded {inserted} services into applications_dim")

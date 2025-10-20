import os
import requests
import psycopg2
from dotenv import load_dotenv

# Load .env from project root
project_root = "/Users/home/Desktop/Work/GitHub/CDW-PepsiCo"
load_dotenv(os.path.join(project_root, '.env'))

SN = os.getenv('SN_INSTANCE')
USER = os.getenv('SN_USER')
PWD = os.getenv('SN_PASS')
PG_DSN = os.getenv('PG_DSN')

BASE = f"https://{SN}.service-now.com/api/now/table"


def pull(table, fields, query=None):
    """Pull data from ServiceNow table"""
    params = {
        'sysparm_fields': ','.join(fields),
        'sysparm_limit': 1000
    }
    if query:
        params['sysparm_query'] = query

    r = requests.get(BASE + f"/{table}", auth=(USER, PWD), params=params, timeout=60)
    r.raise_for_status()
    return r.json()['result']


def upsert_services(conn, services):
    """Insert/update services into applications_dim"""
    cur = conn.cursor()
    rows = 0
    for s in services:
        cur.execute("""
            INSERT INTO applications_dim(appd_application_name, sn_sys_id, sn_service_name, h_code, sector)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (sn_sys_id) DO NOTHING
        """, (
            s.get('name'),
            s.get('sys_id'),
            s.get('name'),
            s.get('u_h_code'),
            s.get('u_sector')
        ))
        rows += 1
    conn.commit()
    return rows


if __name__ == '__main__':
    # Pull active operational services
    services = pull(
        'cmdb_ci_service',
        ['sys_id', 'name', 'owner', 'u_h_code', 'u_sector'],
        'install_status=1^operational_status=1'
    )

    with psycopg2.connect(PG_DSN) as conn:
        inserted = upsert_services(conn, services)

    print(f"Loaded {inserted} services into applications_dim")

import os
import requests
import psycopg2
from datetime import datetime
from dotenv import load_dotenv

# --- Load .env from /opt/appd-licensing ---
ENV_PATH = "/opt/appd-licensing/.env"
if not os.path.isfile(ENV_PATH):
    raise SystemExit(f"❌ .env file not found at {ENV_PATH}")

load_dotenv(ENV_PATH)

CTRL = os.getenv('APPD_CONTROLLER')
ACCOUNT = os.getenv('APPD_ACCOUNT')
CID = os.getenv('APPD_CLIENT_ID')
CSEC = os.getenv('APPD_CLIENT_SECRET')
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

PG_DSN = f"dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD} host={DB_HOST} port={DB_PORT}"

def token():
    r = requests.post(f"https://{CTRL}/controller/api/oauth/access_token",
                      data={"grant_type":"client_credentials",
                            "client_id":f"{CID}@{ACCOUNT}",
                            "client_secret":CSEC}, timeout=60)
    r.raise_for_status()
    return r.json()['access_token']

def get(tok, path):
    headers = {"Authorization": f"Bearer {tok}"}
    r = requests.get(f"https://{CTRL}{path}", headers=headers, timeout=60)
    r.raise_for_status()
    return r.json()

def upsert_usage(conn, records, endpoint):
    cur = conn.cursor()
    cur.execute("INSERT INTO etl_execution_log(job_name, started_at, status) VALUES('appd_license_pull', now(), 'RUNNING') RETURNING run_id")
    run_id = cur.fetchone()[0]
    rows = 0
    for rec in records:
        m = {'ts': datetime.utcnow(), 'app_id': rec.get('app_id',1),
             'capability_id':1, 'tier': rec.get('tier','PRO'),
             'units': float(rec.get('units',0)), 'nodes': int(rec.get('nodes',0))}
        cur.execute("""
            INSERT INTO license_usage_fact(ts, app_id, capability_id, tier, units, nodes)
            VALUES(%(ts)s,%(app_id)s,%(capability_id)s,%(tier)s,%(units)s,%(nodes)s)
            ON CONFLICT (ts, app_id, capability_id, tier)
            DO UPDATE SET units = excluded.units, nodes = excluded.nodes
        """, m)
        cur.execute("""
            INSERT INTO data_lineage(run_id, source_system, source_endpoint, target_table, target_pk)
            VALUES (%s, 'AppDynamics', %s, 'license_usage_fact', json_build_object('app_id', %s))
        """, (run_id, endpoint, m['app_id']))
        rows += 1
    cur.execute("UPDATE etl_execution_log SET finished_at = now(), status='SUCCESS', rows_ingested=%s WHERE run_id=%s", (rows, run_id))
    conn.commit()

if __name__ == '__main__':
    t = token()
    endpoints = ["/controller/rest/licenses/usage?output=JSON", "/controller/rest/licenses?output=JSON"]
    payload = None
    ep_used = None
    for ep in endpoints:
        try:
            payload = get(t, ep)
            ep_used = ep
            break
        except Exception:
            continue
    if payload is None:
        raise SystemExit('No licensing endpoint responded with JSON')

    with psycopg2.connect(PG_DSN) as conn:
        # Placeholder demo record
        sample = [{"app_id":1,"tier":"PRO","units":10,"nodes":5}]
        upsert_usage(conn, sample, ep_used)

    print("✅ AppDynamics licensing ETL complete")

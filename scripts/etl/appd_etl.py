#!/usr/bin/env python3
"""AppDynamics ETL - Mock Data Generator with Standard _id Naming"""
import psycopg2, os, time, random
from datetime import datetime, timedelta

# Configuration
DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_NAME = os.getenv('DB_NAME', 'appd_licensing')
DB_USER = os.getenv('DB_USER', 'appd_ro')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'appd_pass')

MOCK_START = datetime(2025, 7, 30)
MOCK_END = datetime(2025, 10, 28)
APPS = [
    {"name": "Supply Chain Visibility", "team": "Frito-Lay", "owner": "Alice Johnson"},
    {"name": "Global Inventory", "team": "Beverages", "owner": "Bob Williams"},
    {"name": "eCommerce Portal", "team": "Digital", "owner": "Carol Davis"}
]

def get_conn():
    for i in range(5):
        try:
            return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)
        except: 
            if i < 4: time.sleep(2**i)
            else: raise

def upsert_apps(conn):
    cur = conn.cursor()
    for app in APPS:
        cur.execute("SELECT app_id FROM applications_dim WHERE appd_application_name = %s", (app['name'],))
        result = cur.fetchone()
        if result:
            app['id'] = result[0]
        else:
            cur.execute("""INSERT INTO applications_dim (appd_application_name, owner_id, sector_id, architecture_id)
                          VALUES (%s, 1, 1, 2) RETURNING app_id""", (app['name'],))
            app['id'] = cur.fetchone()[0]
    conn.commit()
    return APPS

def insert_usage(conn, apps):
    cur = conn.cursor()
    # Get capability IDs
    cur.execute("SELECT capability_id, capability_code FROM capabilities_dim")
    caps = {row[1]: row[0] for row in cur.fetchall()}
    
    data = []
    current = MOCK_START
    while current <= MOCK_END:
        for app in apps:
            for cap_code in ['APM', 'MRUM']:
                tier = random.choice(['PEAK', 'PRO'])
                units = round(random.uniform(50, 500), 2)
                nodes = random.randint(5, 50)
                data.append((current, app['id'], caps[cap_code], tier, units, nodes))
        current += timedelta(days=1)
    
    cur.executemany("""INSERT INTO license_usage_fact (ts, app_id, capability_id, tier, units_consumed, nodes_count)
                       VALUES (%s, %s, %s, %s, %s, %s)""", data)
    conn.commit()
    print(f"✅ Inserted {len(data)} usage records")

def run_appd_etl():
    print("AppDynamics ETL Starting (Mock Data)")
    conn = None
    try:
        conn = get_conn()
        apps = upsert_apps(conn)
        insert_usage(conn, apps)
        print(f"✅ Complete: {len(apps)} apps, {(MOCK_END - MOCK_START).days + 1} days")
    except Exception as e:
        print(f"❌ FATAL: {e}")
    finally:
        if conn: conn.close()

if __name__ == '__main__': run_appd_etl()
#!/usr/bin/env python3
"""ServiceNow ETL - Real API Integration with OAuth 2.0 Support"""
import requests
import psycopg2
from psycopg2.extras import execute_values
import os
from datetime import datetime

def extract_sys_id(item):
    """Extract sys_id from either string or dict format"""
    if isinstance(item, dict):
        return item.get('value') or item.get('sys_id')
    return item

def get_oauth_token(client_id, client_secret, instance):
    """Get OAuth token from ServiceNow"""
    token_url = f"https://{instance}.service-now.com/oauth_token.do"
    
    try:
        response = requests.post(
            token_url,
            auth=(client_id, client_secret),
            data={'grant_type': 'client_credentials'},
            timeout=30
        )
        response.raise_for_status()
        return response.json()['access_token']
    except Exception as e:
        print(f"Error getting OAuth token: {e}")
        raise

def query_snow_paginated(access_token, instance, table, fields, query=None, limit=100):
    """Fetch data from ServiceNow with pagination"""
    base_url = f"https://{instance}.service-now.com/api/now/table/{table}"
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    
    all_records = []
    offset = 0
    batch_count = 0
    start_time = datetime.now()
    
    while True:
        params = {
            "sysparm_fields": ','.join(fields),
            "sysparm_limit": limit,
            "sysparm_offset": offset,
            "sysparm_exclude_reference_link": "true",
            "sysparm_no_count": "true"  # Speed optimization - don't count total records
        }
        if query:
            params["sysparm_query"] = query
        
        try:
            batch_start = datetime.now()
            response = requests.get(base_url, headers=headers, params=params, timeout=60)
            response.raise_for_status()
            batch_time = (datetime.now() - batch_start).total_seconds()
            
            records = response.json().get("result", [])
            if not records:
                break
            
            all_records.extend(records)
            batch_count += 1
            
            # Progress update every batch
            elapsed = (datetime.now() - start_time).total_seconds()
            rate = len(all_records) / elapsed if elapsed > 0 else 0
            if batch_count % 2 == 0:
                print(f"  ✓ Fetched {len(all_records)} records ({rate:.0f} rec/sec, batch time: {batch_time:.1f}s)...")
            
            offset += limit
            
            # Safety check: if we've been running over 240 seconds, stop and process what we have
            if elapsed > 240:
                print(f"  ⚠️  Approaching timeout. Stopping fetch after {len(all_records)} records.")
                break
            
        except requests.exceptions.Timeout:
            print(f"  ⚠️  Request timed out at offset {offset}. Continuing with {len(all_records)} collected records...")
            break
        except requests.exceptions.RequestException as e:
            print(f"  ⚠️  Request error at offset {offset}: {e}. Continuing with {len(all_records)} collected records...")
            break
        except Exception as e:
            print(f"  ❌ Unexpected error: {e}")
            break
    
    total_time = (datetime.now() - start_time).total_seconds()
    print(f"  ✓ Retrieved {len(all_records)} records in {batch_count} batches ({total_time:.1f} seconds)")
    return all_records

def get_applications(access_token, instance):
    """Fetch applications from ServiceNow CMDB"""
    print("Fetching ServiceNow applications (cmdb_ci_service)...")
    
    # Only fetch operational applications, exclude test/dev environments where possible
    query = "operational_status=1^ORoperational_status=2"  # 1=Operational, 2=In Planning
    
    apps = query_snow_paginated(
        access_token, instance,
        table='cmdb_ci_service',
        fields=['sys_id', 'name'],  # Only essential fields
        query=query,
        limit=250  # Larger page size = fewer requests
    )
    
    print(f"✓ Retrieved {len(apps)} applications")
    return apps

def get_app_server_relationships(access_token, instance):
    """Fetch app-to-server relationships from ServiceNow"""
    print("Fetching application-to-server relationships...")
    
    # Relationship types that link apps to servers
    relationship_types = [
        "Runs on::Runs",
        "Depends on::Used by",
        "Contains::Contained by",
        "Hosted on::Hosts"
    ]
    
    all_relationships = []
    
    for rel_type in relationship_types:
        print(f"  Querying '{rel_type}' relationships...")
        
        rels = query_snow_paginated(
            access_token, instance,
            table='cmdb_rel_ci',
            fields=['parent', 'child', 'type'],
            query=f"type.name={rel_type}",
            limit=100
        )
        
        all_relationships.extend(rels)
        print(f"    Found {len(rels)} '{rel_type}' relationships")
    
    print(f"✓ Retrieved {len(all_relationships)} total app-server relationships")
    return all_relationships

def upsert_applications(conn, apps):
    """Insert or update applications in the database"""
    print("Upserting applications into applications_dim...")
    
    cursor = conn.cursor()
    
    records = []
    for app in apps:
        app_id = extract_sys_id(app.get('sys_id'))
        name = extract_sys_id(app.get('name'))
        
        records.append((
            app_id,
            name
        ))
    
    insert_query = """
        INSERT INTO applications_dim (sn_sys_id, sn_service_name)
        VALUES %s
        ON CONFLICT (sn_sys_id) DO UPDATE SET
            sn_service_name = EXCLUDED.sn_service_name,
            updated_at = CURRENT_TIMESTAMP
    """
    
    execute_values(cursor, insert_query, records)
    conn.commit()
    print(f"✓ Upserted {len(records)} applications")

def upsert_applications_batched(conn, apps, batch_size=1000):
    """Insert or update applications in batches"""
    print(f"Upserting applications into applications_dim (batch size: {batch_size})...")
    
    cursor = conn.cursor()
    total_upserted = 0
    
    for i in range(0, len(apps), batch_size):
        batch = apps[i:i+batch_size]
        records = []
        
        for app in batch:
            app_sys_id = extract_sys_id(app.get('sys_id'))
            name = extract_sys_id(app.get('name'))
            
            if app_sys_id:  # Only insert if we have a sys_id
                records.append((app_sys_id, name))
        
        if records:
            insert_query = """
                INSERT INTO applications_dim (sn_sys_id, sn_service_name)
                VALUES %s
                ON CONFLICT (sn_sys_id) DO UPDATE SET
                    sn_service_name = EXCLUDED.sn_service_name,
                    updated_at = CURRENT_TIMESTAMP
            """
            
            try:
                execute_values(cursor, insert_query, records)
                conn.commit()
                total_upserted += len(records)
                print(f"  ✓ Batch {i//batch_size + 1}: Upserted {len(records)} applications ({total_upserted}/{len(apps)} total)")
            except Exception as e:
                print(f"  ❌ Error upserting batch: {e}")
                conn.rollback()
                raise
    
    print(f"✓ Total applications upserted: {total_upserted}")

def get_servers(access_token, instance):
    """Fetch servers from ServiceNow CMDB"""
    print("Fetching ServiceNow servers (cmdb_ci_server)...")
    
    # Only fetch operational servers
    query = "operational_status=1"
    
    servers = query_snow_paginated(
        access_token, instance,
        table='cmdb_ci_server',
        fields=['sys_id', 'name', 'os'],  # Only essential fields
        query=query,
        limit=250
    )
    
    print(f"✓ Retrieved {len(servers)} servers")
    return servers

def upsert_servers(conn, servers):
    """Insert or update servers in the database"""
    print("Upserting servers into servers_dim...")
    
    cursor = conn.cursor()
    
    records = []
    for server in servers:
        server_sys_id = extract_sys_id(server.get('sys_id'))
        name = extract_sys_id(server.get('name'))
        os_type = extract_sys_id(server.get('os'))
        
        records.append((
            server_sys_id,
            name,
            os_type
        ))
    
    insert_query = """
        INSERT INTO servers_dim (sn_sys_id, server_name, os)
        VALUES %s
        ON CONFLICT (sn_sys_id) DO UPDATE SET
            server_name = EXCLUDED.server_name,
            os = EXCLUDED.os,
            updated_at = CURRENT_TIMESTAMP
    """
    
    execute_values(cursor, insert_query, records)
    conn.commit()
    print(f"✓ Upserted {len(records)} servers")

def upsert_servers_batched(conn, servers, batch_size=1000):
    """Insert or update servers in batches"""
    print(f"Upserting servers into servers_dim (batch size: {batch_size})...")
    
    cursor = conn.cursor()
    total_upserted = 0
    
    for i in range(0, len(servers), batch_size):
        batch = servers[i:i+batch_size]
        records = []
        
        for server in batch:
            server_sys_id = extract_sys_id(server.get('sys_id'))
            name = extract_sys_id(server.get('name'))
            os_type = extract_sys_id(server.get('os'))
            
            if server_sys_id:
                records.append((server_sys_id, name, os_type))
        
        if records:
            insert_query = """
                INSERT INTO servers_dim (sn_sys_id, server_name, os)
                VALUES %s
                ON CONFLICT (sn_sys_id) DO UPDATE SET
                    server_name = EXCLUDED.server_name,
                    os = EXCLUDED.os,
                    updated_at = CURRENT_TIMESTAMP
            """
            
            try:
                execute_values(cursor, insert_query, records)
                conn.commit()
                total_upserted += len(records)
                print(f"  ✓ Batch {i//batch_size + 1}: Upserted {len(records)} servers ({total_upserted}/{len(servers)} total)")
            except Exception as e:
                print(f"  ❌ Error upserting batch: {e}")
                conn.rollback()
                raise
    
    print(f"✓ Total servers upserted: {total_upserted}")

def upsert_app_server_mappings(conn, relationships, apps, servers):
    """Process and insert app-to-server mappings"""
    print("Processing app-to-server relationships...")
    
    cursor = conn.cursor()
    
    # Create lookup dictionaries by sys_id
    app_lookup = {extract_sys_id(app.get('sys_id')): app for app in apps}
    server_lookup = {extract_sys_id(server.get('sys_id')): server for server in servers}
    
    # Now look up the actual database IDs
    app_sys_id_to_id = {}
    server_sys_id_to_id = {}
    
    # Get app_id mappings
    app_sys_ids = list(app_lookup.keys())
    if app_sys_ids:
        placeholders = ','.join(['%s'] * len(app_sys_ids))
        cursor.execute(f"SELECT app_id, sn_sys_id FROM applications_dim WHERE sn_sys_id IN ({placeholders})", app_sys_ids)
        for app_id, sn_sys_id in cursor.fetchall():
            app_sys_id_to_id[sn_sys_id] = app_id
    
    # Get server_id mappings
    server_sys_ids = list(server_lookup.keys())
    if server_sys_ids:
        placeholders = ','.join(['%s'] * len(server_sys_ids))
        cursor.execute(f"SELECT server_id, sn_sys_id FROM servers_dim WHERE sn_sys_id IN ({placeholders})", server_sys_ids)
        for server_id, sn_sys_id in cursor.fetchall():
            server_sys_id_to_id[sn_sys_id] = server_id
    
    records = []
    skipped = 0
    
    for rel in relationships:
        parent_sys_id = extract_sys_id(rel.get('parent'))
        child_sys_id = extract_sys_id(rel.get('child'))
        rel_type = extract_sys_id(rel.get('type'))
        
        app_id = None
        server_id = None
        relationship_type = rel_type if rel_type else "Unknown"
        
        # Determine which is app and which is server
        if parent_sys_id in app_lookup and child_sys_id in server_lookup:
            app_id = app_sys_id_to_id.get(parent_sys_id)
            server_id = server_sys_id_to_id.get(child_sys_id)
        elif parent_sys_id in server_lookup and child_sys_id in app_lookup:
            app_id = app_sys_id_to_id.get(child_sys_id)
            server_id = server_sys_id_to_id.get(parent_sys_id)
        else:
            # Could be app-to-app or other relationships
            skipped += 1
            continue
        
        if app_id and server_id:
            records.append((app_id, server_id, relationship_type))
    
    if records:
        insert_query = """
            INSERT INTO app_server_mapping (app_id, server_id, relationship_type)
            VALUES %s
            ON CONFLICT (app_id, server_id) DO UPDATE SET
                relationship_type = EXCLUDED.relationship_type,
                created_at = CURRENT_TIMESTAMP
        """
        
        execute_values(cursor, insert_query, records)
        conn.commit()
        print(f"✓ Upserted {len(records)} app-server mappings")
    
    if skipped > 0:
        print(f"⚠️  Skipped {skipped} relationships (not app-to-server)")

def main():
    """Main ServiceNow ETL process"""
    print("="*70)
    print("ServiceNow CMDB ETL")
    print("="*70)
    print()
    
    # Get credentials from environment
    sn_instance = os.getenv('SN_INSTANCE')
    sn_client_id = os.getenv('SN_CLIENT_ID')
    sn_client_secret = os.getenv('SN_CLIENT_SECRET')
    
    db_host = os.getenv('DB_HOST')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')
    
    # Get OAuth token
    print("Authenticating with ServiceNow...")
    access_token = get_oauth_token(sn_client_id, sn_client_secret, sn_instance)
    print("✓ Authentication successful\n")
    
    # Connect to database
    print("Connecting to database...")
    conn = psycopg2.connect(
        host=db_host,
        database=db_name,
        user=db_user,
        password=db_password
    )
    print("✓ Database connection successful\n")
    
    try:
        # Fetch and load data
        print("STEP 1: Applications")
        print("-"*70)
        apps = get_applications(access_token, sn_instance)
        if not apps:
            print("⚠️  No applications found. Continuing anyway...")
        else:
            upsert_applications_batched(conn, apps, batch_size=500)
        print()
        
        print("STEP 2: Servers")
        print("-"*70)
        servers = get_servers(access_token, sn_instance)
        if not servers:
            print("⚠️  No servers found. Continuing anyway...")
        else:
            upsert_servers_batched(conn, servers, batch_size=500)
        print()
        
        print("STEP 3: Application-to-Server Relationships")
        print("-"*70)
        if apps and servers:
            relationships = get_app_server_relationships(access_token, sn_instance)
            if relationships:
                upsert_app_server_mappings(conn, relationships, apps, servers)
            else:
                print("⚠️  No relationships found")
        else:
            print("⊘ Skipping relationships (no apps or servers)")
        print()
        
        print("="*70)
        print("✅ ServiceNow ETL completed successfully")
        print("="*70)
        
    except Exception as e:
        print(f"❌ Error during ETL: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    main()
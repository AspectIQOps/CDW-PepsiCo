#!/usr/bin/env python3
"""
ServiceNow ETL - OPTIMIZED to only fetch servers for AppDynamics-monitored applications
Key Change: Filters to only AppD apps BEFORE querying for servers
"""

# [Keep all your imports and helper functions from lines 1-200]

def get_appd_monitored_app_sys_ids(conn):
    """
    Get ServiceNow sys_ids for applications that are monitored in AppDynamics
    This is the KEY optimization - only fetch servers for apps we actually monitor
    
    Returns: List of sn_sys_id values for AppD-monitored apps
    """
    cursor = conn.cursor()
    
    # Query applications that have BOTH AppD and ServiceNow data
    # These are the ~128 apps we actually care about for licensing
    cursor.execute("""
        SELECT sn_sys_id, appd_application_name, sn_service_name
        FROM applications_dim
        WHERE sn_sys_id IS NOT NULL 
          AND appd_application_id IS NOT NULL
    """)
    
    results = cursor.fetchall()
    cursor.close()
    
    if not results:
        print("⚠️  No AppDynamics-monitored apps found with ServiceNow links")
        print("   This means reconciliation hasn't run yet or no apps matched")
        print("   Will try using ALL applications as fallback")
        return None
    
    app_sys_ids = [row[0] for row in results]
    print(f"✓ Found {len(app_sys_ids)} AppDynamics-monitored applications with ServiceNow links")
    print(f"  (Will ONLY fetch servers for these {len(app_sys_ids)} apps, not all 19,944)")
    
    # Show some examples
    for row in results[:5]:
        print(f"    • {row[1]} → {row[2]}")
    if len(results) > 5:
        print(f"    ... and {len(results) - 5} more")
    
    return app_sys_ids


def fetch_and_load_servers_for_appd_apps(conn, access_token, instance):
    """
    Fetch servers ONLY for AppDynamics-monitored applications
    This dramatically reduces the query scope from 19,944 apps to ~128 apps
    
    Expected reduction: 67,500 servers → ~500-2000 servers
    """
    print("Fetching servers for AppDynamics-monitored applications...")
    
    # Step 1: Get list of AppD-monitored app sys_ids
    app_sys_ids = get_appd_monitored_app_sys_ids(conn)
    
    if not app_sys_ids:
        # Fallback: Use applications that have AppD data (even if not matched to ServiceNow yet)
        print("⚠️  Using fallback: querying by AppD application names")
        cursor = conn.cursor()
        cursor.execute("""
            SELECT DISTINCT sn_sys_id
            FROM applications_dim
            WHERE appd_application_id IS NOT NULL AND sn_sys_id IS NOT NULL
        """)
        results = cursor.fetchall()
        app_sys_ids = [row[0] for row in results if row[0]]
        cursor.close()
        
        if not app_sys_ids:
            print("❌ Cannot find any applications to query servers for")
            print("   Possible reasons:")
            print("   1. AppDynamics ETL hasn't run yet")
            print("   2. Reconciliation hasn't matched any apps")
            print("   3. No AppD apps have ServiceNow sys_ids")
            return 0
    
    print(f"\n📊 Query scope: {len(app_sys_ids)} applications (not 19,944!)")
    
    # Step 2: Query relationships for ONLY these AppD apps
    print("\n[Step 1/2] Fetching relationships for AppD-monitored apps...")
    all_relationships = []
    batch_size = 100
    
    for i in range(0, len(app_sys_ids), batch_size):
        batch = app_sys_ids[i:i+batch_size]
        
        # Use "Depends on::Used by" as discovered in diagnostics
        query = f"type.name=Depends on::Used by^parentIN{','.join(batch)}"
        
        print(f"  Querying relationship batch {i//batch_size + 1}/{(len(app_sys_ids)-1)//batch_size + 1}")
        
        rels = query_snow_paginated(
            access_token, instance,
            table='cmdb_rel_ci',
            fields=['parent', 'child', 'type'],
            query=query,
            limit=250
        )
        all_relationships.extend(rels)
    
    print(f"✓ Retrieved {len(all_relationships)} total relationships")
    
    if len(all_relationships) == 0:
        print("⚠️  No 'Depends on::Used by' relationships found")
        print("   Your CMDB may not track app-to-server relationships")
        print("   Continuing without server data...")
        return 0
    
    # Step 3: Extract unique server sys_ids
    server_sys_ids = set()
    for rel in all_relationships:
        child = rel.get('child', {})
        child_sys_id = child.get('value') if isinstance(child, dict) else child
        if child_sys_id:
            server_sys_ids.add(child_sys_id)
    
    print(f"✓ Identified {len(server_sys_ids)} unique servers from relationships")
    
    if len(server_sys_ids) == 0:
        print("⚠️  No servers identified in relationships")
        return 0
    
    # Step 4: Fetch ONLY these specific servers
    print(f"\n[Step 2/2] Fetching {len(server_sys_ids)} servers...")
    success = 0
    batch_size = 50
    server_list = list(server_sys_ids)
    
    for i in range(0, len(server_list), batch_size):
        batch = server_list[i:i+batch_size]
        query = f"sys_idIN{','.join(batch)}"
        
        if (i // batch_size) % 10 == 0:
            print(f"  Fetching server batch {i//batch_size + 1}/{(len(server_list)-1)//batch_size + 1}")
        
        servers = query_snow_paginated(
            access_token, instance,
            table='cmdb_ci_server',
            fields=['sys_id', 'name', 'ip_address', 'os', 'virtual'],
            query=query,
            limit=250
        )
        
        # Upsert immediately (don't accumulate in memory)
        for server in servers:
            try:
                cursor = conn.cursor()
                
                server_sys_id = extract_sys_id(server.get('sys_id'))
                name = safe_truncate(extract_sys_id(server.get('name')), 255, "server name")
                os_type = safe_truncate(extract_sys_id(server.get('os')), 255, "OS")  # NOW 255!
                ip_address = safe_truncate(extract_sys_id(server.get('ip_address')), 100, "IP")  # NOW 100!
                
                virtual_raw = extract_sys_id(server.get('virtual'))
                if virtual_raw in ['true', 'True', '1', 'yes']:
                    is_virtual = True
                elif virtual_raw in ['false', 'False', '0', 'no']:
                    is_virtual = False
                else:
                    is_virtual = False
                
                if server_sys_id and name:
                    cursor.execute("""
                        INSERT INTO servers_dim (sn_sys_id, server_name, os, ip_address, is_virtual)
                        VALUES (%s, %s, %s, %s, %s)
                        ON CONFLICT (sn_sys_id) DO UPDATE SET
                            server_name = EXCLUDED.server_name,
                            os = EXCLUDED.os,
                            ip_address = EXCLUDED.ip_address,
                            is_virtual = EXCLUDED.is_virtual,
                            updated_at = CURRENT_TIMESTAMP
                    """, (server_sys_id, name, os_type, ip_address, is_virtual))
                    conn.commit()
                    success += 1
                
                cursor.close()
                
            except Exception as e:
                print(f"    ⚠️  Error upserting server: {str(e)[:100]}")
                conn.rollback()
    
    print(f"✓ Loaded {success} servers (only for AppD-monitored apps)")
    return success


def safe_truncate(value, max_length, field_name="field"):
    """Safely truncate string values"""
    if not value:
        return None
    s = str(value)
    if len(s) > max_length:
        return s[:max_length]
    return s


def main():
    """
    Main ServiceNow ETL - OPTIMIZED VERSION
    
    Key Changes:
    1. Loads ALL ServiceNow apps (for enrichment data - owner, sector, h_code)
    2. Identifies which apps are monitored in AppDynamics (~128 apps)
    3. ONLY fetches servers for those AppD-monitored apps
    4. Expected: 500-2000 servers instead of 67,500
    """
    print("="*70)
    print("ServiceNow CMDB ETL (AppDynamics-Optimized)")
    print("="*70)
    print()
    
    # [Keep your existing credential loading code]
    
    # Connect to database
    conn = psycopg2.connect(...)
    
    try:
        # Step 1: Load ALL applications (for enrichment)
        print("\n[1/3] Loading ALL ServiceNow applications...")
        print("      (These provide owner, sector, h_code data for enrichment)")
        apps = get_applications(access_token, instance)
        upsert_applications_batched(conn, apps, batch_size=500)
        
        # Step 2: Load servers ONLY for AppDynamics-monitored apps
        print("\n[2/3] Loading servers for AppDynamics-monitored applications...")
        print("      (This is the KEY optimization - not loading all 67,500 servers!)")
        servers_loaded = fetch_and_load_servers_for_appd_apps(conn, access_token, instance)
        
        # Step 3: Map relationships
        print("\n[3/3] Mapping application-server relationships...")
        relationships_mapped = fetch_and_map_relationships(conn, access_token, instance)
        
        print("="*70)
        print(f"✅ ServiceNow ETL Complete (Optimized)")
        print(f"   • Applications: {len(apps)}")
        print(f"   • Servers: {servers_loaded} (only for AppD apps)")
        print(f"   • Relationships: {relationships_mapped}")
        print("="*70)
        
    except Exception as e:
        print(f"❌ FATAL: {e}")
        import traceback
        traceback.print_exc()
    finally:
        conn.close()


if __name__ == "__main__":
    main()
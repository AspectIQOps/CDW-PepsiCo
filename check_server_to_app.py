#!/usr/bin/env python3
"""
Check if servers have relationships TO applications (reverse direction)
"""
import os
import sys
import requests
from requests.auth import HTTPBasicAuth

SN_INSTANCE = os.getenv('SN_INSTANCE', 'pepsicodev2')
SN_CLIENT_ID = os.getenv('SN_CLIENT_ID')
SN_CLIENT_SECRET = os.getenv('SN_CLIENT_SECRET')

def get_oauth_token():
    url = f"https://{SN_INSTANCE}.service-now.com/oauth_token.do"
    data = {
        'grant_type': 'client_credentials',
        'client_id': SN_CLIENT_ID,
        'client_secret': SN_CLIENT_SECRET
    }
    response = requests.post(url, data=data, timeout=30)
    return response.json()['access_token']

def query_snow(table, fields, query=None, limit=10):
    token = get_oauth_token()
    params = {
        'sysparm_fields': ','.join(fields),
        'sysparm_limit': limit,
        'sysparm_display_value': 'all'
    }
    if query:
        params['sysparm_query'] = query
    
    url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/{table}"
    headers = {'Authorization': f'Bearer {token}', 'Accept': 'application/json'}
    
    response = requests.get(url, headers=headers, params=params, timeout=60)
    response.raise_for_status()
    return response.json()['result']

def extract_sys_id(item):
    """Extract sys_id from either string or dict format"""
    if isinstance(item, dict):
        return item.get('value') or item.get('sys_id')
    return item

def extract_value(item):
    """Extract display value from either string or dict format"""
    if isinstance(item, dict):
        return item.get('display_value') or item.get('value') or str(item)
    return str(item)

print("="*80)
print("CHECKING SERVER-TO-APPLICATION RELATIONSHIPS")
print("="*80)

# Get some servers
print("\n1. Getting sample servers...")
servers = query_snow('cmdb_ci_server', ['sys_id', 'name', 'operational_status'], 
                    query='operational_status=1', limit=10)
server_sys_ids = [extract_sys_id(s['sys_id']) for s in servers]
print(f"   Found {len(servers)} operational servers:")
for s in servers:
    print(f"   - {extract_value(s.get('name'))}")

print("\n2. Testing relationship types (server as CHILD → app as PARENT)...")
child_parent_types = [
    'Hosted on::Hosts',
    'Runs on::Runs',
    'Depends on::Used by',
    'Contained by::Contains',
    'Managed by::Manages'
]

found_relationships = []
for rel_type in child_parent_types:
    batch = server_sys_ids[:5]  # Test with first 5 servers
    query = f"type.name={rel_type}^childIN{','.join(batch)}"
    try:
        rels = query_snow('cmdb_rel_ci', ['parent', 'child', 'type'], 
                         query=query, limit=50)
        if rels:
            print(f"   ✅ '{rel_type}': Found {len(rels)} relationships")
            found_relationships.extend(rels)
        else:
            print(f"   ⊘ '{rel_type}': No relationships found")
    except Exception as e:
        print(f"   ❌ '{rel_type}': Error - {str(e)}")

print("\n3. Testing relationship types (server as PARENT → app as CHILD)...")
parent_child_types = [
    'Hosts::Hosted on',
    'Runs::Runs on',
    'Contains::Contained by'
]

for rel_type in parent_child_types:
    batch = server_sys_ids[:5]
    query = f"type.name={rel_type}^parentIN{','.join(batch)}"
    try:
        rels = query_snow('cmdb_rel_ci', ['parent', 'child', 'type'], 
                         query=query, limit=50)
        if rels:
            print(f"   ✅ '{rel_type}': Found {len(rels)} relationships")
            found_relationships.extend(rels)
        else:
            print(f"   ⊘ '{rel_type}': No relationships found")
    except Exception as e:
        print(f"   ❌ '{rel_type}': Error - {str(e)}")

print("\n" + "="*80)
print("RESULTS:")
print("="*80)

if found_relationships:
    print(f"✅ FOUND {len(found_relationships)} RELATIONSHIPS\n")
    
    # Analyze what these link to
    parent_ids = [extract_sys_id(r.get('parent')) for r in found_relationships]
    child_ids = [extract_sys_id(r.get('child')) for r in found_relationships]
    
    print(f"Parent IDs count: {len(parent_ids)}")
    print(f"Child IDs count: {len(child_ids)}")
    
    # Remove duplicates and filter empty strings
    parent_ids = list(set([id for id in parent_ids if id]))
    child_ids = list(set([id for id in child_ids if id]))
    
    print(f"Unique parent IDs: {len(parent_ids)}")
    print(f"Unique child IDs: {len(child_ids)}")
    
    print("\nChecking if parents are applications...")
    try:
        # Query in smaller batches to avoid timeout
        parent_apps = []
        for i in range(0, len(parent_ids), 50):
            batch = parent_ids[i:i+50]
            query = f"sys_idIN{','.join(batch)}"
            apps = query_snow('cmdb_ci_service', ['sys_id', 'name'], 
                             query=query, limit=100)
            parent_apps.extend(apps)
            if apps:
                print(f"   Batch {i//50 + 1}: Found {len(apps)} applications")
        
        if parent_apps:
            print(f"\n✅ Found {len(parent_apps)} linked applications (as parents):")
            for app in parent_apps[:10]:
                print(f"   - {extract_value(app.get('name'))}")
    except Exception as e:
        print(f"   ⚠️  Error checking parent applications: {str(e)}")
    
    print("\nChecking if children are applications...")
    try:
        # Query in smaller batches to avoid timeout
        child_apps = []
        for i in range(0, len(child_ids), 50):
            batch = child_ids[i:i+50]
            print(f"   Querying batch {i//50 + 1} ({len(batch)} IDs)...", end="", flush=True)
            query = f"sys_idIN{','.join(batch)}"
            apps = query_snow('cmdb_ci_service', ['sys_id', 'name'], 
                             query=query, limit=100)
            child_apps.extend(apps)
            if apps:
                print(f" Found {len(apps)} applications")
            else:
                print(" No applications")
        
        if child_apps:
            print(f"\n✅ Found {len(child_apps)} linked applications (as children):")
            for app in child_apps[:10]:
                print(f"   - {extract_value(app.get('name'))}")
        else:
            print("\n⊘ No applications found as children")
    except Exception as e:
        print(f"   ⚠️  Error checking child applications: {str(e)}")
    
    print("\nChecking if children are servers...")
    try:
        child_servers = []
        for i in range(0, len(child_ids), 50):
            batch = child_ids[i:i+50]
            print(f"   Querying batch {i//50 + 1} ({len(batch)} IDs)...", end="", flush=True)
            query = f"sys_idIN{','.join(batch)}"
            servers = query_snow('cmdb_ci_server', ['sys_id', 'name'], 
                                query=query, limit=100)
            child_servers.extend(servers)
            if servers:
                print(f" Found {len(servers)} servers")
            else:
                print(" No servers")
        
        if child_servers:
            print(f"\n✅ Found {len(child_servers)} linked servers (as children):")
            for server in child_servers[:10]:
                print(f"   - {extract_value(server.get('name'))}")
    except Exception as e:
        print(f"   ⚠️  Error checking child servers: {str(e)}")

else:
    print("❌ NO APP-SERVER RELATIONSHIPS FOUND")
    print("\nPossible reasons:")
    print("  1. App-server relationships don't exist in your CMDB")
    print("  2. The relationship types used don't link servers to apps")
    print("  3. Need to check what relationship types actually exist")
    print("\nSuggestion: Run 'list all relationship types' query:")
    print("  Query: cmdb_rel_ci table with unique relationship types")

print("="*80)
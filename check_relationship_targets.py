#!/usr/bin/env python3
"""
Check what 'Depends on::Used by' relationships actually link to
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

def extract_sys_id(item):
    """Extract sys_id from either string or dict format"""
    if isinstance(item, dict):
        return item.get('value') or item.get('sys_id')
    return item

def query_snow(table, fields, query=None, limit=10):
    token = get_oauth_token()
    params = {
        'sysparm_fields': ','.join(fields),
        'sysparm_limit': limit,
        'sysparm_display_value': 'all'  # Get both value and display_value
    }
    if query:
        params['sysparm_query'] = query
    
    url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/{table}"
    headers = {'Authorization': f'Bearer {token}', 'Accept': 'application/json'}
    
    response = requests.get(url, headers=headers, params=params, timeout=60)
    response.raise_for_status()
    return response.json()['result']

print("="*80)
print("ANALYZING 'Depends on::Used by' RELATIONSHIP TARGETS")
print("="*80)

# Get some apps
print("\n1. Getting sample applications...")
apps = query_snow('cmdb_ci_service', ['sys_id', 'name'], 
                  query='install_status=1^operational_status=1', limit=100)
# Extract sys_ids properly
app_sys_ids = [extract_sys_id(app['sys_id']) for app in apps]
print(f"   Found {len(apps)} applications")

# Get relationships
print("\n2. Querying 'Depends on::Used by' relationships...")
batch = app_sys_ids[:50]
query = f"type.name=Depends on::Used by^parentIN{','.join(batch)}"
rels = query_snow('cmdb_rel_ci', ['parent', 'child', 'type'], query=query, limit=50)
print(f"   Found {len(rels)} relationships")

if not rels:
    print("   No relationships found!")
    sys.exit(0)

# Analyze what the children are
print("\n3. Analyzing child objects (what apps depend on)...")
child_sys_ids = []
for rel in rels:
    child_id = extract_sys_id(rel.get('child'))
    if child_id:
        child_sys_ids.append(child_id)

print(f"   Found {len(child_sys_ids)} unique child objects")

# Try to identify what type of CIs these are
print("\n4. Checking if children are servers (cmdb_ci_server)...")
for i in range(0, len(child_sys_ids[:10]), 10):
    batch = child_sys_ids[i:i+10]
    query = f"sys_idIN{','.join(batch)}"
    servers = query_snow('cmdb_ci_server', ['sys_id', 'name', 'sys_class_name'], 
                        query=query, limit=10)
    if servers:
        print(f"   ✅ Found {len(servers)} SERVERS:")
        for s in servers[:5]:
            name = s.get('name', {})
            if isinstance(name, dict):
                name = name.get('display_value', 'N/A')
            sys_class = s.get('sys_class_name', {})
            if isinstance(sys_class, dict):
                sys_class = sys_class.get('display_value', 'N/A')
            print(f"      - {name} (class: {sys_class})")

print("\n5. Checking if children are other applications (cmdb_ci_service)...")
for i in range(0, len(child_sys_ids[:10]), 10):
    batch = child_sys_ids[i:i+10]
    query = f"sys_idIN{','.join(batch)}"
    services = query_snow('cmdb_ci_service', ['sys_id', 'name'], 
                         query=query, limit=10)
    if services:
        print(f"   ✅ Found {len(services)} APPLICATIONS:")
        for s in services[:5]:
            name = s.get('name', {})
            if isinstance(name, dict):
                name = name.get('display_value', 'N/A')
            print(f"      - {name}")

print("\n6. Checking if children are databases (cmdb_ci_database)...")
for i in range(0, len(child_sys_ids[:10]), 10):
    batch = child_sys_ids[i:i+10]
    query = f"sys_idIN{','.join(batch)}"
    try:
        dbs = query_snow('cmdb_ci_database', ['sys_id', 'name'], 
                        query=query, limit=10)
        if dbs:
            print(f"   ✅ Found {len(dbs)} DATABASES:")
            for d in dbs[:5]:
                name = d.get('name', {})
                if isinstance(name, dict):
                    name = name.get('display_value', 'N/A')
                print(f"      - {name}")
    except:
        print("   ⊘ No databases found")

print("\n" + "="*80)
print("SUMMARY:")
print("="*80)
print("'Depends on::Used by' relationships link applications to:")
print("  - Other applications (service dependencies)")
print("  - Databases")
print("  - Potentially servers")
print("\nThis is different from 'Hosted on::Hosts' which links apps to servers.")
print("\nFor server relationships, you may need to:")
print("  1. Query from the SERVER side (child looking for parent)")
print("  2. Use a different relationship type")
print("  3. Check if app-server links exist in your CMDB at all")
print("="*80)
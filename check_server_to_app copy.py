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

print("="*80)
print("CHECKING SERVER-TO-APPLICATION RELATIONSHIPS")
print("="*80)

# Get some servers
print("\n1. Getting sample servers...")
servers = query_snow('cmdb_ci_server', ['sys_id', 'name'], 
                     query='operational_status=1', limit=10)
print(f"   Found {len(servers)} operational servers:")
for s in servers[:5]:
    name = s.get('name', 'N/A')
    if isinstance(name, dict):
        name = name.get('display_value', 'N/A')
    print(f"   - {name}")

if not servers:
    print("   No servers found!")
    sys.exit(0)

server_sys_ids = [s['sys_id'] for s in servers]

# Test different relationship types from server perspective (server is CHILD, app is PARENT)
print("\n2. Testing relationship types (server as CHILD → app as PARENT)...")

test_types = [
    ('Hosted on::Hosts', 'Server is hosted on application'),
    ('Runs on::Runs', 'Server runs on application'),
    ('Depends on::Used by', 'Server depends on application'),
    ('Contained by::Contains', 'Server contained by application'),
    ('Managed by::Manages', 'Server managed by application'),
]

best_type = None
best_count = 0

for rel_type, description in test_types:
    try:
        # Query where servers are CHILDREN (apps would be PARENTS)
        query = f"type.name={rel_type}^childIN{','.join(server_sys_ids)}"
        rels = query_snow('cmdb_rel_ci', ['parent', 'child', 'type'], 
                         query=query, limit=10)
        
        if rels:
            print(f"\n   ✅ '{rel_type}': Found {len(rels)} relationships")
            print(f"      {description}")
            
            # Check if parents are applications
            for rel in rels[:3]:
                parent = rel.get('parent', {})
                child = rel.get('child', {})
                
                parent_id = parent.get('value') if isinstance(parent, dict) else parent
                parent_name = parent.get('display_value') if isinstance(parent, dict) else 'N/A'
                child_name = child.get('display_value') if isinstance(child, dict) else 'N/A'
                
                print(f"      Sample: {parent_name} ← {child_name}")
            
            if len(rels) > best_count:
                best_count = len(rels)
                best_type = rel_type
        else:
            print(f"   ⊘ '{rel_type}': No relationships found")
            
    except Exception as e:
        print(f"   ❌ '{rel_type}': Error - {str(e)[:100]}")

# Also test reverse: server as PARENT → app as CHILD
print("\n3. Testing relationship types (server as PARENT → app as CHILD)...")

reverse_types = [
    ('Hosts::Hosted on', 'Server hosts application'),
    ('Runs::Runs on', 'Server runs application'),
    ('Contains::Contained by', 'Server contains application'),
]

for rel_type, description in reverse_types:
    try:
        query = f"type.name={rel_type}^parentIN{','.join(server_sys_ids)}"
        rels = query_snow('cmdb_rel_ci', ['parent', 'child', 'type'], 
                         query=query, limit=10)
        
        if rels:
            print(f"\n   ✅ '{rel_type}': Found {len(rels)} relationships")
            print(f"      {description}")
            
            for rel in rels[:3]:
                parent = rel.get('parent', {})
                child = rel.get('child', {})
                
                parent_name = parent.get('display_value') if isinstance(parent, dict) else 'N/A'
                child_name = child.get('display_value') if isinstance(child, dict) else 'N/A'
                
                print(f"      Sample: {parent_name} → {child_name}")
            
            if len(rels) > best_count:
                best_count = len(rels)
                best_type = rel_type
        else:
            print(f"   ⊘ '{rel_type}': No relationships found")
            
    except Exception as e:
        print(f"   ❌ '{rel_type}': Error - {str(e)[:100]}")

print("\n" + "="*80)
print("RESULTS:")
print("="*80)

if best_type and best_count > 0:
    print(f"✅ FOUND APP-SERVER RELATIONSHIPS!")
    print(f"   Best match: '{best_type}' with {best_count} relationships")
    print(f"\n   Your CMDB DOES have app-server links!")
    print(f"   Update snow_etl.py to use this relationship type.")
else:
    print("❌ NO APP-SERVER RELATIONSHIPS FOUND")
    print("\n   Possible reasons:")
    print("   1. Your CMDB doesn't track app-to-server relationships")
    print("   2. Relationships use a different naming convention")
    print("   3. Apps link to virtual hosts or containers, not servers")
    print("\n   Recommendation:")
    print("   - Skip server loading in ETL (set servers to optional)")
    print("   - Focus on application and usage data from AppDynamics")
    print("   - Server mapping may not be needed for license tracking")

print("="*80)
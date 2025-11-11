#!/usr/bin/env python3
"""
ServiceNow Relationship Diagnostic
Run this to understand your CMDB relationship structure
"""
import os
import requests
from requests.auth import HTTPBasicAuth

SN_INSTANCE = os.getenv('SN_INSTANCE')
SN_CLIENT_ID = os.getenv('SN_CLIENT_ID')
SN_CLIENT_SECRET = os.getenv('SN_CLIENT_SECRET')
SN_USER = os.getenv('SN_USER')
SN_PASS = os.getenv('SN_PASS')

def get_oauth_token():
    """Get OAuth token"""
    url = f"https://{SN_INSTANCE}.service-now.com/oauth_token.do"
    data = {
        'grant_type': 'client_credentials',
        'client_id': SN_CLIENT_ID,
        'client_secret': SN_CLIENT_SECRET
    }
    response = requests.post(url, data=data, timeout=30)
    return response.json()['access_token']

def query_snow(table, fields, query=None, limit=10):
    """Query ServiceNow with authentication"""
    use_oauth = bool(SN_CLIENT_ID and SN_CLIENT_SECRET)
    
    params = {
        'sysparm_fields': ','.join(fields),
        'sysparm_limit': limit
    }
    if query:
        params['sysparm_query'] = query
    
    url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/{table}"
    
    if use_oauth:
        token = get_oauth_token()
        headers = {'Authorization': f'Bearer {token}', 'Accept': 'application/json'}
        auth = None
    else:
        headers = {'Accept': 'application/json'}
        auth = HTTPBasicAuth(SN_USER, SN_PASS)
    
    response = requests.get(url, auth=auth, headers=headers, params=params, timeout=60)
    response.raise_for_status()
    return response.json()['result']

print("="*80)
print("SERVICENOW RELATIONSHIP DIAGNOSTIC")
print("="*80)

# Step 1: Get a sample application
print("\n1. Getting sample applications from cmdb_ci_service...")
apps = query_snow('cmdb_ci_service', ['sys_id', 'name'], 
                  query='install_status=1^operational_status=1', limit=5)
print(f"   Found {len(apps)} sample applications:")
for app in apps:
    print(f"   - {app['name']} (sys_id: {app['sys_id']})")

if not apps:
    print("   ❌ No applications found! Check your query filters.")
    exit(1)

sample_app_id = apps[0]['sys_id']
sample_app_name = apps[0]['name']

# Step 2: Find ALL relationships for this application (parent perspective)
print(f"\n2. Finding ALL relationships where '{sample_app_name}' is the PARENT...")
all_parent_rels = query_snow('cmdb_rel_ci', 
                             ['parent', 'child', 'type'], 
                             query=f'parent={sample_app_id}',
                             limit=50)
print(f"   Found {len(all_parent_rels)} relationships:")
for rel in all_parent_rels:
    rel_type = rel.get('type', {})
    type_name = rel_type.get('display_value') if isinstance(rel_type, dict) else rel_type
    child = rel.get('child', {})
    child_val = child.get('display_value') if isinstance(child, dict) else child
    print(f"   - Type: {type_name} → Child: {child_val}")

# Step 3: Find ALL relationships for this application (child perspective)
print(f"\n3. Finding ALL relationships where '{sample_app_name}' is the CHILD...")
all_child_rels = query_snow('cmdb_rel_ci', 
                            ['parent', 'child', 'type'], 
                            query=f'child={sample_app_id}',
                            limit=50)
print(f"   Found {len(all_child_rels)} relationships:")
for rel in all_child_rels:
    rel_type = rel.get('type', {})
    type_name = rel_type.get('display_value') if isinstance(rel_type, dict) else rel_type
    parent = rel.get('parent', {})
    parent_val = parent.get('display_value') if isinstance(parent, dict) else parent
    print(f"   - Type: {type_name} ← Parent: {parent_val}")

# Step 4: Check for common relationship types
print(f"\n4. Testing specific relationship types for ALL applications...")

test_types = [
    'Hosted on::Hosts',
    'Runs on::Runs',
    'Depends on::Used by',
    'Uses::Used by',
    'Contains::Contained by'
]

for rel_type in test_types:
    print(f"\n   Testing: {rel_type}")
    try:
        # Try different query syntaxes
        queries = [
            f'type.name={rel_type}',
            f'type={rel_type}',
            f'type.display_value={rel_type}'
        ]
        
        for i, query in enumerate(queries, 1):
            try:
                rels = query_snow('cmdb_rel_ci', ['parent', 'child', 'type'], 
                                query=query, limit=5)
                if rels:
                    print(f"   ✅ Query syntax {i} works: Found {len(rels)} relationships")
                    print(f"      Query: {query}")
                    for rel in rels[:2]:
                        parent = rel.get('parent', {})
                        child = rel.get('child', {})
                        parent_val = parent.get('display_value') if isinstance(parent, dict) else parent
                        child_val = child.get('display_value') if isinstance(child, dict) else child
                        print(f"      Sample: {parent_val} → {child_val}")
                    break
                else:
                    print(f"   ⚠️  Query syntax {i} returned 0 results")
            except Exception as e:
                print(f"   ❌ Query syntax {i} failed: {str(e)[:100]}")
    except Exception as e:
        print(f"   ❌ Error: {str(e)[:100]}")

# Step 5: Get relationship type statistics
print(f"\n5. Getting relationship type statistics (top 10)...")
try:
    # This query gets all relationships and groups by type
    all_rels = query_snow('cmdb_rel_ci', ['type'], query='', limit=1000)
    type_counts = {}
    for rel in all_rels:
        rel_type = rel.get('type', {})
        type_name = rel_type.get('display_value') if isinstance(rel_type, dict) else str(rel_type)
        type_counts[type_name] = type_counts.get(type_name, 0) + 1
    
    sorted_types = sorted(type_counts.items(), key=lambda x: x[1], reverse=True)[:10]
    print(f"   Top relationship types in your CMDB:")
    for rel_type, count in sorted_types:
        print(f"   - {rel_type}: {count} relationships")
except Exception as e:
    print(f"   ⚠️  Could not get statistics: {str(e)[:100]}")

print("\n" + "="*80)
print("RECOMMENDATIONS:")
print("="*80)

if all_parent_rels or all_child_rels:
    print("✅ Your application has relationships in CMDB")
    print("   Use the relationship types shown above in your ETL query")
else:
    print("⚠️  Sample application has NO relationships")
    print("   This could mean:")
    print("   1. Applications don't link to servers in your CMDB")
    print("   2. Relationships use a different CI type (not cmdb_ci_service)")
    print("   3. You may need to query from the server side instead")

print("\nNext steps:")
print("1. Review the relationship types found above")
print("2. Update snow_etl.py to use the correct relationship type")
print("3. Consider whether you need to query from child (server) perspective")
print("="*80)
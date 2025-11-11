#!/usr/bin/env python3
"""
ServiceNow Relationship Diagnostic
Run this to understand your CMDB relationship structure

Usage:
    python3 test_snow_relationships.py
    
Or with explicit credentials:
    SN_INSTANCE=pepsicodev2 SN_CLIENT_ID=xxx SN_CLIENT_SECRET=xxx python3 test_snow_relationships.py
"""
import os
import sys
import requests
from requests.auth import HTTPBasicAuth

# Try to load from environment first, then from AWS SSM if available
SN_INSTANCE = os.getenv('SN_INSTANCE', 'pepsicodev2')
SN_CLIENT_ID = os.getenv('SN_CLIENT_ID')
SN_CLIENT_SECRET = os.getenv('SN_CLIENT_SECRET')
SN_USER = os.getenv('SN_USER')
SN_PASS = os.getenv('SN_PASS')

# Try to load from SSM if not in environment
if not SN_CLIENT_ID or not SN_CLIENT_SECRET:
    try:
        import boto3
        ssm = boto3.client('ssm', region_name='us-east-1')
        
        params = ssm.get_parameters(
            Names=[
                '/pepsico/servicenow/instance',
                '/pepsico/servicenow/client_id',
                '/pepsico/servicenow/client_secret'
            ],
            WithDecryption=True
        )
        
        for param in params['Parameters']:
            name = param['Name']
            value = param['Value']
            if 'instance' in name:
                SN_INSTANCE = value
            elif 'client_id' in name:
                SN_CLIENT_ID = value
            elif 'client_secret' in name:
                SN_CLIENT_SECRET = value
        
        print(f"✓ Loaded credentials from AWS SSM")
    except:
        pass

if not (SN_CLIENT_ID and SN_CLIENT_SECRET) and not (SN_USER and SN_PASS):
    print("ERROR: No ServiceNow credentials found!")
    print("Set environment variables: SN_INSTANCE, SN_CLIENT_ID, SN_CLIENT_SECRET")
    print("Or: SN_INSTANCE, SN_USER, SN_PASS")
    sys.exit(1)

print(f"Using instance: {SN_INSTANCE}")

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
print(f"   (Using first 100 application sys_ids to test queries)")

# Get list of app sys_ids to test with
app_sys_ids = [app['sys_id'] for app in apps]
if len(apps) < 5:
    # Get more apps for testing
    more_apps = query_snow('cmdb_ci_service', ['sys_id'], 
                          query='install_status=1^operational_status=1', limit=100)
    app_sys_ids = [app['sys_id'] for app in more_apps]

print(f"   Testing with {len(app_sys_ids)} application IDs")

test_types = [
    'Hosted on::Hosts',
    'Runs on::Runs',
    'Depends on::Used by',
    'Uses::Used by',
    'Contains::Contained by'
]

best_query = None
best_count = 0

for rel_type in test_types:
    print(f"\n   Testing: {rel_type}")
    try:
        # Test the query that ETL will actually use
        batch = app_sys_ids[:50]  # Test with first 50
        query = f"type.name={rel_type}^parentIN{','.join(batch)}"
        
        print(f"   Query: {query[:100]}...")
        rels = query_snow('cmdb_rel_ci', ['parent', 'child', 'type'], 
                        query=query, limit=10)
        
        if rels:
            print(f"   ✅ Found {len(rels)} relationships with this type!")
            
            # Extract actual sys_id values (not display values)
            for rel in rels[:3]:
                parent = rel.get('parent', {})
                child = rel.get('child', {})
                
                # ServiceNow returns references as objects with 'value' and 'link'
                parent_id = parent.get('value') if isinstance(parent, dict) else parent
                child_id = child.get('value') if isinstance(child, dict) else child
                
                print(f"      Sample: parent={parent_id[:20]}... child={child_id[:20] if child_id else 'None'}...")
            
            if len(rels) > best_count:
                best_count = len(rels)
                best_query = rel_type
        else:
            print(f"   ⚠️  Query returned 0 results for these applications")
            
    except Exception as e:
        print(f"   ❌ Error: {str(e)[:200]}")

if best_query:
    print(f"\n   🎯 BEST MATCH: '{best_query}' returned {best_count} relationships")
    print(f"   Use this in your snow_etl.py queries!")

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

if best_query and best_count > 0:
    print(f"✅ FOUND WORKING RELATIONSHIP TYPE: '{best_query}'")
    print(f"   This returned {best_count} relationships when queried with your applications")
    print(f"\n   Update your snow_etl.py to use:")
    print(f"   query = f\"type.name={best_query}^parentIN{{','.join(batch)}}\"")
elif all_parent_rels or all_child_rels:
    print("✅ Your application has relationships in CMDB")
    print("   Use the relationship types shown above in your ETL query")
else:
    print("⚠️  Sample application has NO relationships")
    print("   This could mean:")
    print("   1. Applications don't link to servers in your CMDB")
    print("   2. Relationships use a different CI type (not cmdb_ci_service)")
    print("   3. The sample applications chosen don't have relationships")
    print("   4. You may need to query from the server side instead")

print("\nNext steps:")
if best_query:
    print(f"1. Use '{best_query}' as your relationship type in snow_etl.py")
    print("2. The query syntax is correct: type.name=X^parentINY")
    print("3. Re-run your ETL pipeline")
else:
    print("1. Try querying from the server side (child → parent)")
    print("2. Check if your apps use a different CI class")
    print("3. Verify relationships exist in ServiceNow UI")
print("="*80)
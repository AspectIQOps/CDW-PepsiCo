#!/usr/bin/env python3
"""
Test ServiceNow OAuth 2.0 connection with credentials from AWS SSM
"""
import os
import sys
import requests
from requests.auth import HTTPBasicAuth

# Load credentials from environment (same way entrypoint.sh does)
SN_INSTANCE = os.getenv('SN_INSTANCE')
SN_CLIENT_ID = os.getenv('SN_CLIENT_ID')
SN_CLIENT_SECRET = os.getenv('SN_CLIENT_SECRET')

print("=" * 60)
print("ServiceNow OAuth 2.0 Connection Test")
print("=" * 60)
print()

# Validate credentials are loaded
print("1. Checking credentials...")
if not SN_INSTANCE:
    print("❌ SN_INSTANCE not set")
    sys.exit(1)
if not SN_CLIENT_ID:
    print("❌ SN_CLIENT_ID not set")
    sys.exit(1)
if not SN_CLIENT_SECRET:
    print("❌ SN_CLIENT_SECRET not set")
    sys.exit(1)

print(f"✓ SN_INSTANCE: {SN_INSTANCE}")
print(f"✓ SN_CLIENT_ID: {SN_CLIENT_ID[:10]}...{SN_CLIENT_ID[-4:]}")
print(f"✓ SN_CLIENT_SECRET: {'*' * 20}")
print()

# Build OAuth token URL
token_url = f"https://{SN_INSTANCE}.service-now.com/oauth_token.do"
print(f"2. Token URL: {token_url}")
print()

# Try OAuth token request
print("3. Requesting OAuth token...")
print()

configurations = [
    {
        "name": "Config 1: Standard OAuth with form data",
        "method": "POST",
        "url": token_url,
        "data": {
            "grant_type": "client_credentials",
            "client_id": SN_CLIENT_ID,
            "client_secret": SN_CLIENT_SECRET
        },
        "headers": {"Content-Type": "application/x-www-form-urlencoded"}
    },
    {
        "name": "Config 2: OAuth with Basic Auth header",
        "method": "POST",
        "url": token_url,
        "data": {"grant_type": "client_credentials"},
        "auth": HTTPBasicAuth(SN_CLIENT_ID, SN_CLIENT_SECRET),
        "headers": {"Content-Type": "application/x-www-form-urlencoded"}
    },
    {
        "name": "Config 3: Alternative endpoint /oauth/token",
        "method": "POST",
        "url": f"https://{SN_INSTANCE}.service-now.com/oauth/token",
        "data": {
            "grant_type": "client_credentials",
            "client_id": SN_CLIENT_ID,
            "client_secret": SN_CLIENT_SECRET
        },
        "headers": {"Content-Type": "application/x-www-form-urlencoded"}
    },
    {
        "name": "Config 4: Alternative endpoint with Basic Auth",
        "method": "POST",
        "url": f"https://{SN_INSTANCE}.service-now.com/oauth/token",
        "data": {"grant_type": "client_credentials"},
        "auth": HTTPBasicAuth(SN_CLIENT_ID, SN_CLIENT_SECRET),
        "headers": {"Content-Type": "application/x-www-form-urlencoded"}
    }
]

success = False
access_token = None

for i, config in enumerate(configurations, 1):
    print(f"Attempt {i}: {config['name']}")
    print(f"  URL: {config['url']}")

    try:
        kwargs = {
            "data": config.get("data"),
            "headers": config.get("headers"),
            "timeout": 10
        }
        if "auth" in config:
            kwargs["auth"] = config["auth"]
            print(f"  Auth: Basic Auth")
        else:
            print(f"  Auth: Form data")

        response = requests.post(config["url"], **kwargs)

        print(f"  Status: {response.status_code}")
        print(f"  Content-Type: {response.headers.get('Content-Type', 'N/A')}")

        if response.status_code == 200:
            try:
                token_data = response.json()
                if "access_token" in token_data:
                    access_token = token_data["access_token"]
                    print(f"  ✅ SUCCESS! Got access token")
                    print(f"  Token: {access_token[:20]}...{access_token[-10:]}")
                    print(f"  Token type: {token_data.get('token_type', 'N/A')}")
                    print(f"  Expires in: {token_data.get('expires_in', 'N/A')} seconds")
                    success = True
                    break
                else:
                    print(f"  ⚠ Response missing 'access_token'")
                    print(f"  Response: {token_data}")
            except ValueError as e:
                print(f"  ❌ Invalid JSON response")
                print(f"  Response text: {response.text[:200]}")
        else:
            print(f"  ❌ Failed")
            try:
                error_data = response.json()
                print(f"  Error: {error_data}")
            except:
                print(f"  Response: {response.text[:200]}")

        print()

    except requests.exceptions.RequestException as e:
        print(f"  ❌ Request failed: {e}")
        print()

if success:
    print("=" * 60)
    print("✅ OAuth Authentication Successful!")
    print("=" * 60)
    print()

    # Test API call with the token
    print("4. Testing API call with token...")
    api_url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/cmdb_ci_appl"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.get(
            api_url,
            headers=headers,
            params={"sysparm_limit": 1},
            timeout=10
        )

        print(f"  API URL: {api_url}")
        print(f"  Status: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            print(f"  ✅ API call successful!")
            print(f"  Records available: {len(data.get('result', []))}")
            print()
            print("=" * 60)
            print("🎉 ServiceNow connection fully validated!")
            print("=" * 60)
        else:
            print(f"  ❌ API call failed")
            print(f"  Response: {response.text[:200]}")

    except Exception as e:
        print(f"  ❌ API test failed: {e}")
else:
    print("=" * 60)
    print("❌ All OAuth attempts failed")
    print("=" * 60)
    print()
    print("Next steps:")
    print("1. Verify CLIENT_ID and CLIENT_SECRET are correct")
    print("2. Check OAuth application configuration in ServiceNow:")
    print("   - Go to System OAuth → Application Registry")
    print("   - Find your OAuth application")
    print("   - Verify 'Active' is checked")
    print("   - Verify 'Client Credentials' grant type is enabled")
    print("   - Check token endpoint configuration")
    print("3. Contact ServiceNow administrator")
    sys.exit(1)

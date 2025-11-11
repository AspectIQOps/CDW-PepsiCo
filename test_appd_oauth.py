#!/usr/bin/env python3
"""
Test AppDynamics OAuth 2.0 connection with credentials from AWS SSM
"""
import os
import sys
import requests
from requests.auth import HTTPBasicAuth

# Load credentials from environment (same way entrypoint.sh does)
APPD_CONTROLLER = os.getenv('APPD_CONTROLLER')
APPD_ACCOUNT = os.getenv('APPD_ACCOUNT')
APPD_CLIENT_ID = os.getenv('APPD_CLIENT_ID')
APPD_CLIENT_SECRET = os.getenv('APPD_CLIENT_SECRET')

print("=" * 60)
print("AppDynamics OAuth 2.0 Connection Test")
print("=" * 60)
print()

# Validate credentials are loaded
print("1. Checking credentials...")
if not APPD_CONTROLLER:
    print("❌ APPD_CONTROLLER not set")
    sys.exit(1)
if not APPD_ACCOUNT:
    print("❌ APPD_ACCOUNT not set")
    sys.exit(1)
if not APPD_CLIENT_ID:
    print("❌ APPD_CLIENT_ID not set")
    sys.exit(1)
if not APPD_CLIENT_SECRET:
    print("❌ APPD_CLIENT_SECRET not set")
    sys.exit(1)

print(f"✓ APPD_CONTROLLER: {APPD_CONTROLLER}")
print(f"✓ APPD_ACCOUNT: {APPD_ACCOUNT}")
print(f"✓ APPD_CLIENT_ID: {APPD_CLIENT_ID}")
print(f"✓ APPD_CLIENT_SECRET: {'*' * 20}")
print()

# Build OAuth token URL
token_url = f"https://{APPD_CONTROLLER}/controller/api/oauth/access_token"
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
            "client_id": f"{APPD_CLIENT_ID}@{APPD_ACCOUNT}",
            "client_secret": APPD_CLIENT_SECRET
        },
        "headers": {"Content-Type": "application/x-www-form-urlencoded"}
    },
    {
        "name": "Config 2: OAuth with Basic Auth header",
        "method": "POST",
        "url": token_url,
        "data": {"grant_type": "client_credentials"},
        "auth": HTTPBasicAuth(f"{APPD_CLIENT_ID}@{APPD_ACCOUNT}", APPD_CLIENT_SECRET),
        "headers": {"Content-Type": "application/x-www-form-urlencoded"}
    },
    {
        "name": "Config 3: Client ID without account suffix",
        "method": "POST",
        "url": token_url,
        "data": {
            "grant_type": "client_credentials",
            "client_id": APPD_CLIENT_ID,
            "client_secret": APPD_CLIENT_SECRET
        },
        "headers": {"Content-Type": "application/x-www-form-urlencoded"}
    },
    {
        "name": "Config 4: Basic Auth without account suffix",
        "method": "POST",
        "url": token_url,
        "data": {"grant_type": "client_credentials"},
        "auth": HTTPBasicAuth(APPD_CLIENT_ID, APPD_CLIENT_SECRET),
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
            if "client_id" in config["data"]:
                print(f"  Client ID: {config['data']['client_id']}")

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

    # Test API call with the token - Get license usage
    print("4. Testing License API call with token...")

    # AppDynamics License API endpoint
    api_url = f"https://{APPD_CONTROLLER}/controller/licensing/v1/usage/account/{APPD_ACCOUNT}"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.get(
            api_url,
            headers=headers,
            timeout=10
        )

        print(f"  API URL: {api_url}")
        print(f"  Status: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            print(f"  ✅ API call successful!")
            print(f"  Response keys: {list(data.keys())}")

            # Try to show some license data
            if isinstance(data, dict):
                if 'usages' in data:
                    print(f"  License usages found: {len(data['usages'])} items")
                elif 'modules' in data:
                    print(f"  Modules found: {len(data['modules'])} items")
                else:
                    print(f"  Data structure: {data}")

            print()
            print("=" * 60)
            print("🎉 AppDynamics connection fully validated!")
            print("=" * 60)
        else:
            print(f"  ❌ API call failed")
            try:
                error_data = response.json()
                print(f"  Error: {error_data}")
            except:
                print(f"  Response: {response.text[:200]}")

            # Try alternative API endpoint
            print()
            print("5. Trying alternative API endpoint...")
            alt_api_url = f"https://{APPD_CONTROLLER}/controller/rest/applications"
            headers = {
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json"
            }

            response = requests.get(
                alt_api_url,
                headers=headers,
                params={"output": "JSON"},
                timeout=10
            )

            print(f"  API URL: {alt_api_url}")
            print(f"  Status: {response.status_code}")

            if response.status_code == 200:
                data = response.json()
                print(f"  ✅ Applications API successful!")
                if isinstance(data, list):
                    print(f"  Applications found: {len(data)}")
                print()
                print("=" * 60)
                print("🎉 AppDynamics connection validated!")
                print("=" * 60)
            else:
                print(f"  ❌ Alternative API also failed")
                try:
                    error_data = response.json()
                    print(f"  Error: {error_data}")
                except:
                    print(f"  Response: {response.text[:200]}")

    except Exception as e:
        print(f"  ❌ API test failed: {e}")
else:
    print("=" * 60)
    print("❌ All OAuth attempts failed")
    print("=" * 60)
    print()
    print("Next steps:")
    print("1. Verify CLIENT_ID format:")
    print("   - Try: 'Client Name' (what we used)")
    print("   - Try: 'Client Name@account'")
    print("   - Try: UUID format if that's what AppD generated")
    print("2. Check OAuth client configuration in AppDynamics:")
    print("   - Go to Settings → Administration → API Clients")
    print("   - Verify client is Active")
    print("   - Verify client has necessary permissions")
    print("   - Copy the exact Client ID shown")
    print("3. Verify client secret is correct")
    print("4. Contact AppDynamics administrator")
    sys.exit(1)

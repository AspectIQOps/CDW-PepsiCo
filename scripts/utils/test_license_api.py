#!/usr/bin/env python3
"""
Quick test script to verify AppDynamics Licensing API v1 connectivity

Tests:
1. /controller/licensing/v1/usage/account/{accountId} - Account-level usage
2. /controller/licensing/v1/account/{accountId}/grouped-usage/application/by-id - Per-app usage

Usage:
    python3 scripts/utils/test_license_api.py
"""

import os
import sys
import requests
from datetime import datetime, timedelta

# OAuth token cache
_token_cache = {}

def get_oauth_token(controller, account, client_id, client_secret):
    """Get OAuth 2.0 token for AppDynamics API access"""
    cache_key = f"{controller}:{account}"

    if cache_key in _token_cache:
        return _token_cache[cache_key]

    auth_url = f"https://{controller}/controller/api/oauth/access_token"

    try:
        response = requests.post(
            auth_url,
            data={
                'grant_type': 'client_credentials',
                'client_id': f"{client_id}@{account}",
                'client_secret': client_secret
            },
            timeout=30
        )

        if response.status_code == 200:
            token_data = response.json()
            access_token = token_data.get('access_token')
            _token_cache[cache_key] = access_token
            return access_token
        else:
            print(f"❌ OAuth failed: {response.status_code}")
            return None

    except Exception as e:
        print(f"❌ OAuth error: {e}")
        return None

def test_account_level_api(controller, account, client_id, client_secret, account_id):
    """Test /v1/usage/account/{accountId} endpoint"""
    print("\n" + "="*70)
    print("TEST 1: Account-Level Usage API")
    print("="*70)

    token = get_oauth_token(controller, account, client_id, client_secret)
    if not token:
        return False

    # Test with last 7 days
    end_date = datetime.now()
    start_date = end_date - timedelta(days=7)

    date_from = start_date.strftime('%Y-%m-%dT%H:%M:%SZ')
    date_to = end_date.strftime('%Y-%m-%dT%H:%M:%SZ')

    url = f"https://{controller}/controller/licensing/v1/usage/account/{account_id}"
    params = {
        'dateFrom': date_from,
        'dateTo': date_to,
        'granularityMinutes': 1440  # Daily
    }

    print(f"\n🔍 Testing endpoint: {url}")
    print(f"   Parameters:")
    print(f"   - dateFrom: {date_from}")
    print(f"   - dateTo: {date_to}")
    print(f"   - granularityMinutes: 1440")

    try:
        response = requests.get(
            url,
            params=params,
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            },
            timeout=60
        )

        print(f"\n📡 Response Status: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            print(f"✅ SUCCESS! API returned data")
            print(f"\n📦 Response structure:")
            print(f"   - Account ID: {data.get('accountId')}")

            packages = data.get('packages', [])
            print(f"   - Packages: {len(packages)}")

            for i, pkg in enumerate(packages[:3]):  # Show first 3
                print(f"\n   Package {i+1}:")
                print(f"     - Name: {pkg.get('name')}")
                unit_usages = pkg.get('unitUsages', [])
                print(f"     - Unit Usages: {len(unit_usages)}")

                for j, usage in enumerate(unit_usages[:2]):  # Show first 2
                    print(f"       Usage {j+1}:")
                    print(f"         - Type: {usage.get('usageType')}")
                    data_points = usage.get('data', [])
                    print(f"         - Data Points: {len(data_points)}")

            return True

        elif response.status_code == 404:
            print(f"❌ FAILED: 404 Not Found")
            print(f"   The endpoint doesn't exist or account ID is wrong")
            print(f"   Response: {response.text[:500]}")
            return False

        else:
            print(f"❌ FAILED: {response.status_code}")
            print(f"   Response: {response.text[:500]}")
            return False

    except Exception as e:
        print(f"❌ ERROR: {e}")
        return False

def test_grouped_usage_api(controller, account, client_id, client_secret, account_id, app_ids):
    """Test /v1/grouped-usage/application/by-id endpoint"""
    print("\n" + "="*70)
    print("TEST 2: Grouped Usage by Application ID")
    print("="*70)

    token = get_oauth_token(controller, account, client_id, client_secret)
    if not token:
        return False

    url = f"https://{controller}/controller/licensing/v1/account/{account_id}/grouped-usage/application/by-id"

    # Test with first few app IDs
    test_app_ids = app_ids[:5] if len(app_ids) > 5 else app_ids

    print(f"\n🔍 Testing endpoint: {url}")
    print(f"   Testing with {len(test_app_ids)} application IDs: {test_app_ids}")

    try:
        # Build query params (multiple appId parameters)
        params = [('appId', app_id) for app_id in test_app_ids]

        response = requests.get(
            url,
            params=params,
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            },
            timeout=60
        )

        print(f"\n📡 Response Status: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            print(f"✅ SUCCESS! API returned per-application data")
            print(f"\n📦 Response structure:")

            if isinstance(data, list):
                print(f"   - Applications: {len(data)}")

                for i, app_data in enumerate(data[:3]):  # Show first 3
                    print(f"\n   Application {i+1}:")
                    print(f"     - App ID: {app_data.get('applicationId')}")
                    print(f"     - App Name: {app_data.get('applicationName')}")
                    print(f"     - vCPU Total: {app_data.get('vCPUTotal')}")
                    print(f"     - Hosts: {len(app_data.get('hosts', []))}")
                    print(f"     - Agents: {len(app_data.get('agents', []))}")
            else:
                print(f"   Response type: {type(data)}")
                print(f"   Keys: {list(data.keys()) if isinstance(data, dict) else 'N/A'}")

            return True

        elif response.status_code == 404:
            print(f"❌ FAILED: 404 Not Found")
            print(f"   The endpoint doesn't exist on this controller")
            print(f"   Response: {response.text[:500]}")
            return False

        else:
            print(f"❌ FAILED: {response.status_code}")
            print(f"   Response: {response.text[:500]}")
            return False

    except Exception as e:
        print(f"❌ ERROR: {e}")
        return False

def get_application_ids(controller, account, client_id, client_secret):
    """Fetch application IDs from controller"""
    print("\n" + "="*70)
    print("Fetching Application IDs from Controller")
    print("="*70)

    token = get_oauth_token(controller, account, client_id, client_secret)
    if not token:
        return []

    url = f"https://{controller}/controller/rest/applications"

    try:
        response = requests.get(
            url,
            params={'output': 'JSON'},
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            },
            timeout=30
        )

        if response.status_code == 200:
            apps = response.json()
            app_ids = [app['id'] for app in apps if isinstance(app, dict) and 'id' in app]
            print(f"✅ Found {len(app_ids)} applications")
            return app_ids
        else:
            print(f"❌ Failed to fetch applications: {response.status_code}")
            return []

    except Exception as e:
        print(f"❌ Error fetching applications: {e}")
        return []

def main():
    print("="*70)
    print("AppDynamics Licensing API v1 - Connectivity Test")
    print("="*70)

    # Get credentials from environment (from SSM)
    controllers = [c.strip() for c in os.getenv('APPD_CONTROLLERS', '').split(',') if c.strip()]
    accounts = [a.strip() for a in os.getenv('APPD_ACCOUNTS', '').split(',') if a.strip()]
    client_ids = [c.strip() for c in os.getenv('APPD_CLIENT_IDS', '').split(',') if c.strip()]
    client_secrets = [s.strip() for s in os.getenv('APPD_CLIENT_SECRETS', '').split(',') if s.strip()]
    account_ids = [a.strip() for a in os.getenv('APPD_ACCOUNT_IDS', '').split(',') if a.strip()]

    if not controllers or not accounts or not client_ids or not client_secrets:
        print("\n❌ Missing environment variables!")
        print("   Required: APPD_CONTROLLERS, APPD_ACCOUNTS, APPD_CLIENT_IDS, APPD_CLIENT_SECRETS")
        print("\n   Run: ./scripts/utils/discover_with_ssm.sh first")
        sys.exit(1)

    if not account_ids:
        print("\n❌ APPD_ACCOUNT_IDS not set!")
        print("   Run: ./scripts/utils/discover_with_ssm.sh --save-to-ssm")
        sys.exit(1)

    # Test first controller only
    controller = controllers[0]
    account = accounts[0]
    client_id = client_ids[0]
    client_secret = client_secrets[0]
    account_id = account_ids[0]

    print(f"\n🎯 Testing Controller: {controller}")
    print(f"   Account: {account}")
    print(f"   Account ID: {account_id}")

    # Test 1: Account-level usage API
    test1_passed = test_account_level_api(controller, account, client_id, client_secret, account_id)

    # Test 2: Get application IDs first
    app_ids = get_application_ids(controller, account, client_id, client_secret)

    # Test 3: Grouped usage API (if we have app IDs)
    test2_passed = False
    if app_ids:
        test2_passed = test_grouped_usage_api(controller, account, client_id, client_secret, account_id, app_ids)
    else:
        print("\n⚠️  Skipping Test 2: No application IDs available")

    # Summary
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)
    print(f"Test 1 - Account-Level Usage API: {'✅ PASSED' if test1_passed else '❌ FAILED'}")
    print(f"Test 2 - Grouped Usage API:       {'✅ PASSED' if test2_passed else '❌ FAILED' if app_ids else '⚠️  SKIPPED'}")

    if test1_passed:
        print("\n✅ Licensing API v1 is accessible!")
        print("   Next step: Implement grouped-usage API for per-application data")
    else:
        print("\n❌ Licensing API v1 connectivity failed")
        print("   Check endpoint availability with AppDynamics support")

    sys.exit(0 if test1_passed else 1)

if __name__ == '__main__':
    main()

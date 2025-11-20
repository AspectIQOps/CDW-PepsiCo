#!/usr/bin/env python3
"""
AppDynamics Account ID Discovery Utility

This standalone script discovers AppDynamics Account IDs via API and optionally
saves them to AWS SSM Parameter Store for use by the ETL pipeline.

Usage:
    # Discover only (prints to console):
    python3 discover_appd_account_ids.py

    # Discover and save to SSM:
    python3 discover_appd_account_ids.py --save-to-ssm

    # Use custom SSM parameter name:
    python3 discover_appd_account_ids.py --save-to-ssm --param-name /custom/path

Environment Variables Required:
    APPD_CONTROLLERS    - Comma-separated controller URLs
    APPD_ACCOUNTS       - Comma-separated account names
    APPD_CLIENT_IDS     - Comma-separated OAuth client IDs
    APPD_CLIENT_SECRETS - Comma-separated OAuth client secrets
    AWS_REGION          - AWS region for SSM (default: us-east-1)
"""

import os
import sys
import requests
import argparse

# boto3 is optional - only needed for --save-to-ssm
try:
    import boto3
    from botocore.exceptions import ClientError
    BOTO3_AVAILABLE = True
except ImportError:
    BOTO3_AVAILABLE = False

# OAuth token cache
_token_cache = {}

def get_oauth_token(controller, account, client_id, client_secret):
    """
    Get OAuth 2.0 token for AppDynamics API access
    Caches token to avoid redundant auth calls
    """
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
            print(f"❌ OAuth failed for {controller}: {response.status_code}")
            return None

    except Exception as e:
        print(f"❌ OAuth error for {controller}: {e}")
        return None

def discover_account_id(controller, account, client_id, client_secret):
    """
    Discover numeric Account ID from AppDynamics API

    Calls: GET /controller/api/accounts/myaccount
    Returns: str - numeric account ID (e.g., "12345")
    """
    print(f"\n🔍 Discovering Account ID for {controller}...")
    print(f"   Account Name: {account}")

    # Get OAuth token
    token = get_oauth_token(controller, account, client_id, client_secret)
    if not token:
        print(f"   ❌ Failed to get OAuth token")
        return None

    # Call account info API
    api_url = f"https://{controller}/controller/api/accounts/myaccount"

    try:
        response = requests.get(
            api_url,
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            },
            timeout=30
        )

        if response.status_code == 200:
            account_data = response.json()
            account_id = str(account_data.get('id', ''))

            if account_id:
                print(f"   ✅ Account ID: {account_id}")
                print(f"   Name: {account_data.get('name', 'N/A')}")
                print(f"   Global Account: {account_data.get('globalAccountName', 'N/A')}")
                return account_id
            else:
                print(f"   ❌ No account ID in response")
                return None
        else:
            print(f"   ❌ API call failed: {response.status_code}")
            print(f"   Response: {response.text[:200]}")
            return None

    except Exception as e:
        print(f"   ❌ Error: {e}")
        return None

def save_to_ssm(account_ids, param_name, aws_region):
    """
    Save discovered account IDs to AWS SSM Parameter Store

    Args:
        account_ids: List of account IDs in controller order
        param_name: SSM parameter name (e.g., /pepsico/appdynamics/ACCOUNT_ID)
        aws_region: AWS region
    """
    if not BOTO3_AVAILABLE:
        print(f"\n❌ boto3 not installed - cannot save to SSM")
        print(f"   Install: pip install boto3")
        print(f"   Or run in Docker/venv where boto3 is available")
        return False

    print(f"\n💾 Saving to AWS SSM Parameter Store...")
    print(f"   Parameter: {param_name}")
    print(f"   Region: {aws_region}")

    # Join list into comma-separated string
    account_ids_value = ','.join(str(id) for id in account_ids if id)
    print(f"   Value: {account_ids_value}")

    try:
        ssm = boto3.client('ssm', region_name=aws_region)

        ssm.put_parameter(
            Name=param_name,
            Value=account_ids_value,
            Type='String',
            Overwrite=True,
            Description='AppDynamics Account IDs (comma-separated, matches CONTROLLERS order)'
        )

        print(f"   ✅ Successfully saved to SSM!")
        return True

    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'AccessDeniedException':
            print(f"   ❌ Permission denied!")
            print(f"   Required IAM permission: ssm:PutParameter")
            print(f"   Resource: {param_name}")
        else:
            print(f"   ❌ AWS error: {e}")
        return False

    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description='Discover AppDynamics Account IDs via API',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        '--save-to-ssm',
        action='store_true',
        help='Save discovered Account IDs to AWS SSM Parameter Store'
    )
    parser.add_argument(
        '--param-name',
        default='/pepsico/appdynamics/ACCOUNT_ID',
        help='SSM parameter name (default: /pepsico/appdynamics/ACCOUNT_ID)'
    )
    parser.add_argument(
        '--aws-region',
        default=os.getenv('AWS_REGION', 'us-east-1'),
        help='AWS region for SSM (default: from AWS_REGION env var or us-east-1)'
    )

    args = parser.parse_args()

    print("=" * 70)
    print("AppDynamics Account ID Discovery")
    print("=" * 70)

    # Parse environment variables
    controllers = [c.strip() for c in os.getenv('APPD_CONTROLLERS', '').split(',') if c.strip()]
    accounts = [a.strip() for a in os.getenv('APPD_ACCOUNTS', '').split(',') if a.strip()]
    client_ids = [c.strip() for c in os.getenv('APPD_CLIENT_IDS', '').split(',') if c.strip()]
    client_secrets = [s.strip() for s in os.getenv('APPD_CLIENT_SECRETS', '').split(',') if s.strip()]

    # Validate configuration
    if not controllers:
        print("\n❌ Error: APPD_CONTROLLERS environment variable not set")
        print("   Set: export APPD_CONTROLLERS='controller1.appdynamics.com,controller2.appdynamics.com'")
        sys.exit(1)

    if len(controllers) != len(accounts) or len(controllers) != len(client_ids) or len(controllers) != len(client_secrets):
        print("\n❌ Error: Mismatched controller configuration counts!")
        print(f"   Controllers: {len(controllers)}")
        print(f"   Accounts: {len(accounts)}")
        print(f"   Client IDs: {len(client_ids)}")
        print(f"   Client Secrets: {len(client_secrets)}")
        sys.exit(1)

    print(f"\n📋 Configured Controllers: {len(controllers)}")
    for i, controller in enumerate(controllers):
        print(f"   {i+1}. {controller} (account: {accounts[i]})")

    # Discover account IDs
    discovered_ids = []
    for i, controller in enumerate(controllers):
        account = accounts[i]
        client_id = client_ids[i]
        client_secret = client_secrets[i]

        account_id = discover_account_id(controller, account, client_id, client_secret)
        discovered_ids.append(account_id)

    # Summary
    print("\n" + "=" * 70)
    print("Discovery Results")
    print("=" * 70)

    success_count = sum(1 for id in discovered_ids if id)

    for i, (controller, account_id) in enumerate(zip(controllers, discovered_ids)):
        status = "✅" if account_id else "❌"
        id_str = account_id if account_id else "FAILED"
        print(f"{status} Controller {i+1}: {controller} → Account ID: {id_str}")

    print(f"\n✅ Successfully discovered: {success_count}/{len(controllers)}")

    if success_count == 0:
        print("\n❌ No account IDs discovered. Check your credentials and network connectivity.")
        sys.exit(1)

    # Generate comma-separated output
    ids_csv = ','.join(discovered_ids)
    print(f"\n📋 Comma-separated format (for APPD_ACCOUNT_IDS):")
    print(f"   {ids_csv}")

    # Save to SSM if requested
    if args.save_to_ssm:
        if save_to_ssm(discovered_ids, args.param_name, args.aws_region):
            print("\n✅ Complete! Account IDs saved to SSM Parameter Store.")
            print(f"\nNext step: ETL pipeline will automatically use these values from SSM.")
        else:
            print("\n⚠️  Discovery succeeded but SSM save failed.")
            print(f"   You can manually create the parameter:")
            print(f"   aws ssm put-parameter \\")
            print(f"     --name '{args.param_name}' \\")
            print(f"     --value '{ids_csv}' \\")
            print(f"     --type String \\")
            print(f"     --region {args.aws_region}")
            sys.exit(1)
    else:
        print(f"\n💡 To save to AWS SSM Parameter Store, run:")
        print(f"   python3 {sys.argv[0]} --save-to-ssm")
        print(f"\n💡 Or manually create the parameter:")
        print(f"   aws ssm put-parameter \\")
        print(f"     --name '{args.param_name}' \\")
        print(f"     --value '{ids_csv}' \\")
        print(f"     --type String \\")
        print(f"     --region {args.aws_region}")

if __name__ == '__main__':
    main()

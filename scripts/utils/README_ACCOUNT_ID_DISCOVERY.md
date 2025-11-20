# AppDynamics Account ID Discovery Utility

## Purpose

This standalone script discovers AppDynamics Account IDs via API and saves them to AWS SSM Parameter Store for use by the ETL pipeline.

**Why is this needed?**
- AppDynamics Licensing API requires a numeric Account ID (not just the account name)
- Account IDs rarely change (stable configuration)
- Better to discover once and persist, rather than discovering on every ETL run

---

## Quick Start

### 1. Set Environment Variables

```bash
export APPD_CONTROLLERS="controller1.appdynamics.com,controller2.appdynamics.com"
export APPD_ACCOUNTS="customer1,customer2"
export APPD_CLIENT_IDS="client_id_1,client_id_2"
export APPD_CLIENT_SECRETS="secret_1,secret_2"
export AWS_REGION="us-east-2"
```

### 2. Discover Only (No SSM Write)

```bash
python3 scripts/utils/discover_appd_account_ids.py
```

**Output:**
```
======================================================================
AppDynamics Account ID Discovery
======================================================================

📋 Configured Controllers: 2
   1. controller1.appdynamics.com (account: customer1)
   2. controller2.appdynamics.com (account: customer2)

🔍 Discovering Account ID for controller1.appdynamics.com...
   Account Name: customer1
   ✅ Account ID: 12345
   Name: customer1
   Global Account: PepsiCo Global

🔍 Discovering Account ID for controller2.appdynamics.com...
   Account Name: customer2
   ✅ Account ID: 67890
   Name: customer2
   Global Account: PepsiCo Global

======================================================================
Discovery Results
======================================================================
✅ Controller 1: controller1.appdynamics.com → Account ID: 12345
✅ Controller 2: controller2.appdynamics.com → Account ID: 67890

✅ Successfully discovered: 2/2

📋 Comma-separated format (for APPD_ACCOUNT_IDS):
   12345,67890

💡 To save to AWS SSM Parameter Store, run:
   python3 scripts/utils/discover_appd_account_ids.py --save-to-ssm
```

### 3. Discover and Save to SSM

```bash
python3 scripts/utils/discover_appd_account_ids.py --save-to-ssm
```

**Output:**
```
... (discovery output) ...

💾 Saving to AWS SSM Parameter Store...
   Parameter: /pepsico/appdynamics/ACCOUNT_ID
   Region: us-east-2
   Value: 12345,67890
   ✅ Successfully saved to SSM!

✅ Complete! Account IDs saved to SSM Parameter Store.

Next step: ETL pipeline will automatically use these values from SSM.
```

---

## Command-Line Options

```bash
python3 discover_appd_account_ids.py [OPTIONS]

Options:
  --save-to-ssm              Save discovered IDs to AWS SSM Parameter Store
  --param-name NAME          SSM parameter name (default: /pepsico/appdynamics/ACCOUNT_ID)
  --aws-region REGION        AWS region (default: from AWS_REGION env var or us-east-1)
  -h, --help                 Show help message
```

---

## Examples

### Discover for Single Controller

```bash
export APPD_CONTROLLERS="mycontroller.appdynamics.com"
export APPD_ACCOUNTS="myaccount"
export APPD_CLIENT_IDS="my_client_id"
export APPD_CLIENT_SECRETS="my_secret"

python3 scripts/utils/discover_appd_account_ids.py
```

### Discover and Save with Custom Parameter Name

```bash
python3 scripts/utils/discover_appd_account_ids.py \
  --save-to-ssm \
  --param-name /custom/path/ACCOUNT_ID \
  --aws-region us-west-2
```

### Manual SSM Update (Alternative to --save-to-ssm)

If the script doesn't have SSM write permissions, you can copy the output and run:

```bash
aws ssm put-parameter \
  --name '/pepsico/appdynamics/ACCOUNT_ID' \
  --value '12345,67890' \
  --type String \
  --region us-east-2
```

---

## IAM Permissions Required

### For Discovery Only

No special permissions needed - uses same OAuth credentials as ETL pipeline.

### For SSM Write (--save-to-ssm)

```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:PutParameter"
  ],
  "Resource": [
    "arn:aws:ssm:us-east-2:*:parameter/pepsico/appdynamics/ACCOUNT_ID"
  ]
}
```

---

## How It Works

1. **Reads Environment Variables:**
   - `APPD_CONTROLLERS`, `APPD_ACCOUNTS`, `APPD_CLIENT_IDS`, `APPD_CLIENT_SECRETS`

2. **For Each Controller:**
   - Authenticates via OAuth 2.0 (`POST /controller/api/oauth/access_token`)
   - Calls Account Info API (`GET /controller/api/accounts/myaccount`)
   - Extracts numeric `id` field from response

3. **Generates Output:**
   - Comma-separated list matching controller order
   - Example: `"12345,67890"` for 2 controllers

4. **Optionally Saves to SSM:**
   - Parameter: `/pepsico/appdynamics/ACCOUNT_ID`
   - Type: `String`
   - Format: Comma-separated, matches `APPD_CONTROLLERS` order

---

## Integration with ETL Pipeline

### Without Account IDs in SSM

ETL will auto-discover on every run (slower):
```
ℹ️  APPD_ACCOUNT_ID not provided, attempting auto-discovery...
✅ Auto-discovered Account ID: 12345
```

### With Account IDs in SSM

ETL reads from SSM (faster):
```
✅ AppDynamics credentials retrieved
  Controller: controller1.appdynamics.com
  Account: customer1
  Account ID: 12345 (from SSM)
```

---

## Troubleshooting

### Error: "APPD_CONTROLLERS environment variable not set"

**Solution:** Set required environment variables:
```bash
export APPD_CONTROLLERS="your-controller.appdynamics.com"
export APPD_ACCOUNTS="your-account"
export APPD_CLIENT_IDS="your-client-id"
export APPD_CLIENT_SECRETS="your-secret"
```

### Error: "OAuth failed for controller"

**Possible Causes:**
- Incorrect client ID/secret
- Client ID not in format: `client_id@account`
- Network connectivity issues

**Solution:** Verify credentials in AppDynamics UI

### Error: "Permission denied" (SSM write)

**Solution:** Either:
1. Grant IAM permission: `ssm:PutParameter`
2. Or manually create parameter using AWS CLI (see output)

---

## Best Practices

1. **Run Once During Deployment:**
   - Account IDs rarely change
   - Run during initial setup or when adding new controllers

2. **Verify Output:**
   - Check that discovered IDs match controllers
   - Verify order is correct (same as `APPD_CONTROLLERS`)

3. **Store Securely:**
   - SSM Parameter Store is secure and encrypted
   - Better than hardcoding in scripts

4. **Re-run When:**
   - Adding new AppDynamics controllers
   - Changing account configurations
   - Account IDs change (rare)

---

## See Also

- [DEPLOYMENT_GUIDE.md](../../docs/DEPLOYMENT_GUIDE.md) - Full deployment instructions
- [appd_extract.py](../etl/appd_extract.py) - Main ETL script that uses account IDs
- [entrypoint.sh](../../docker/etl/entrypoint.sh) - Docker entrypoint that reads from SSM

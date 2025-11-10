# Credential Setup Guide

## Overview

This guide documents the credentials required for the ETL pipeline and how to configure them in AWS SSM Parameter Store.

## Credentials Required

### 1. Database Credentials (REQUIRED)

All database credentials must be present in SSM for the pipeline to run.

```bash
# RDS PostgreSQL Connection
aws ssm put-parameter \
  --name '/pepsico/DB_HOST' \
  --value 'your-rds-endpoint.us-east-2.rds.amazonaws.com' \
  --type String \
  --region us-east-2 \
  --overwrite

aws ssm put-parameter \
  --name '/pepsico/DB_NAME' \
  --value 'cost_analytics_db' \
  --type String \
  --region us-east-2 \
  --overwrite

aws ssm put-parameter \
  --name '/pepsico/DB_USER' \
  --value 'etl_analytics' \
  --type String \
  --region us-east-2 \
  --overwrite

aws ssm put-parameter \
  --name '/pepsico/DB_PASSWORD' \
  --value 'YOUR_DB_PASSWORD' \
  --type SecureString \
  --region us-east-2 \
  --overwrite
```

### 2. ServiceNow Credentials (REQUIRED for CMDB data)

**Option A: OAuth 2.0 (Preferred)**

```bash
aws ssm put-parameter \
  --name '/pepsico/servicenow/INSTANCE' \
  --value 'yourinstance' \
  --type String \
  --region us-east-2 \
  --overwrite

aws ssm put-parameter \
  --name '/pepsico/servicenow/CLIENT_ID' \
  --value 'YOUR_CLIENT_ID' \
  --type String \
  --region us-east-2 \
  --overwrite

aws ssm put-parameter \
  --name '/pepsico/servicenow/CLIENT_SECRET' \
  --value 'YOUR_CLIENT_SECRET' \
  --type SecureString \
  --region us-east-2 \
  --overwrite
```

**Option B: Basic Auth (Legacy)**

```bash
aws ssm put-parameter \
  --name '/pepsico/servicenow/INSTANCE' \
  --value 'yourinstance' \
  --type String \
  --region us-east-2 \
  --overwrite

aws ssm put-parameter \
  --name '/pepsico/servicenow/USER' \
  --value 'YOUR_USERNAME' \
  --type String \
  --region us-east-2 \
  --overwrite

aws ssm put-parameter \
  --name '/pepsico/servicenow/PASS' \
  --value 'YOUR_PASSWORD' \
  --type SecureString \
  --region us-east-2 \
  --overwrite
```

### 3. AppDynamics Credentials (REQUIRED for real license data)

**Status:** Currently using mock data. Real API integration ready when credentials are provided.

```bash
# Controller URL (without https:// or trailing /)
aws ssm put-parameter \
  --name '/pepsico/appdynamics/CONTROLLER' \
  --value 'pepsi-test.saas.appdynamics.com' \
  --type String \
  --region us-east-2 \
  --overwrite

# Account name (usually same as first part of controller URL)
aws ssm put-parameter \
  --name '/pepsico/appdynamics/ACCOUNT' \
  --value 'pepsi-test' \
  --type String \
  --region us-east-2 \
  --overwrite

# Client ID (PENDING - waiting for client to provide)
aws ssm put-parameter \
  --name '/pepsico/appdynamics/CLIENT_ID' \
  --value 'YOUR_CLIENT_ID' \
  --type String \
  --region us-east-2 \
  --overwrite

# Client Secret
aws ssm put-parameter \
  --name '/pepsico/appdynamics/CLIENT_SECRET' \
  --value 'YOUR_CLIENT_SECRET' \
  --type SecureString \
  --region us-east-2 \
  --overwrite
```

## Current Status

### ✅ Completed
- [x] All ETL scripts updated to use environment variables (no hardcoded defaults)
- [x] entrypoint.sh fetches all credentials from SSM
- [x] run_pipeline.py validates credentials before execution
- [x] OAuth 2.0 support implemented for both ServiceNow and AppDynamics
- [x] Fallback to Basic Auth for ServiceNow

### 🔄 Pending Client Response

**ServiceNow:**
- Need client to verify OAuth application is properly configured
- OR provide username/password for Basic Auth
- Current status: OAuth failing with authentication errors

**AppDynamics:**
- Need CLIENT_ID for the "License Dashboard Client Key" API client
- Have: Controller URL, Account Name, Client Secret
- Missing: CLIENT_ID value

## How Credentials Are Loaded

1. **Docker Entrypoint** (`docker/etl/entrypoint.sh`):
   - Fetches all credentials from AWS SSM Parameter Store at `/pepsico/*`
   - Exports them as environment variables
   - Validates database connection
   - Shows which authentication methods are available

2. **ETL Scripts**:
   - Read credentials from environment variables using `os.getenv()`
   - No default values - will fail fast if credentials missing
   - Example:
     ```python
     DB_HOST = os.getenv('DB_HOST')  # No default!
     ```

3. **Pipeline Validation** (`run_pipeline.py`):
   - Pre-flight check ensures all required credentials present
   - Warns about optional credentials
   - Aborts if critical credentials missing

## Testing Credentials

### Test Database Connection
```bash
# After entrypoint.sh loads credentials
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1;"
```

### Test ServiceNow OAuth
```bash
curl -X POST "https://${SN_INSTANCE}.service-now.com/oauth_token.do" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${SN_CLIENT_ID}&client_secret=${SN_CLIENT_SECRET}"
```

### Test AppDynamics OAuth
```bash
curl -X POST "https://${APPD_CONTROLLER}/controller/api/oauth/access_token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${APPD_CLIENT_ID}@${APPD_ACCOUNT}&client_secret=${APPD_CLIENT_SECRET}"
```

## Troubleshooting

### "Missing required credentials" Error
- Check that SSM parameters exist: `aws ssm get-parameter --name '/pepsico/DB_HOST' --region us-east-2`
- Verify EC2 instance IAM role has `ssm:GetParameter` permission
- Check entrypoint.sh successfully loaded variables: `echo $DB_HOST`

### ServiceNow OAuth Fails
- Verify OAuth application is active in ServiceNow
- Check client_id and client_secret are correct
- Try Basic Auth as fallback
- Contact ServiceNow admin to verify OAuth configuration

### AppDynamics API Fails
- Verify controller URL is correct (no https:// prefix)
- Ensure CLIENT_ID is the actual ID, not the display name
- Check client secret hasn't expired
- Confirm API client has appropriate permissions

## Client Action Items

### Immediate (Blocking Pipeline)
1. **ServiceNow:**
   - [ ] Verify OAuth application configuration in ServiceNow admin
   - [ ] OR provide username/password for Basic Auth fallback
   - [ ] Test credentials with provided curl commands

2. **AppDynamics:**
   - [ ] Provide CLIENT_ID from "License Dashboard Client Key" API client
   - [ ] Found in: AppDynamics → Settings → API Clients → "License Dashboard Client Key"

### Before Production
1. Ensure H-code field populated in ServiceNow CMDB (>90% coverage)
2. Verify all applications have owners assigned
3. Populate architectural classification (Monolith/Microservices)
4. Provide Peak vs. Pro differentiation strategy

## References

- SoW Section 3: Prerequisites (PepsiCo Responsibilities)
- SoW Section 2.4: Data Integration & Enrichment
- Technical Architecture: `docs/technical_architecture.md`
- Operations Runbook: `docs/operations_runbook.md`

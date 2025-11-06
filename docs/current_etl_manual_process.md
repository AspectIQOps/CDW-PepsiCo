# Current ETL Manual Execution Process

## Prerequisites

- Python 3.11+
- Virtual environment set up
- AWS credentials configured
- RDS connection details

## Manual Execution Steps

### 1. Activate Virtual Environment

```bash
# Create venv (if not exists)
python3 -m venv venv

# Activate
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
2. Set Environment Variables
# Database connection
export DB_HOST="your-rds-endpoint.us-east-1.rds.amazonaws.com"
export DB_PORT="5432"
export DB_NAME="appd_licensing"
export DB_USER="etl_analytics"
export DB_PASSWORD="your-password"

# AppDynamics credentials
export APPD_CONTROLLER_URL="https://your-controller.saas.appdynamics.com"
export APPD_CLIENT_ID="your-client-id"
export APPD_CLIENT_SECRET="your-client-secret"

# ServiceNow credentials
export SNOW_INSTANCE="your-instance.service-now.com"
export SNOW_USERNAME="your-username"
export SNOW_PASSWORD="your-password"

# AWS SSM (if using)
export SSM_PATH="/pepsico"
3. Run ETL Scripts
# Run AppDynamics ETL
python scripts/etl/appd_etl.py

# Run ServiceNow ETL
python scripts/etl/snow_etl.py

# Run reconciliation
python scripts/etl/reconciliation_engine.py

# Run forecasting
python scripts/etl/advanced_forecasting.py

# Run allocation
python scripts/etl/allocation_engine.py
4. Verify Data
# Connect to RDS and verify
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM license_usage_fact;"

Issues with Current Process
Manual environment variables - Error-prone, not reproducible
No scheduling - Must remember to run daily
No error handling - If one script fails, rest don't run
No logging - Hard to troubleshoot issues
Not using Docker - Defeats purpose of containerization

What Phase 3 Will Fix
✅ Automated daily runs via EventBridge
✅ Secrets pulled from SSM automatically
✅ Containerized execution in ECS Fargate
✅ Centralized logging in CloudWatch
✅ Error notifications via SNS
✅ Automatic retries on failure

#!/bin/sh
# Use /bin/sh for lightweight execution inside the slim image

# Exit immediately if any command fails (ensures security check is reliable)
set -e

# --- Check Configuration ---
# DB_HOST and SSM_PATH are passed from docker-compose.yaml
if [ -z "$DB_HOST" ] || [ -z "$SSM_PATH" ]; then
    echo "ERROR: DB_HOST or SSM_PATH environment variable is not set. Cannot proceed."
    exit 1
fi

# =========================================================================
# 💡 LOCAL VS. CLOUD ENVIRONMENT CHECK
# If DB_PASSWORD is set locally (via the .env file), we assume local development
# and skip the slow/failing SSM fetch to use the local variables directly.
# If DB_PASSWORD is not set, we assume production and rely entirely on SSM.
# =========================================================================

if [ -z "$DB_PASSWORD" ]; then
    echo "Starting ETL job setup. DB_PASSWORD not found locally. Fetching production secrets from AWS SSM path: ${SSM_PATH}"
    
    # --- Fetch Secrets from AWS SSM and Export as Environment Variables ---
    # The names on the left are the internal ENV vars for Python.
    # The names on the right are your specific SSM parameter suffixes.
    
    # We use 2>/dev/null to suppress expected "parameter not found" errors when testing on dev systems 
    # where the full parameter set may not exist, and we rely on the final check below.
    
    # Database Secrets
    export DB_NAME=$(aws ssm get-parameter --name "${SSM_PATH}/DB_NAME" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export DB_USER=$(aws ssm get-parameter --name "${SSM_PATH}/DB_USER" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export DB_PASSWORD=$(aws ssm get-parameter --name "${SSM_PATH}/DB_PASSWORD" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")

    # AppDynamics Secrets
    export APPD_CONTROLLER=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CONTROLLER" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export APPD_ACCOUNT=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_ACCOUNT" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export APPD_CLIENT_ID=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CLIENT_ID" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export APPD_CLIENT_SECRET=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CLIENT_SECRET" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")

    # ServiceNow Secrets
    export SN_INSTANCE=$(aws ssm get-parameter --name "${SSM_PATH}/SN_INSTANCE" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export SN_USER=$(aws ssm get-parameter --name "${SSM_PATH}/SN_USER" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    export SN_PASS=$(aws ssm get-parameter --name "${SSM_PATH}/SN_PASS" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    
    # After SSM fetch, perform a final check to ensure we got all necessary variables
    if [ -z "$DB_PASSWORD" ] || [ -z "$APPD_CLIENT_SECRET" ]; then
        echo "ERROR: Failed to fetch critical secrets (DB or APPD) from SSM. Ensure parameters exist at ${SSM_PATH} and the IAM role is correct."
        exit 1
    fi
    echo "Secrets fetched successfully."

else
    echo "Local DB_PASSWORD detected. Skipping AWS SSM fetch and using local environment variables for testing."
    echo "SSM path is available if needed: ${SSM_PATH}"
fi


# --- Wait for Postgres to be ready ---
# NOTE: Using DB_USER here is safer since it's now guaranteed to be set either locally or from SSM.
DB_USER_FOR_READY=${DB_USER:-devuser}
echo "Waiting for database at ${DB_HOST}..."

# Use the pg_isready utility (installed in Dockerfile)
until pg_isready -h "$DB_HOST" -p 5432 -U "$DB_USER_FOR_READY"; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 2
done
>&2 echo "Postgres is up and accessible. Executing ETL script."

# --- Execute the main command (The Python Script) ---
exec "$@"

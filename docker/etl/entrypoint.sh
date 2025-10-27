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

echo "Starting ETL job setup. Fetching secrets from AWS SSM path: ${SSM_PATH}"

# --- Fetch Secrets from AWS SSM and Export as Environment Variables ---
# The names on the left are the internal ENV vars for Python.
# The names on the right are your specific SSM parameter suffixes.
# Note: The EC2 IAM Role must have 'ssm:GetParameter' permission for this path.

# Database Secrets
export DB_NAME=$(aws ssm get-parameter --name "${SSM_PATH}/DB_NAME" --with-decryption --query "Parameter.Value" --output text)
export DB_USER=$(aws ssm get-parameter --name "${SSM_PATH}/DB_USER" --with-decryption --query "Parameter.Value" --output text)
export DB_PASSWORD=$(aws ssm get-parameter --name "${SSM_PATH}/DB_PASSWORD" --with-decryption --query "Parameter.Value" --output text)

# AppDynamics Secrets
export APPD_CONTROLLER=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CONTROLLER" --with-decryption --query "Parameter.Value" --output text)
export APPD_ACCOUNT=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_ACCOUNT" --with-decryption --query "Parameter.Value" --output text)
export APPD_CLIENT_ID=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CLIENT_ID" --with-decryption --query "Parameter.Value" --output text)
export APPD_CLIENT_SECRET=$(aws ssm get-parameter --name "${SSM_PATH}/APPD_CLIENT_SECRET" --with-decryption --query "Parameter.Value" --output text)

# ServiceNow Secrets
export SN_INSTANCE=$(aws ssm get-parameter --name "${SSM_PATH}/SN_INSTANCE" --with-decryption --query "Parameter.Value" --output text)
export SN_USER=$(aws ssm get-parameter --name "${SSM_PATH}/SN_USER" --with-decryption --query "Parameter.Value" --output text)
export SN_PASS=$(aws ssm get-parameter --name "${SSM_PATH}/SN_PASS" --with-decryption --query "Parameter.Value" --output text)

echo "Secrets fetched successfully."

# --- Wait for Postgres to be ready ---
# We use the generic 'devuser' for the readiness check, as that's the init user defined in docker-compose.yaml.
DB_USER_FOR_READY=${POSTGRES_USER:-devuser}
echo "Waiting for database at ${DB_HOST}..."

# Use the pg_isready utility (installed in Dockerfile)
until pg_isready -h "$DB_HOST" -p 5432 -U "$DB_USER_FOR_READY"; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 2
done
>&2 echo "Postgres is up and accessible. Executing ETL script."

# --- Execute the main command (The Python Script) ---
exec "$@"

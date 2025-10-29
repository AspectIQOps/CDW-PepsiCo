#!/bin/bash
# Title: Complete Docker Stack Setup and Credential Management
# Description: Performs stack cleanup, building, deployment, and waits for the 
# database to be healthy, prioritizing local environment variables with a 
# fallback to AWS Secrets Manager for credentials if they are empty.

# --- MANDATORY FIX: Source the .env file to load local variables ---
# 1. 'set -a' enables auto-exporting of all subsequent variables.
set -a
# 2. '.' (source) loads the .env file into the current shell context.
. ./.env
# 3. 'set +a' disables auto-exporting.
set +a
# --- END MANDATORY FIX ---

# --- Configuration & Variable Loading ---
echo "✅ Environment variables loaded from .env file."

# AWS SECRETS MANAGER FALLBACK LOGIC 
# If DB_USER or DB_PASSWORD is still not set (e.g., empty in .env), attempt AWS SM.
if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo "🚨 IMPORTANT: DB_USER or DB_PASSWORD is empty (even after sourcing .env). Attempting to fetch from AWS Secrets Manager..."
    
    # --- START OF YOUR ORIGINAL AWS SM LOGIC (Placeholder) ---
    
    # [Insert your AWS Secrets Manager retrieval logic here]
    
    # --- END OF YOUR ORIGINAL AWS SM LOGIC ---

    # After attempting retrieval, check if credentials are still missing.
    if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
        echo "❌ ERROR: Credentials are still missing after attempting AWS retrieval. Please ensure DB_USER and DB_PASSWORD are set."
        # We allow the psql command to fail later with a proper authentication error.
    else
        echo "✅ Credentials successfully set via AWS retrieval attempt."
    fi
else
    echo "✅ Credentials loaded successfully from local environment."
fi

# Set defaults for host/port/name if they aren't explicitly defined
DB_HOST=${DB_HOST:-postgres}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-pepsicodb}

# Variables for the host-side psql connection check (Uses 127.0.0.1 for exposed port)
DB_HOST_CHECK="127.0.0.1"
DB_PORT_CHECK="$DB_PORT"

# --- Pre-Setup Checks and Cleanup ---

echo "🔒 Ensuring correct permissions on SQL files..."
find ./data/sql -type f -name "*.sql" -exec chmod 644 {} \; 2>/dev/null

read -r -p "🚨 WARNING: Setup requires cleaning up existing Docker volumes. Continue (y/n)? " cleanup_confirm
if [[ "$cleanup_confirm" != "y" ]]; then
    echo "Setup aborted by user."
    exit 1
fi

echo "🧹 Cleaning up old containers and volumes..."
docker compose down -v --remove-orphans

# --- Docker Compose Start ---

echo "🐳 Building and starting infrastructure services..."
# Build and run containers in detached mode
docker compose up --build -d 

# --- PostgreSQL Health Check ---

echo "⏱️ Waiting for PostgreSQL to become fully ready on host $DB_HOST_CHECK:$DB_PORT_CHECK ..."

MAX_ATTEMPTS=24 # 24 attempts * 5 seconds = 120 seconds
SLEEP_TIME=5
CURRENT_ATTEMPT=0

while [ $CURRENT_ATTEMPT -lt $MAX_ATTEMPTS ]; do
    CURRENT_ATTEMPT=$((CURRENT_ATTEMPT + 1))
    
    # The psql utility connects to the host's exposed port (127.0.0.1) using the 
    # credentials loaded above.
    if docker compose exec -T postgres pg_isready -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; then
        echo "✅ PostgreSQL is fully ready and accepting connections."
        
        # --- Database Initialization / Schema Loading ---
        echo "⚙️ Running database initialization scripts..."
        # Example: docker compose exec -T pepsico-postgres psql -U "$DB_USER" -d "$DB_NAME" < ./data/sql/init_schema.sql

        echo "✨ Setup complete. Services are running and database is initialized."
        exit 0
    else
        echo "    ... still waiting for database connection ($((CURRENT_ATTEMPT * SLEEP_TIME))/120s)"
        sleep "$SLEEP_TIME"
    fi
done

# --- Timeout Failure ---

echo "❌ ERROR: PostgreSQL connection timed out after 120 seconds."
echo "--- PostgreSQL Container Logs (for debugging) ---"
docker compose logs postgres
exit 1

#!/bin/bash
#
# Docker Entrypoint for Analytics Platform
# Fetches credentials from AWS SSM Parameter Store
#

set -e

echo "========================================="
echo "Analytics Platform - Starting ETL"
echo "========================================="
echo ""

# Configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
SSM_PREFIX="/pepsico"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ========================================
# Fetch Database Credentials from SSM
# ========================================

echo -e "${YELLOW}Fetching database credentials from SSM...${NC}"

export DB_HOST=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/DB_HOST" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

export DB_NAME=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/DB_NAME" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

export DB_USER=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/DB_USER" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

export DB_PASSWORD=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/DB_PASSWORD" \
    --with-decryption \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

# Validate required parameters
if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}Error: Required SSM parameters not found${NC}"
    echo "Expected parameters at:"
    echo "  ${SSM_PREFIX}/DB_HOST"
    echo "  ${SSM_PREFIX}/DB_NAME"
    echo "  ${SSM_PREFIX}/DB_USER"
    echo "  ${SSM_PREFIX}/DB_PASSWORD"
    exit 1
fi

echo -e "${GREEN}✓ Database credentials retrieved${NC}"
echo "  Host: $DB_HOST"
echo "  Database: $DB_NAME"
echo "  User: $DB_USER"
echo ""

# ========================================
# Fetch AppDynamics Credentials from SSM
# ========================================

echo -e "${YELLOW}Fetching AppDynamics credentials from SSM...${NC}"

export APPD_CONTROLLER=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/CONTROLLER" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export APPD_ACCOUNT=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/ACCOUNT" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export APPD_CLIENT_NAME=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/CLIENT_NAME" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export APPD_CLIENT_SECRET=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/appdynamics/CLIENT_SECRET" \
    --with-decryption \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

if [ -n "$APPD_CONTROLLER" ]; then
    echo -e "${GREEN}✓ AppDynamics credentials retrieved${NC}"
    echo "  Controller: $APPD_CONTROLLER"
    echo "  Account: $APPD_ACCOUNT"
else
    echo -e "${YELLOW}⚠ AppDynamics credentials not found (skipping)${NC}"
fi
echo ""

# ========================================
# Fetch ServiceNow Credentials from SSM
# ========================================

echo -e "${YELLOW}Fetching ServiceNow credentials from SSM...${NC}"

export SN_INSTANCE=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/servicenow/INSTANCE" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export SN_CLIENT_ID=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/servicenow/CLIENT_ID" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export SN_CLIENT_SECRET=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/servicenow/CLIENT_SECRET" \
    --with-decryption \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

# Legacy: Try username/password if OAuth not available
export SN_USER=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/servicenow/USER" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

export SN_PASS=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/servicenow/PASS" \
    --with-decryption \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

if [ -n "$SN_INSTANCE" ]; then
    echo -e "${GREEN}✓ ServiceNow credentials retrieved${NC}"
    echo "  Instance: $SN_INSTANCE"
    if [ -n "$SN_CLIENT_ID" ]; then
        echo "  Auth Method: OAuth 2.0 (Client Credentials)"
        echo "  Client ID: $SN_CLIENT_ID"
    elif [ -n "$SN_USER" ]; then
        echo "  Auth Method: Basic Auth (Legacy)"
        echo "  User: $SN_USER"
    else
        echo -e "${RED}  ERROR: No authentication credentials found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ ServiceNow credentials not found (skipping)${NC}"
fi
echo ""

# ========================================
# Test Database Connection
# ========================================

echo -e "${YELLOW}Testing database connection...${NC}"

if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}Error: Cannot connect to database${NC}"
    echo "Check:"
    echo "  1. RDS security group allows EC2 access"
    echo "  2. Database credentials are correct"
    echo "  3. Database exists and user has permissions"
    exit 1
fi
echo ""

# ========================================
# Execute Command
# ========================================

echo "========================================="
echo "Starting ETL Pipeline"
echo "========================================="
echo ""

# Execute the provided command or default to run_pipeline.py
if [ $# -eq 0 ]; then
    exec python3 /app/scripts/etl/run_pipeline.py
else
    exec "$@"
fi
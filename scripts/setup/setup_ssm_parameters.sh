#!/bin/bash
#
# SSM Parameter Store Setup
# Configure all required parameters for Analytics Platform
#
# Usage: ./setup_ssm_parameters.sh
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SSM Parameter Store Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Configuration
AWS_REGION="us-east-2"
SSM_BASE="/pepsico"

echo -e "${YELLOW}This script will configure SSM parameters at: ${SSM_BASE}${NC}"
echo -e "${YELLOW}Region: ${AWS_REGION}${NC}"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi
echo ""

# ========================================
# Helper Functions
# ========================================

create_parameter() {
    local name=$1
    local value=$2
    local type=${3:-String}
    local description=$4
    
    if aws ssm get-parameter --name "$name" --region $AWS_REGION &>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC} $name (already exists, skipping)"
    else
        aws ssm put-parameter \
            --name "$name" \
            --value "$value" \
            --type "$type" \
            --description "$description" \
            --region $AWS_REGION \
            --overwrite > /dev/null
        echo -e "  ${GREEN}✓${NC} $name"
    fi
}

prompt_value() {
    local prompt=$1
    local default=$2
    local is_secret=${3:-false}
    
    if [ "$is_secret" = "true" ]; then
        read -s -p "$prompt: " value
        echo ""
    else
        read -p "$prompt [$default]: " value
        value=${value:-$default}
    fi
    
    echo "$value"
}

# ========================================
# 1. Database Parameters
# ========================================
echo -e "${BLUE}1. Database Configuration${NC}"
echo ""

DB_HOST=$(prompt_value "RDS Endpoint" "your-db.us-east-2.rds.amazonaws.com")
DB_NAME=$(prompt_value "Database Name" "cost_analytics_db")
DB_USER=$(prompt_value "ETL User" "etl_analytics")
DB_PASSWORD=$(prompt_value "ETL User Password" "" "true")
DB_ADMIN_PASSWORD=$(prompt_value "Master Password" "" "true")
GRAFANA_PASSWORD=$(prompt_value "Grafana RO Password" "" "true")

echo ""
echo -e "${YELLOW}Creating database parameters...${NC}"

create_parameter "${SSM_BASE}/DB_HOST" "$DB_HOST" "String" "RDS database endpoint"
create_parameter "${SSM_BASE}/DB_NAME" "$DB_NAME" "String" "Database name"
create_parameter "${SSM_BASE}/DB_USER" "$DB_USER" "String" "ETL service user"
create_parameter "${SSM_BASE}/DB_PASSWORD" "$DB_PASSWORD" "SecureString" "ETL user password"
create_parameter "${SSM_BASE}/DB_ADMIN_PASSWORD" "$DB_ADMIN_PASSWORD" "SecureString" "PostgreSQL master password"
create_parameter "${SSM_BASE}/GRAFANA_DB_PASSWORD" "$GRAFANA_PASSWORD" "SecureString" "Grafana read-only password"

echo ""

# ========================================
# 2. AppDynamics Parameters
# ========================================
echo -e "${BLUE}2. AppDynamics Configuration${NC}"
echo ""

read -p "Configure AppDynamics? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    APPD_CONTROLLER=$(prompt_value "Controller URL" "your-account.saas.appdynamics.com")
    APPD_ACCOUNT=$(prompt_value "Account Name" "your-account")
    APPD_CLIENT_ID=$(prompt_value "Client ID" "")
    APPD_CLIENT_SECRET=$(prompt_value "Client Secret" "" "true")
    
    echo ""
    echo -e "${YELLOW}Creating AppDynamics parameters...${NC}"
    
    create_parameter "${SSM_BASE}/appdynamics/CONTROLLER" "$APPD_CONTROLLER" "String" "AppDynamics controller URL"
    create_parameter "${SSM_BASE}/appdynamics/ACCOUNT" "$APPD_ACCOUNT" "String" "AppDynamics account name"
    create_parameter "${SSM_BASE}/appdynamics/CLIENT_ID" "$APPD_CLIENT_ID" "String" "AppDynamics API client ID"
    create_parameter "${SSM_BASE}/appdynamics/CLIENT_SECRET" "$APPD_CLIENT_SECRET" "SecureString" "AppDynamics API client secret"
    
    echo ""
fi

# ========================================
# 3. ServiceNow Parameters
# ========================================
echo -e "${BLUE}3. ServiceNow Configuration${NC}"
echo ""

read -p "Configure ServiceNow? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    SN_INSTANCE=$(prompt_value "Instance URL" "dev12345.service-now.com")
    SN_USER=$(prompt_value "Username" "")
    SN_PASS=$(prompt_value "Password" "" "true")
    
    echo ""
    echo -e "${YELLOW}Creating ServiceNow parameters...${NC}"
    
    create_parameter "${SSM_BASE}/servicenow/INSTANCE" "$SN_INSTANCE" "String" "ServiceNow instance URL"
    create_parameter "${SSM_BASE}/servicenow/USER" "$SN_USER" "String" "ServiceNow API user"
    create_parameter "${SSM_BASE}/servicenow/PASS" "$SN_PASS" "SecureString" "ServiceNow API password"
    
    echo ""
fi

# ========================================
# 4. Optional: Future Tool Placeholders
# ========================================
echo -e "${BLUE}4. Future Tool Configuration${NC}"
echo ""

read -p "Create placeholder paths for future tools? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}Creating placeholder structure...${NC}"
    
    # Just create the paths with dummy values to establish the structure
    create_parameter "${SSM_BASE}/elastic/API_KEY" "CONFIGURE_WHEN_READY" "SecureString" "Elastic API key (placeholder)"
    create_parameter "${SSM_BASE}/datadog/API_KEY" "CONFIGURE_WHEN_READY" "SecureString" "Datadog API key (placeholder)"
    create_parameter "${SSM_BASE}/splunk/API_TOKEN" "CONFIGURE_WHEN_READY" "SecureString" "Splunk API token (placeholder)"
    
    echo ""
fi

# ========================================
# Summary
# ========================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ SSM Setup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Configured parameters:${NC}"

aws ssm get-parameters-by-path \
    --path "$SSM_BASE" \
    --recursive \
    --region $AWS_REGION \
    --query 'Parameters[*].[Name,Type]' \
    --output table

echo ""
echo -e "${YELLOW}To view a parameter:${NC}"
echo "  aws ssm get-parameter --name '${SSM_BASE}/DB_HOST' --region ${AWS_REGION}"
echo ""
echo -e "${YELLOW}To view a secure parameter:${NC}"
echo "  aws ssm get-parameter --name '${SSM_BASE}/DB_PASSWORD' --with-decryption --region ${AWS_REGION}"
echo ""
echo -e "${YELLOW}To update a parameter:${NC}"
echo "  aws ssm put-parameter --name '${SSM_BASE}/DB_HOST' --value 'new-value' --overwrite --region ${AWS_REGION}"
echo ""
echo -e "${BLUE}Parameter Structure:${NC}"
echo "  ${SSM_BASE}/"
echo "    ├── DB_HOST, DB_NAME, DB_USER, DB_PASSWORD"
echo "    ├── appdynamics/"
echo "    │   └── CONTROLLER, ACCOUNT, CLIENT_ID, CLIENT_SECRET"
echo "    ├── servicenow/"
echo "    │   └── INSTANCE, USER, PASS"
echo "    └── (future tools)/"
echo ""
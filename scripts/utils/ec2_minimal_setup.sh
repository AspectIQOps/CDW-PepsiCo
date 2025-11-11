#!/bin/bash
#
# EC2 Minimal Setup - ETL Only (No Docker)
# Installs only what's needed to run Python ETL scripts
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Analytics Platform - Minimal ETL Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

AWS_REGION="us-east-2"
PROJECT_DIR="$(pwd)"

# ========================================
# 1. Install Python3 + pip (if not present)
# ========================================
echo -e "${YELLOW}Step 1: Installing Python3...${NC}"

if ! command -v python3 &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip
    echo -e "${GREEN}✓ Python3 installed${NC}"
else
    echo -e "${GREEN}✓ Python3 already installed${NC}"
fi

python3 --version
pip3 --version
echo ""

# ========================================
# 2. Install AWS CLI (for SSM access)
# ========================================
echo -e "${YELLOW}Step 2: Installing AWS CLI...${NC}"

if ! command -v aws &> /dev/null; then
    # Install unzip if needed
    if ! command -v unzip &> /dev/null; then
        sudo apt-get install -y unzip
    fi

    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    echo -e "${GREEN}✓ AWS CLI installed${NC}"
else
    echo -e "${GREEN}✓ AWS CLI already installed${NC}"
fi

aws --version
echo ""

# ========================================
# 3. Install Python Dependencies
# ========================================
echo -e "${YELLOW}Step 3: Installing Python packages...${NC}"

pip3 install --user psycopg2-binary requests

echo -e "${GREEN}✓ Python packages installed${NC}"
echo ""

# ========================================
# 4. Verify SSM Access
# ========================================
echo -e "${YELLOW}Step 4: Verifying SSM access...${NC}"

if aws ssm get-parameter --name "/pepsico/DB_HOST" --region $AWS_REGION &>/dev/null; then
    echo -e "${GREEN}✓ SSM access confirmed${NC}"
else
    echo -e "${RED}✗ Cannot access SSM parameters${NC}"
    echo "  Verify EC2 IAM role has ssm:GetParameter permissions"
    exit 1
fi
echo ""

# ========================================
# 5. Create Cron Job for Daily ETL
# ========================================
echo -e "${YELLOW}Step 5: Setting up cron job...${NC}"

CRON_CMD="cd $PROJECT_DIR && export AWS_DEFAULT_REGION=$AWS_REGION && bash docker/etl/entrypoint.sh python3 scripts/etl/run_pipeline.py >> $HOME/etl.log 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "run_pipeline.py"; then
    echo -e "${GREEN}✓ Cron job already configured${NC}"
else
    # Add cron job: Daily at 2 AM
    (crontab -l 2>/dev/null; echo "0 2 * * * $CRON_CMD") | crontab -
    echo -e "${GREEN}✓ Cron job configured (daily at 2 AM)${NC}"
fi
echo ""

# ========================================
# Setup Complete
# ========================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Minimal Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Manual Test Run:${NC}"
echo "  cd $PROJECT_DIR"
echo "  export AWS_DEFAULT_REGION=$AWS_REGION"
echo "  bash docker/etl/entrypoint.sh python3 scripts/etl/run_pipeline.py"
echo ""
echo -e "${YELLOW}Check Logs:${NC}"
echo "  tail -f $HOME/etl.log"
echo ""
echo -e "${YELLOW}Installed:${NC}"
echo "  • Python3 + pip"
echo "  • AWS CLI"
echo "  • psycopg2-binary (PostgreSQL driver)"
echo "  • requests (HTTP library)"
echo ""
echo -e "${GREEN}Total footprint: ~100MB${NC}"
echo ""

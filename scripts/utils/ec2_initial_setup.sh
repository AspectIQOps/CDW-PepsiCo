#!/bin/bash
#
# EC2 Initial Setup - Analytics Platform
# Run this script on a fresh Ubuntu EC2 instance
#
# Prerequisites:
# - EC2 instance with IAM role for SSM access
# - RDS PostgreSQL instance accessible from EC2
# - SSM parameters configured at /pepsico/*
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Analytics Platform - EC2 Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Configuration
AWS_REGION="us-east-2"
REPO_URL="https://github.com/AspectIQOps/CDW-PepsiCo.git"
REPO_BRANCH="deploy-docker"
PROJECT_DIR="$HOME/CDW-PepsiCo"

# ========================================
# 1. System Updates
# ========================================
echo -e "${YELLOW}Step 1: Updating system packages...${NC}"
sudo apt-get update
sudo apt-get upgrade -y
echo -e "${GREEN}✓ System updated${NC}"
echo ""

# ========================================
# 2. Install Docker
# ========================================
echo -e "${YELLOW}Step 2: Installing Docker...${NC}"

if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add user to docker group
    sudo usermod -aG docker $USER
    
    echo -e "${GREEN}✓ Docker installed${NC}"
else
    echo -e "${GREEN}✓ Docker already installed${NC}"
fi

docker --version
echo ""

# ========================================
# 3. Install AWS CLI and PostgreSQL Client
# ========================================
echo -e "${YELLOW}Step 3: Installing AWS CLI and PostgreSQL client...${NC}"

# Install unzip if not present
if ! command -v unzip &> /dev/null; then
    sudo apt-get install -y unzip
fi

# AWS CLI
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    echo -e "${GREEN}✓ AWS CLI installed${NC}"
else
    echo -e "${GREEN}✓ AWS CLI already installed${NC}"
fi

aws --version

# PostgreSQL client
if ! command -v psql &> /dev/null; then
    sudo apt-get install -y postgresql-client
    echo -e "${GREEN}✓ PostgreSQL client installed${NC}"
else
    echo -e "${GREEN}✓ PostgreSQL client already installed${NC}"
fi

psql --version
echo ""

# ========================================
# 4. Clone Repository
# ========================================
echo -e "${YELLOW}Step 4: Cloning project repository...${NC}"

if [ -d "$PROJECT_DIR" ]; then
    echo -e "${YELLOW}Project directory exists. Pulling latest changes...${NC}"
    cd "$PROJECT_DIR"
    git pull origin $REPO_BRANCH
else
    git clone -b $REPO_BRANCH $REPO_URL $PROJECT_DIR
    cd "$PROJECT_DIR"
fi

echo -e "${GREEN}✓ Repository ready at: $PROJECT_DIR${NC}"
echo ""

# ========================================
# 5. Verify SSM Parameters
# ========================================
echo -e "${YELLOW}Step 5: Verifying SSM parameters...${NC}"

SSM_PREFIX="/pepsico"
REQUIRED_PARAMS=(
    "${SSM_PREFIX}/DB_HOST"
    "${SSM_PREFIX}/DB_NAME"
    "${SSM_PREFIX}/DB_USER"
    "${SSM_PREFIX}/DB_PASSWORD"
    "${SSM_PREFIX}/appdynamics/CONTROLLER"
    "${SSM_PREFIX}/servicenow/INSTANCE"
)

MISSING_PARAMS=()

for param in "${REQUIRED_PARAMS[@]}"; do
    if aws ssm get-parameter --name "$param" --region $AWS_REGION &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $param"
    else
        echo -e "  ${RED}✗${NC} $param"
        MISSING_PARAMS+=("$param")
    fi
done

if [ ${#MISSING_PARAMS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Missing SSM parameters:${NC}"
    printf '  %s\n' "${MISSING_PARAMS[@]}"
    echo ""
    echo -e "${YELLOW}Please configure these parameters before proceeding.${NC}"
    echo "Example:"
    echo "  aws ssm put-parameter --name '/pepsico/DB_HOST' --value 'your-rds-endpoint' --type String --region $AWS_REGION"
    exit 1
fi

echo -e "${GREEN}✓ All required SSM parameters present${NC}"
echo ""

# ========================================
# 6. Test Database Connection
# ========================================
echo -e "${YELLOW}Step 6: Testing database connection...${NC}"

DB_HOST=$(aws ssm get-parameter --name "${SSM_PREFIX}/DB_HOST" --region $AWS_REGION --query 'Parameter.Value' --output text)
DB_NAME=$(aws ssm get-parameter --name "${SSM_PREFIX}/DB_NAME" --region $AWS_REGION --query 'Parameter.Value' --output text)
DB_USER=postgres
DB_PASSWORD=$(aws ssm get-parameter --name "${SSM_PREFIX}/DB_ADMIN_PASSWORD" --with-decryption --region $AWS_REGION --query 'Parameter.Value' --output text)

if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1;" &>/dev/null; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
    echo "  Host: $DB_HOST"
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
else
    echo -e "${RED}✗ Database connection failed${NC}"
    echo "  Host: $DB_HOST"
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
    echo ""
    echo -e "${YELLOW}Please verify:${NC}"
    echo "  1. RDS security group allows EC2 access"
    echo "  2. Database credentials are correct"
    echo "  3. Database exists and user has permissions"
    exit 1
fi
echo ""

# ========================================
# 7. Create Environment File
# ========================================
echo -e "${YELLOW}Step 7: Creating .env file...${NC}"

cat > "$PROJECT_DIR/.env" <<EOF
# Auto-generated on $(date)
# Database Configuration
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_PORT=5432

# AWS Configuration
AWS_REGION=$AWS_REGION
AWS_DEFAULT_REGION=$AWS_REGION

# SSM Paths
SSM_BASE_PATH=$SSM_PREFIX
SSM_APPDYNAMICS_PREFIX=${SSM_PREFIX}/appdynamics
SSM_SERVICENOW_PREFIX=${SSM_PREFIX}/servicenow

# Pipeline Configuration
PIPELINE_MODE=full
LOG_LEVEL=INFO
EOF

chmod 600 "$PROJECT_DIR/.env"
echo -e "${GREEN}✓ Environment file created${NC}"
echo ""

# ========================================
# 8. Build Docker Image
# ========================================
echo -e "${YELLOW}Step 8: Building Docker image...${NC}"

cd "$PROJECT_DIR"
docker compose -f docker-compose.ec2.yaml build

echo -e "${GREEN}✓ Docker image built${NC}"
echo ""

# ========================================
# 9. Make Scripts Executable
# ========================================
echo -e "${YELLOW}Step 9: Setting script permissions...${NC}"

chmod +x scripts/setup/*.sh
chmod +x scripts/utils/*.sh

echo -e "${GREEN}✓ Script permissions set${NC}"
echo ""

# ========================================
# Setup Complete
# ========================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ EC2 Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Initialize database schema:"
echo "   cd $PROJECT_DIR"
echo "   ./scripts/setup/init_database.sh"
echo ""
echo "2. Run ETL pipeline:"
echo "   ./scripts/utils/daily_startup.sh"
echo ""
echo "3. Check logs:"
echo "   docker compose -f docker-compose.ec2.yaml logs -f"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  Health check: ./scripts/utils/health_check.sh"
echo "  Verify data:  ./scripts/utils/verify_setup.sh"
echo "  Shutdown:     ./scripts/utils/daily_teardown.sh"
echo ""
echo -e "${BLUE}Project configured for:${NC}"
echo "  Database: cost_analytics_db"
echo "  ETL User: etl_analytics"
echo "  SSM Path: /pepsico/*"
echo ""
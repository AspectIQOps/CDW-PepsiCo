#!/bin/bash
# ==========================================================
# 🚀 CDW-PepsiCo Docker Stack Deployment
# Builds and starts the complete PepsiCo AppDynamics stack
# ==========================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine repo root dynamically
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=============================================="
echo -e "${BLUE}🚀 PepsiCo AppDynamics Licensing Dashboard${NC}"
echo "   Docker Stack Deployment"
echo "=============================================="
echo ""
echo "Repository root: $REPO_ROOT"
echo ""

# Check if running as root (shouldn't be)
if [ "$EUID" -eq 0 ]; then 
    echo -e "${YELLOW}⚠️  WARNING: Running as root. Consider using a regular user in the docker group.${NC}"
    echo ""
fi

# Check if .env file exists
if [ ! -f "$REPO_ROOT/.env" ]; then
    echo -e "${RED}❌ ERROR: .env file not found${NC}"
    echo ""
    echo "Please create a .env file in the repository root."
    echo ""
    echo "📝 For LOCAL DEVELOPMENT:"
    echo "   cp .env.example .env"
    echo "   # Edit .env and fill in all DB_* and SN_* credentials"
    echo ""
    echo "☁️  For AWS PRODUCTION (using SSM):"
    echo "   # Leave DB_PASSWORD empty in .env"
    echo "   # Ensure AWS credentials are configured"
    echo "   # Ensure EC2 instance has IAM role with SSM read permissions"
    echo ""
    exit 1
fi

# Load .env to check mode
set -a
source "$REPO_ROOT/.env"
set +a

# Determine deployment mode
if [ -n "$DB_PASSWORD" ]; then
    echo -e "${GREEN}✅ Local development mode detected${NC}"
    echo "   (DB_PASSWORD is set in .env)"
    LOCAL_MODE=true
else
    echo -e "${BLUE}☁️  AWS Production mode detected${NC}"
    echo "   (DB_PASSWORD is empty - will use SSM)"
    echo "   SSM Path: ${SSM_PATH:-/aspectiq/demo}"
    LOCAL_MODE=false
    
    # Verify AWS CLI is available in production mode
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ ERROR: AWS CLI not found but required for production mode${NC}"
        echo "   Install: pip install awscli"
        exit 1
    fi
    
    # Test SSM access
    echo "   Testing SSM access..."
    if aws ssm get-parameter --name "${SSM_PATH:-/aspectiq/demo}/DB_NAME" --query "Parameter.Value" --output text &>/dev/null; then
        echo -e "${GREEN}   ✅ SSM access verified${NC}"
    else
        echo -e "${YELLOW}   ⚠️  WARNING: Cannot access SSM parameters${NC}"
        echo "   Ensure EC2 instance has proper IAM role"
    fi
fi
echo ""

# Validate required vars for local mode
if [ "$LOCAL_MODE" = true ]; then
    REQUIRED_VARS=("DB_USER" "DB_PASSWORD" "DB_NAME")
    MISSING_VARS=()
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            MISSING_VARS+=("$var")
        fi
    done
    
    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        echo -e "${RED}❌ ERROR: Missing required environment variables:${NC}"
        for var in "${MISSING_VARS[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Please update your .env file."
        exit 1
    fi
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ ERROR: Docker is not installed${NC}"
    echo ""
    echo "Run the environment setup script first:"
    echo "  sudo ./scripts/setup/setup_docker_env.sh"
    echo ""
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ ERROR: Docker Compose plugin is not available${NC}"
    echo ""
    echo "Run the environment setup script first:"
    echo "  sudo ./scripts/setup/setup_docker_env.sh"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Docker environment ready${NC}"
docker --version
docker compose version
echo ""

# Set permissions
echo "🔧 Setting file permissions..."
chmod +x "$REPO_ROOT"/scripts/etl/*.py 2>/dev/null || true
chmod +x "$REPO_ROOT"/docker/etl/entrypoint.sh
chmod +x "$REPO_ROOT"/scripts/utils/*.sh 2>/dev/null || true
chmod +x "$REPO_ROOT"/scripts/setup/*.sh 2>/dev/null || true

echo -e "${GREEN}✅ Permissions set${NC}"
echo ""

# Clean slate option
read -p "🧹 Do you want to remove existing containers and volumes? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🧹 Stopping and removing existing containers..."
    cd "$REPO_ROOT"
    docker compose down -v 2>/dev/null || true
    echo -e "${GREEN}✅ Cleanup complete${NC}"
else
    echo "⏭️  Skipping cleanup (will attempt to restart existing containers)"
    cd "$REPO_ROOT"
    docker compose down 2>/dev/null || true
fi
echo ""

# Build and start infrastructure
echo "🐳 Building and starting infrastructure services..."
echo "   (PostgreSQL and Grafana)"
echo ""

cd "$REPO_ROOT"
docker compose up -d --build postgres grafana

echo ""
echo "⏳ Waiting for PostgreSQL to initialize..."

# Wait for postgres to be healthy
MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if docker compose exec -T postgres pg_isready -U appd_ro -d appd_licensing > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PostgreSQL is ready${NC}"
        break
    fi
    
    if [ $ELAPSED -eq 0 ]; then
        echo -n "   Waiting"
    fi
    echo -n "."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo ""
        echo -e "${RED}❌ PostgreSQL failed to become ready within ${MAX_WAIT}s${NC}"
        echo ""
        echo "Check logs:"
        echo "  docker compose logs postgres"
        exit 1
    fi
done
echo ""
echo ""

# Verify database schema
echo "🔍 Verifying database schema..."
TABLE_COUNT=$(docker compose exec -T postgres psql -U appd_ro -d appd_licensing -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ Database schema initialized (${TABLE_COUNT} tables)${NC}"
    
    # Show dimension table counts
    docker compose exec -T postgres psql -U appd_ro -d appd_licensing << 'EOF'
\echo ''
\echo 'Dimension Tables:'
SELECT 'owners_dim' as table_name, COUNT(*) as rows FROM owners_dim
UNION ALL SELECT 'sectors_dim', COUNT(*) FROM sectors_dim
UNION ALL SELECT 'architecture_dim', COUNT(*) FROM architecture_dim
UNION ALL SELECT 'capabilities_dim', COUNT(*) FROM capabilities_dim
UNION ALL SELECT 'time_dim', COUNT(*) FROM time_dim;
EOF
else
    echo -e "${YELLOW}⚠️  WARNING: No tables found. Init scripts may have failed.${NC}"
    echo "Check logs:"
    echo "  docker compose logs postgres | grep ERROR"
fi
echo ""

# Check Grafana
if docker compose ps grafana | grep -q "Up"; then
    echo -e "${GREEN}✅ Grafana is running${NC}"
else
    echo -e "${YELLOW}⚠️  WARNING: Grafana may not be healthy${NC}"
    echo "Check logs:"
    echo "  docker compose logs grafana"
fi
echo ""

echo "=============================================="
echo -e "${GREEN}✅ Infrastructure Deployment Complete!${NC}"
echo "=============================================="
echo ""
echo "📍 Services Running:"
echo "   • PostgreSQL:  localhost:5432"
echo "   • Grafana:     http://localhost:3000"
echo ""
echo "🔐 Grafana Login:"
echo "   Username: admin"
echo "   Password: admin"
echo "   (Change password on first login)"
echo ""
echo "🔄 Next Steps - Run ETL Jobs:"
echo ""
echo "   # ServiceNow ETL (populate applications from CMDB):"
echo "   docker compose run --rm etl_snow"
echo ""
echo "   # AppDynamics ETL (populate license usage - when ready):"
echo "   docker compose run --rm etl_appd"
echo ""
echo "📊 Verify Data:"
echo "   docker compose exec postgres psql -U appd_ro -d appd_licensing"
echo ""
echo "📝 View Logs:"
echo "   docker compose logs -f postgres"
echo "   docker compose logs -f grafana"
echo "   docker compose logs etl_snow"
echo ""
echo "🛑 Stop Services:"
echo "   docker compose down"
echo ""
echo "🗑️  Full Cleanup (removes data):"
echo "   docker compose down -v"
echo ""
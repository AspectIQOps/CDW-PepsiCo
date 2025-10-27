#!/bin/bash
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
echo "   Docker Stack Setup"
echo "=============================================="
echo ""
echo "Repository root: $REPO_ROOT"
echo ""

# Check if .env file exists
if [ ! -f "$REPO_ROOT/.env" ]; then
    echo -e "${RED}❌ ERROR: .env file not found${NC}"
    echo ""
    echo "Please create a .env file in the repository root."
    echo ""
    echo "For LOCAL DEVELOPMENT (no AWS SSM):"
    echo "  cp .env.example .env"
    echo "  # Edit .env and set DB_PASSWORD and other credentials"
    echo ""
    echo "For PRODUCTION (with AWS SSM):"
    echo "  # Leave DB_PASSWORD empty in .env"
    echo "  # Ensure AWS credentials and SSM_PATH are configured"
    echo ""
    exit 1
fi

# Load .env
set -a
source "$REPO_ROOT/.env"
set +a

# Check if running locally or in AWS
if [ -n "$DB_PASSWORD" ]; then
    echo -e "${GREEN}✅ Local development mode detected (DB_PASSWORD set in .env)${NC}"
    LOCAL_MODE=true
else
    echo -e "${BLUE}☁️  Production mode detected (will use AWS SSM)${NC}"
    LOCAL_MODE=false
fi

# Validate required vars for local mode
if [ "$LOCAL_MODE" = true ]; then
    REQUIRED_VARS=(
        "DB_USER"
        "DB_PASSWORD"
        "DB_NAME"
    )
    
    MISSING_VARS=()
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            MISSING_VARS+=("$var")
        fi
    done
    
    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        echo -e "${RED}❌ ERROR: Missing required local environment variables:${NC}"
        for var in "${MISSING_VARS[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
fi

echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ ERROR: Docker is not installed${NC}"
    echo "Run: ./scripts/setup/setup_docker_env.sh"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ ERROR: Docker Compose is not available${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker environment ready${NC}"
echo ""

# Set permissions
echo "🔧 Setting file permissions..."
chmod +x "$REPO_ROOT"/scripts/etl/*.py 2>/dev/null || true
chmod +x "$REPO_ROOT"/docker/etl/entrypoint.sh
chmod +x "$REPO_ROOT"/scripts/utils/*.sh 2>/dev/null || true
chmod +x "$REPO_ROOT"/scripts/setup/*.sh 2>/dev/null || true

echo -e "${GREEN}✅ Permissions set${NC}"
echo ""

# Stop existing containers
echo "🧹 Stopping any existing containers..."
cd "$REPO_ROOT"
docker compose down 2>/dev/null || true
echo ""

# Build and start infrastructure
echo "🐳 Building and starting infrastructure services..."
echo "   (PostgreSQL and Grafana)"
echo ""

docker compose up -d --build postgres grafana

echo ""
echo "⏳ Waiting for PostgreSQL to initialize..."
sleep 10

# Check PostgreSQL health
echo "🔍 Checking PostgreSQL health..."
for i in {1..30}; do
    if docker compose exec -T postgres pg_isready -U appd_ro -d appd_licensing > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PostgreSQL is ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ PostgreSQL failed to become ready${NC}"
        echo "Check logs: docker compose logs postgres"
        exit 1
    fi
    echo "  Attempt $i/30..."
    sleep 2
done

echo ""
echo "🔍 Verifying database schema..."
docker compose exec -T postgres psql -U appd_ro -d appd_licensing << 'EOF'
\echo '============================================'
\echo 'Database Tables:'
\echo '============================================'
SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
\echo ''
\echo 'Dimension table row counts:'
SELECT 'owners_dim' as table_name, COUNT(*) as rows FROM owners_dim
UNION ALL SELECT 'sectors_dim', COUNT(*) FROM sectors_dim
UNION ALL SELECT 'architecture_dim', COUNT(*) FROM architecture_dim
UNION ALL SELECT 'capabilities_dim', COUNT(*) FROM capabilities_dim
UNION ALL SELECT 'time_dim', COUNT(*) FROM time_dim;
EOF

echo ""
echo "=============================================="
echo -e "${GREEN}✅ Infrastructure Setup Complete!${NC}"
echo "=============================================="
echo ""
echo "📍 Services Running:"
echo "   • PostgreSQL:  localhost:5432"
echo "   • Grafana:     http://localhost:3000"
echo ""
echo "🔐 Grafana Login:"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "🔄 Next Steps - Run ETL Jobs:"
echo ""
echo "   # ServiceNow ETL (populate applications from CMDB):"
echo "   docker compose run --rm etl_snow"
echo ""
echo "   # AppDynamics ETL (populate license usage):"
echo "   docker compose run --rm etl_appd"
echo ""
echo "📊 Verify Data:"
echo "   ./scripts/utils/verify_setup.sh"
echo ""
echo "📝 View Logs:"
echo "   docker compose logs -f postgres"
echo "   docker compose logs -f grafana"
echo "   docker compose logs etl_snow"
echo "   docker compose logs etl_appd"
echo ""
echo "🗄️  Database Access:"
echo "   docker compose exec postgres psql -U appd_ro -d appd_licensing"
echo ""
echo "🛑 Stop Services:"
echo "   docker compose down"
echo ""
echo "🗑️  Full Cleanup (removes data):"
echo "   docker compose down -v"
echo ""
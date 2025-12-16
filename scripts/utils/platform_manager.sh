#!/bin/bash
#
# Analytics Platform Manager
# Consolidated utility for all platform operations
#
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AWS_REGION="us-east-2"
SSM_PREFIX="/pepsico"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yaml"

# ========================================
# Helper Functions
# ========================================

show_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

show_usage() {
    echo -e "${CYAN}Analytics Platform Manager${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./platform_manager.sh [command]"
    echo ""
    echo -e "${YELLOW}Commands:${NC}"
    echo -e "  ${GREEN}start${NC}      - Start the ETL pipeline"
    echo -e "  ${GREEN}stop${NC}       - Stop all containers"
    echo -e "  ${GREEN}restart${NC}    - Restart the pipeline"
    echo -e "  ${GREEN}rebuild${NC}    - Force rebuild (no cache) and restart"
    echo -e "  ${GREEN}status${NC}     - Show system status"
    echo -e "  ${GREEN}health${NC}     - Run health checks"
    echo -e "  ${GREEN}validate${NC}   - Validate data quality"
    echo -e "  ${GREEN}logs${NC}       - Show container logs and follow"
    echo -e "  ${GREEN}clean${NC}      - Clean up containers and logs"
    echo -e "  ${GREEN}db${NC}         - Connect to database"
    echo -e "  ${GREEN}db-exec${NC}    - Execute SQL command or file"
    echo -e "  ${GREEN}pricing${NC}    - Manage test pricing data"
    echo -e "  ${GREEN}ssm${NC}        - List SSM parameters"
    echo ""
    echo -e "${YELLOW}Pricing Commands:${NC}"
    echo -e "  ${GREEN}pricing add${NC}     - Add temporary test pricing"
    echo -e "  ${GREEN}pricing show${NC}    - Show current pricing"
    echo -e "  ${GREEN}pricing clear${NC}   - Clear test pricing"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ./platform_manager.sh start"
    echo "  ./platform_manager.sh status"
    echo "  ./platform_manager.sh logs"
    echo "  ./platform_manager.sh pricing add"
    echo "  ./platform_manager.sh db-exec \"SELECT COUNT(*) FROM license_usage_fact;\""
}

get_ssm_param() {
    local param_name=$1
    aws ssm get-parameter \
        --name "${SSM_PREFIX}/${param_name}" \
        --region $AWS_REGION \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo ""
}

get_ssm_param_secure() {
    local param_name=$1
    aws ssm get-parameter \
        --name "${SSM_PREFIX}/${param_name}" \
        --with-decryption \
        --region $AWS_REGION \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo ""
}

# ========================================
# Start Command (replaces daily_startup.sh)
# ========================================

cmd_start() {
    show_header "Starting Analytics Platform"
    
    cd "$PROJECT_ROOT"
    
    # Check if already running
    if docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -q "Up"; then
        echo -e "${YELLOW}Pipeline already running${NC}"
        echo ""
        docker compose -f "$COMPOSE_FILE" ps
        echo ""
        read -p "Restart? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cmd_stop
            sleep 2
        else
            return 0
        fi
    fi
    
    echo -e "${YELLOW}Verifying SSM parameters...${NC}"
    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")
    
    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}✗ SSM parameters not configured${NC}"
        echo "Run: aws ssm get-parameters-by-path --path /pepsico --region us-east-2"
        exit 1
    fi
    
    echo -e "${GREEN}✓ SSM parameters found${NC}"
    echo ""
    
    echo -e "${YELLOW}Starting containers...${NC}"
    docker compose -f "$COMPOSE_FILE" up -d --build
    
    echo ""
    echo -e "${GREEN}✓ Platform started${NC}"
    echo ""
    echo "Monitor with: ./platform_manager.sh logs"
    echo "Check status: ./platform_manager.sh status"
}

# ========================================
# Start Auto Command (for cron/automated execution)
# ========================================

cmd_start_auto() {
    show_header "Starting Analytics Platform (Automated)"
    
    cd "$PROJECT_ROOT"
    
    # Check if already running - auto-restart if needed
    if docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -q "Up"; then
        echo -e "${YELLOW}Pipeline already running - restarting${NC}"
        cmd_stop
        sleep 2
    fi
    
    echo -e "${YELLOW}Verifying SSM parameters...${NC}"
    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")
    
    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}✗ SSM parameters not configured${NC}"
        echo "Run: aws ssm get-parameters-by-path --path /pepsico --region us-east-2"
        exit 1
    fi
    
    echo -e "${GREEN}✓ SSM parameters found${NC}"
    echo ""
    
    echo -e "${YELLOW}Starting containers...${NC}"
    docker compose -f "$COMPOSE_FILE" up -d --build
    
    echo ""
    echo -e "${GREEN}✓ Platform started at $(date)${NC}"
}

# ========================================
# Stop Command (replaces daily_teardown.sh, teardown_docker_stack.sh)
# ========================================

cmd_stop() {
    show_header "Stopping Analytics Platform"
    
    cd "$PROJECT_ROOT"
    
    echo -e "${YELLOW}Stopping containers...${NC}"
    docker compose -f "$COMPOSE_FILE" down
    
    echo -e "${GREEN}✓ Platform stopped${NC}"
}

# ========================================
# Restart Command
# ========================================

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

# ========================================
# Rebuild Command (forces no-cache rebuild)
# ========================================

cmd_rebuild() {
    show_header "Rebuilding Analytics Platform (No Cache)"

    cd "$PROJECT_ROOT"

    echo -e "${YELLOW}Stopping containers...${NC}"
    docker compose -f "$COMPOSE_FILE" down

    echo ""
    echo -e "${YELLOW}Rebuilding images (no cache)...${NC}"
    docker compose -f "$COMPOSE_FILE" build --no-cache

    echo ""
    echo -e "${YELLOW}Starting containers...${NC}"
    docker compose -f "$COMPOSE_FILE" up -d

    echo ""
    echo -e "${GREEN}✓ Platform rebuilt and started${NC}"
}

# ========================================
# Status Command (replaces verify_setup.sh)
# ========================================

cmd_status() {
    show_header "Platform Status"
    
    echo -e "${CYAN}Container Status:${NC}"
    cd "$PROJECT_ROOT"
    if docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -q "Up"; then
        docker compose -f "$COMPOSE_FILE" ps
    else
        echo -e "  ${YELLOW}No containers running${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Database Connection:${NC}"
    
    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_NAME=$(get_ssm_param "DB_NAME")
    DB_USER=$(get_ssm_param "DB_USER")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")
    
    if [ -z "$DB_HOST" ]; then
        echo -e "  ${RED}✗ SSM parameters not configured${NC}"
        return 1
    fi
    
    echo -e "  Host: $DB_HOST"
    echo -e "  Database: $DB_NAME"
    echo -e "  User: $DB_USER"
    
    if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1;" &>/dev/null; then
        echo -e "  ${GREEN}✓ Connected${NC}"
        
        # Get table count
        TABLE_COUNT=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc \
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" \
            2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓ Tables: $TABLE_COUNT${NC}"
        
        # Get recent ETL runs
        RECENT_RUNS=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc \
            "SELECT COUNT(*) FROM audit_etl_runs WHERE start_time > NOW() - INTERVAL '24 hours';" \
            2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓ ETL runs (24h): $RECENT_RUNS${NC}"
        
        # Get active tools
        ACTIVE_TOOLS=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc \
            "SELECT STRING_AGG(tool_name, ', ') FROM tool_configurations WHERE is_active = TRUE;" \
            2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ Active tools: $ACTIVE_TOOLS${NC}"
    else
        echo -e "  ${RED}✗ Cannot connect${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}SSM Parameters:${NC}"
    PARAM_COUNT=$(aws ssm get-parameters-by-path \
        --path "$SSM_PREFIX" \
        --recursive \
        --region $AWS_REGION \
        --query 'length(Parameters)' \
        --output text 2>/dev/null || echo "0")
    echo -e "  Parameters: $PARAM_COUNT"
}

# ========================================
# Health Command (replaces health_check.sh)
# ========================================

cmd_health() {
    show_header "Health Check"
    
    HEALTH_OK=true
    
    echo -e "${CYAN}1. Docker${NC}"
    if command -v docker &> /dev/null; then
        echo -e "  ${GREEN}✓ Docker installed${NC}"
        if docker ps &>/dev/null; then
            echo -e "  ${GREEN}✓ Docker running${NC}"
        else
            echo -e "  ${RED}✗ Docker not running${NC}"
            HEALTH_OK=false
        fi
    else
        echo -e "  ${RED}✗ Docker not installed${NC}"
        HEALTH_OK=false
    fi
    
    echo ""
    echo -e "${CYAN}2. AWS CLI${NC}"
    if command -v aws &> /dev/null; then
        echo -e "  ${GREEN}✓ AWS CLI installed${NC}"
        if aws sts get-caller-identity &>/dev/null; then
            IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
            echo -e "  ${GREEN}✓ IAM role: ${IDENTITY##*/}${NC}"
        else
            echo -e "  ${RED}✗ Cannot assume IAM role${NC}"
            HEALTH_OK=false
        fi
    else
        echo -e "  ${RED}✗ AWS CLI not installed${NC}"
        HEALTH_OK=false
    fi
    
    echo ""
    echo -e "${CYAN}3. PostgreSQL Client${NC}"
    if command -v psql &> /dev/null; then
        echo -e "  ${GREEN}✓ psql installed${NC}"
    else
        echo -e "  ${RED}✗ psql not installed${NC}"
        HEALTH_OK=false
    fi
    
    echo ""
    echo -e "${CYAN}4. SSM Parameters${NC}"
    REQUIRED_PARAMS=("DB_HOST" "DB_NAME" "DB_USER" "DB_PASSWORD")
    for param in "${REQUIRED_PARAMS[@]}"; do
        if aws ssm get-parameter --name "${SSM_PREFIX}/${param}" --region $AWS_REGION &>/dev/null; then
            echo -e "  ${GREEN}✓ $param${NC}"
        else
            echo -e "  ${RED}✗ $param${NC}"
            HEALTH_OK=false
        fi
    done
    
    echo ""
    echo -e "${CYAN}5. Database Connection${NC}"
    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_NAME=$(get_ssm_param "DB_NAME")
    DB_USER=$(get_ssm_param "DB_USER")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")
    
    if [ -n "$DB_HOST" ] && [ -n "$DB_PASSWORD" ]; then
        if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1;" &>/dev/null; then
            echo -e "  ${GREEN}✓ Database reachable${NC}"
            
            VERSION=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc "SELECT version();" | head -1)
            PG_VERSION=$(echo $VERSION | grep -oP 'PostgreSQL \K[0-9.]+')
            echo -e "  ${GREEN}✓ PostgreSQL $PG_VERSION${NC}"
        else
            echo -e "  ${RED}✗ Cannot connect to database${NC}"
            HEALTH_OK=false
        fi
    else
        echo -e "  ${RED}✗ Database credentials missing${NC}"
        HEALTH_OK=false
    fi
    
    echo ""
    echo -e "${CYAN}6. Required Tables${NC}"
    if [ -n "$DB_HOST" ] && [ -n "$DB_PASSWORD" ]; then
        TABLES=("tool_configurations" "audit_etl_runs" "appd_applications" "appd_licenses")
        for table in "${TABLES[@]}"; do
            EXISTS=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc \
                "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema='public' AND table_name='$table');" \
                2>/dev/null || echo "f")
            if [ "$EXISTS" = "t" ]; then
                echo -e "  ${GREEN}✓ $table${NC}"
            else
                echo -e "  ${YELLOW}⚠ $table (missing)${NC}"
            fi
        done
    fi
    
    echo ""
    echo -e "${CYAN}7. Disk Space${NC}"
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$DISK_USAGE" -lt 80 ]; then
        echo -e "  ${GREEN}✓ Disk usage: ${DISK_USAGE}%${NC}"
    else
        echo -e "  ${YELLOW}⚠ Disk usage: ${DISK_USAGE}% (consider cleanup)${NC}"
    fi
    
    echo ""
    if [ "$HEALTH_OK" = true ]; then
        echo -e "${GREEN}✓ All health checks passed${NC}"
    else
        echo -e "${RED}✗ Some health checks failed${NC}"
        exit 1
    fi
}

# ========================================
# Validate Command (calls validate_pipeline.py)
# ========================================

cmd_validate() {
    show_header "Data Validation"
    
    if [ -f "$PROJECT_ROOT/scripts/utils/validate_pipeline.py" ]; then
        python3 "$PROJECT_ROOT/scripts/utils/validate_pipeline.py"
    else
        echo -e "${RED}Validation script not found${NC}"
        exit 1
    fi
}

# ========================================
# Logs Command
# ========================================

cmd_logs() {
    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" logs -f
}

# ========================================
# Clean Command
# ========================================

cmd_clean() {
    show_header "Cleanup"
    
    cd "$PROJECT_ROOT"
    
    echo -e "${YELLOW}Stopping containers...${NC}"
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    
    echo -e "${YELLOW}Removing stopped containers...${NC}"
    docker container prune -f
    
    echo -e "${YELLOW}Cleaning old logs...${NC}"
    if [ -d "$PROJECT_ROOT/logs" ]; then
        find "$PROJECT_ROOT/logs" -name "*.log" -mtime +7 -delete 2>/dev/null || true
        echo -e "${GREEN}✓ Removed logs older than 7 days${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# ========================================
# DB Command
# ========================================

cmd_db() {
    show_header "Database Connection"
    
    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_NAME=$(get_ssm_param "DB_NAME")
    DB_USER=$(get_ssm_param "DB_USER")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")
    
    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Database credentials not configured${NC}"
        exit 1
    fi
    
    echo "Connecting to: $DB_HOST / $DB_NAME"
    echo "Press Ctrl+D or type '\q' to exit"
    echo ""
    
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME
}

# ========================================
# DB Exec Command
# ========================================

cmd_db_exec() {
    local query_or_file="$2"

    if [ -z "$query_or_file" ]; then
        echo -e "${RED}Error: No SQL command or file provided${NC}"
        echo "Usage: ./platform_manager.sh db-exec \"SELECT 1;\""
        echo "       ./platform_manager.sh db-exec sql/temp/insert_test_prices.sql"
        exit 1
    fi

    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_NAME=$(get_ssm_param "DB_NAME")
    DB_USER=$(get_ssm_param "DB_USER")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")

    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Database credentials not configured${NC}"
        exit 1
    fi

    # Check if it's a file path
    if [ -f "$query_or_file" ]; then
        echo -e "${CYAN}Executing SQL file: $query_or_file${NC}"
        PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f "$query_or_file"
    else
        echo -e "${CYAN}Executing SQL command${NC}"
        PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "$query_or_file"
    fi
}

# ========================================
# Pricing Management Commands
# ========================================

cmd_pricing() {
    local subcommand="$2"

    case $subcommand in
        add)
            cmd_pricing_add
            ;;
        show)
            cmd_pricing_show
            ;;
        clear)
            cmd_pricing_clear
            ;;
        *)
            echo -e "${YELLOW}Pricing Management${NC}"
            echo ""
            echo "Commands:"
            echo "  add    - Add temporary test pricing"
            echo "  show   - Show current pricing configuration"
            echo "  clear  - Clear test pricing data"
            echo ""
            echo "Usage: ./platform_manager.sh pricing [add|show|clear]"
            ;;
    esac
}

cmd_pricing_add() {
    show_header "Adding Test Pricing Data"

    echo -e "${YELLOW}⚠️  WARNING: These are PLACEHOLDER rates for testing only${NC}"
    echo -e "${YELLOW}   Replace with actual contract pricing from PepsiCo${NC}"
    echo ""

    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        return 0
    fi

    SQL_FILE="$PROJECT_ROOT/sql/temp/insert_test_prices.sql"

    if [ ! -f "$SQL_FILE" ]; then
        echo -e "${RED}Error: SQL file not found: $SQL_FILE${NC}"
        exit 1
    fi

    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_NAME=$(get_ssm_param "DB_NAME")
    DB_USER=$(get_ssm_param "DB_USER")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")

    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Database credentials not configured${NC}"
        exit 1
    fi

    echo -e "${CYAN}Inserting test pricing...${NC}"
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f "$SQL_FILE"

    echo ""
    echo -e "${GREEN}✓ Test pricing added successfully${NC}"
    echo ""

    cmd_pricing_show
}

cmd_pricing_show() {
    show_header "Current Pricing Configuration"

    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_NAME=$(get_ssm_param "DB_NAME")
    DB_USER=$(get_ssm_param "DB_USER")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")

    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Database credentials not configured${NC}"
        exit 1
    fi

    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
        SELECT
            c.capability_code,
            p.tier,
            '$' || p.unit_rate::text as rate,
            TO_CHAR(p.start_date, 'YYYY-MM-DD') as effective_date,
            CASE
                WHEN p.end_date IS NULL THEN '(active)'
                ELSE TO_CHAR(p.end_date, 'YYYY-MM-DD')
            END as end_date
        FROM price_config p
        JOIN capabilities_dim c ON p.capability_id = c.capability_id
        ORDER BY c.capability_code, p.tier;
    "
}

cmd_pricing_clear() {
    show_header "Clear Test Pricing Data"

    echo -e "${YELLOW}⚠️  This will delete ALL pricing data from price_config table${NC}"
    echo -e "${YELLOW}   You will need to re-add pricing before running ETL${NC}"
    echo ""

    read -p "Are you sure? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        return 0
    fi

    DB_HOST=$(get_ssm_param "DB_HOST")
    DB_NAME=$(get_ssm_param "DB_NAME")
    DB_USER=$(get_ssm_param "DB_USER")
    DB_PASSWORD=$(get_ssm_param_secure "DB_PASSWORD")

    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Database credentials not configured${NC}"
        exit 1
    fi

    echo -e "${CYAN}Deleting pricing data...${NC}"
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
        DELETE FROM price_config;
        SELECT 'Deleted ' || COUNT(*) || ' price records' FROM price_config;
    "

    echo ""
    echo -e "${GREEN}✓ Test pricing cleared${NC}"
}

# ========================================
# SSM Command
# ========================================

cmd_ssm() {
    show_header "SSM Parameters"

    echo -e "${CYAN}Parameters at: $SSM_PREFIX${NC}"
    echo ""

    aws ssm get-parameters-by-path \
        --path "$SSM_PREFIX" \
        --recursive \
        --region $AWS_REGION \
        --query 'Parameters[*].[Name,Type]' \
        --output table
}

# ========================================
# Main
# ========================================

if [ $# -eq 0 ]; then
    show_usage
    exit 0
fi

COMMAND=$1

case $COMMAND in
    start) cmd_start ;;
    start-auto) cmd_start_auto ;;
    stop) cmd_stop ;;
    restart) cmd_restart ;;
    rebuild) cmd_rebuild ;;
    status) cmd_status ;;
    health) cmd_health ;;
    validate) cmd_validate ;;
    logs) cmd_logs ;;
    clean) cmd_clean ;;
    db) cmd_db ;;
    db-exec) cmd_db_exec "$@" ;;
    pricing) cmd_pricing "$@" ;;
    ssm) cmd_ssm ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac
#!/bin/bash
#
# Analytics Platform Manager
# Consolidated utility for all platform operations
#
# Replaces: daily_startup.sh, daily_teardown.sh, health_check.sh, 
#           verify_setup.sh, teardown_docker_stack.sh
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
${CYAN}Analytics Platform Manager${NC}

${YELLOW}Usage:${NC}
  ./platform_manager.sh [command]

${YELLOW}Commands:${NC}
  ${GREEN}start${NC}      - Start the ETL pipeline
  ${GREEN}stop${NC}       - Stop all containers
  ${GREEN}restart${NC}    - Restart the pipeline
  ${GREEN}status${NC}     - Show system status
  ${GREEN}health${NC}     - Run health checks
  ${GREEN}validate${NC}   - Validate data quality
  ${GREEN}logs${NC}       - Show container logs and follow
  ${GREEN}clean${NC}      - Clean up containers and logs
  ${GREEN}db${NC}         - Connect to database
  ${GREEN}ssm${NC}        - List SSM parameters

${YELLOW}Examples:${NC}
  ./platform_manager.sh start
  ./platform_manager.sh status
  ./platform_manager.sh logs
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
    stop) cmd_stop ;;
    restart) cmd_restart ;;
    status) cmd_status ;;
    health) cmd_health ;;
    validate) cmd_validate ;;
    logs) cmd_logs ;;
    clean) cmd_clean ;;
    db) cmd_db ;;
    ssm) cmd_ssm ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac
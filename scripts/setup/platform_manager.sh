#!/bin/bash
#
# Analytics Platform Manager
# Consolidated script for common operations
#
# Usage: ./platform_manager.sh [command]
# Commands: start, stop, status, health, validate, logs, clean
#

set -e

# Color output
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
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.ec2.yaml"

# Load environment if exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

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
    cat <<EOF
${CYAN}Analytics Platform Manager${NC}

${YELLOW}Usage:${NC}
  ./platform_manager.sh [command]

${YELLOW}Commands:${NC}
  ${GREEN}start${NC}      - Start the ETL pipeline
  ${GREEN}stop${NC}       - Stop all containers
  ${GREEN}restart${NC}    - Restart the pipeline
  ${GREEN}status${NC}     - Show container and database status
  ${GREEN}health${NC}     - Run comprehensive health checks
  ${GREEN}validate${NC}   - Validate data quality
  ${GREEN}logs${NC}       - Show container logs (follow mode)
  ${GREEN}clean${NC}      - Clean up stopped containers and logs
  ${GREEN}db${NC}         - Open database connection
  ${GREEN}ssm${NC}        - List SSM parameters

${YELLOW}Examples:${NC}
  ./platform_manager.sh start
  ./platform_manager.sh status
  ./platform_manager.sh logs

EOF
}

get_db_connection_string() {
    if [ -z "$DB_HOST" ]; then
        DB_HOST=$(aws ssm get-parameter --name "${SSM_PREFIX}/DB_HOST" --region $AWS_REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    fi
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(aws ssm get-parameter --name "${SSM_PREFIX}/DB_PASSWORD" --with-decryption --region $AWS_REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    fi
    DB_NAME="${DB_NAME:-cost_analytics_db}"
    DB_USER="${DB_USER:-etl_analytics}"
}

# ========================================
# Command Functions
# ========================================

cmd_start() {
    show_header "Starting Analytics Pipeline"
    
    cd "$PROJECT_ROOT"
    
    # Check if already running
    if docker compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        echo -e "${YELLOW}Containers already running${NC}"
        read -p "Restart? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cmd_stop
        else
            return 0
        fi
    fi
    
    echo -e "${YELLOW}Building and starting containers...${NC}"
    docker compose -f "$COMPOSE_FILE" up -d --build
    
    echo ""
    echo -e "${GREEN}✓ Pipeline started${NC}"
    echo ""
    echo "View logs with: ./platform_manager.sh logs"
}

cmd_stop() {
    show_header "Stopping Analytics Pipeline"
    
    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" down
    
    echo -e "${GREEN}✓ Pipeline stopped${NC}"
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_status() {
    show_header "Platform Status"
    
    echo -e "${CYAN}Container Status:${NC}"
    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" ps
    
    echo ""
    echo -e "${CYAN}Database Connection:${NC}"
    get_db_connection_string
    
    if [ -n "$DB_HOST" ] && [ -n "$DB_PASSWORD" ]; then
        if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1;" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Connected to: $DB_HOST"
            echo -e "  ${GREEN}✓${NC} Database: $DB_NAME"
            
            # Get table counts
            TABLE_COUNT=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>/dev/null || echo "0")
            echo -e "  ${GREEN}✓${NC} Tables: $TABLE_COUNT"
            
            # Get recent ETL runs
            RECENT_RUNS=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc "SELECT COUNT(*) FROM audit_etl_runs WHERE start_time > NOW() - INTERVAL '24 hours';" 2>/dev/null || echo "0")
            echo -e "  ${GREEN}✓${NC} ETL runs (24h): $RECENT_RUNS"
        else
            echo -e "  ${RED}✗${NC} Cannot connect to database"
        fi
    else
        echo -e "  ${RED}✗${NC} Database credentials not configured"
    fi
    
    echo ""
    echo -e "${CYAN}SSM Parameters:${NC}"
    PARAM_COUNT=$(aws ssm get-parameters-by-path --path "$SSM_PREFIX" --recursive --region $AWS_REGION --query 'length(Parameters)' --output text 2>/dev/null || echo "0")
    echo -e "  Parameters configured: $PARAM_COUNT"
}

cmd_health() {
    show_header "Health Check"
    
    echo -e "${CYAN}1. Docker Status${NC}"
    if command -v docker &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Docker installed: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    else
        echo -e "  ${RED}✗${NC} Docker not installed"
    fi
    
    echo ""
    echo -e "${CYAN}2. AWS CLI Status${NC}"
    if command -v aws &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} AWS CLI installed: $(aws --version | cut -d' ' -f1 | cut -d'/' -f2)"
        
        # Check IAM role
        if aws sts get-caller-identity &>/dev/null; then
            IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
            echo -e "  ${GREEN}✓${NC} IAM role: ${IDENTITY##*/}"
        else
            echo -e "  ${RED}✗${NC} Cannot assume IAM role"
        fi
    else
        echo -e "  ${RED}✗${NC} AWS CLI not installed"
    fi
    
    echo ""
    echo -e "${CYAN}3. Database Connectivity${NC}"
    get_db_connection_string
    
    if [ -n "$DB_HOST" ] && [ -n "$DB_PASSWORD" ]; then
        if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT version();" &>/dev/null; then
            VERSION=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc "SELECT version();" | head -1)
            echo -e "  ${GREEN}✓${NC} Database reachable"
            echo -e "  ${GREEN}✓${NC} PostgreSQL version: $(echo $VERSION | grep -oP 'PostgreSQL \K[0-9.]+')"
        else
            echo -e "  ${RED}✗${NC} Cannot connect to database"
        fi
    else
        echo -e "  ${RED}✗${NC} Database credentials not configured"
    fi
    
    echo ""
    echo -e "${CYAN}4. Required Tables${NC}"
    if [ -n "$DB_HOST" ] && [ -n "$DB_PASSWORD" ]; then
        REQUIRED_TABLES=("audit_etl_runs" "tool_configurations" "appd_applications" "appd_licenses")
        
        for table in "${REQUIRED_TABLES[@]}"; do
            EXISTS=$(PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema='public' AND table_name='$table');" 2>/dev/null || echo "f")
            if [ "$EXISTS" = "t" ]; then
                echo -e "  ${GREEN}✓${NC} $table"
            else
                echo -e "  ${YELLOW}⚠${NC} $table (missing)"
            fi
        done
    fi
    
    echo ""
    echo -e "${CYAN}5. Disk Space${NC}"
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$DISK_USAGE" -lt 80 ]; then
        echo -e "  ${GREEN}✓${NC} Disk usage: ${DISK_USAGE}%"
    else
        echo -e "  ${YELLOW}⚠${NC} Disk usage: ${DISK_USAGE}% (consider cleanup)"
    fi
    
    echo ""
    echo -e "${GREEN}Health check complete${NC}"
}

cmd_validate() {
    show_header "Data Validation"
    
    if [ -f "$PROJECT_ROOT/scripts/utils/validate_pipeline.py" ]; then
        python3 "$PROJECT_ROOT/scripts/utils/validate_pipeline.py"
    else
        echo -e "${YELLOW}Validation script not found${NC}"
    fi
}

cmd_logs() {
    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" logs -f
}

cmd_clean() {
    show_header "Cleanup"
    
    echo -e "${YELLOW}Stopping containers...${NC}"
    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" down
    
    echo -e "${YELLOW}Removing stopped containers...${NC}"
    docker container prune -f
    
    echo -e "${YELLOW}Cleaning old logs...${NC}"
    if [ -d "$PROJECT_ROOT/logs" ]; then
        find "$PROJECT_ROOT/logs" -name "*.log" -mtime +7 -delete
        echo -e "${GREEN}✓${NC} Removed logs older than 7 days"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

cmd_db() {
    show_header "Database Connection"
    
    get_db_connection_string
    
    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Database credentials not configured${NC}"
        exit 1
    fi
    
    echo "Connecting to: $DB_HOST / $DB_NAME"
    echo "Press Ctrl+D or type '\q' to exit"
    echo ""
    
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME
}

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

# Check if command provided
if [ $# -eq 0 ]; then
    show_usage
    exit 0
fi

COMMAND=$1

case $COMMAND in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    status)
        cmd_status
        ;;
    health)
        cmd_health
        ;;
    validate)
        cmd_validate
        ;;
    logs)
        cmd_logs
        ;;
    clean)
        cmd_clean
        ;;
    db)
        cmd_db
        ;;
    ssm)
        cmd_ssm
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac
#!/bin/bash
#
# Diagnose Why ETL Container Crashed
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "======================================================================"
echo "  ETL Container Crash Diagnostics"
echo "======================================================================"
echo ""

# 1. Find the ETL container (even if stopped)
echo -e "${CYAN}[1] Looking for ETL container...${NC}"
CONTAINER_ID=$(docker ps -a --filter "name=etl" --format "{{.ID}}" | head -1)

if [ -z "$CONTAINER_ID" ]; then
    # Try to find by image name
    CONTAINER_ID=$(docker ps -a --filter "ancestor=pepsico-etl" --format "{{.ID}}" | head -1)
fi

if [ -z "$CONTAINER_ID" ]; then
    echo -e "${RED}❌ No ETL container found${NC}"
    echo ""
    echo "Available containers:"
    docker ps -a
    exit 1
fi

CONTAINER_NAME=$(docker ps -a --filter "id=$CONTAINER_ID" --format "{{.Names}}")
CONTAINER_STATUS=$(docker ps -a --filter "id=$CONTAINER_ID" --format "{{.Status}}")
CONTAINER_EXIT_CODE=$(docker inspect $CONTAINER_ID --format='{{.State.ExitCode}}' 2>/dev/null)

echo -e "${GREEN}✓ Found container${NC}"
echo "  ID: $CONTAINER_ID"
echo "  Name: $CONTAINER_NAME"
echo "  Status: $CONTAINER_STATUS"
echo "  Exit Code: $CONTAINER_EXIT_CODE"
echo ""

# 2. Get full container logs
echo -e "${CYAN}[2] Container logs:${NC}"
echo "----------------------------------------------------------------------"
docker logs $CONTAINER_ID 2>&1 | tail -100
echo "----------------------------------------------------------------------"
echo ""

# 3. Decode exit code
echo -e "${CYAN}[3] Exit code analysis:${NC}"
case $CONTAINER_EXIT_CODE in
    0)
        echo -e "  ${GREEN}✓ Exit code 0 - Container completed successfully${NC}"
        echo "  Pipeline may have run and finished quickly"
        ;;
    1)
        echo -e "  ${RED}✗ Exit code 1 - General error${NC}"
        echo "  Common causes:"
        echo "    • Python script error"
        echo "    • Missing credentials"
        echo "    • Database connection failed"
        echo "    • Import error"
        ;;
    125)
        echo -e "  ${RED}✗ Exit code 125 - Docker run error${NC}"
        echo "  Container failed to start properly"
        ;;
    126)
        echo -e "  ${RED}✗ Exit code 126 - Command cannot execute${NC}"
        echo "  Entrypoint or CMD not executable"
        ;;
    127)
        echo -e "  ${RED}✗ Exit code 127 - Command not found${NC}"
        echo "  Python or script path incorrect"
        ;;
    137)
        echo -e "  ${RED}✗ Exit code 137 - Container killed (OOM?)${NC}"
        echo "  Ran out of memory"
        ;;
    139)
        echo -e "  ${RED}✗ Exit code 139 - Segmentation fault${NC}"
        echo "  Binary crashed"
        ;;
    143)
        echo -e "  ${YELLOW}⚠️  Exit code 143 - Terminated by SIGTERM${NC}"
        echo "  Container was stopped manually or by orchestrator"
        ;;
    *)
        echo -e "  ${YELLOW}⚠️  Exit code $CONTAINER_EXIT_CODE - Unknown${NC}"
        ;;
esac
echo ""

# 4. Check container environment variables
echo -e "${CYAN}[4] Checking environment variables (if container still exists):${NC}"
ENV_CHECK=$(docker inspect $CONTAINER_ID --format='{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E "DB_|APPD_|SN_" | grep -v "PASSWORD\|SECRET")

if [ -n "$ENV_CHECK" ]; then
    echo "$ENV_CHECK" | while read line; do
        echo "  $line"
    done
else
    echo -e "  ${YELLOW}⚠️  No environment variables found${NC}"
fi
echo ""

# 5. Check if database is accessible
echo -e "${CYAN}[5] Checking database connectivity:${NC}"
DB_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.ID}}" | head -1)

if [ -n "$DB_CONTAINER" ]; then
    echo -e "  ${GREEN}✓ PostgreSQL container is running${NC}"

    # Try to connect
    DB_STATUS=$(docker exec $DB_CONTAINER pg_isready 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓ Database is accepting connections${NC}"
    else
        echo -e "  ${RED}✗ Database is not ready${NC}"
        echo "  $DB_STATUS"
    fi
else
    echo -e "  ${RED}✗ PostgreSQL container is NOT running${NC}"
    echo "  ETL requires database to be running first"
fi
echo ""

# 6. Recommendations
echo "======================================================================"
echo "  Recommendations"
echo "======================================================================"
echo ""

if [ "$CONTAINER_EXIT_CODE" = "1" ]; then
    echo -e "${YELLOW}Most likely cause: Missing credentials or database connection${NC}"
    echo ""
    echo "To fix:"
    echo "  1. Check your .env file has all required variables:"
    echo "     DB_HOST, DB_NAME, DB_USER, DB_PASSWORD"
    echo "     APPD_CONTROLLERS, APPD_ACCOUNTS, APPD_CLIENT_IDS, APPD_CLIENT_SECRETS"
    echo ""
    echo "  2. Ensure database is running:"
    echo "     docker-compose up -d postgres"
    echo "     sleep 10  # Wait for DB to be ready"
    echo ""
    echo "  3. Test credentials manually:"
    echo "     docker run --rm --env-file .env <your-image> \\"
    echo "       psql -h \$DB_HOST -U \$DB_USER -d \$DB_NAME -c 'SELECT version();'"
    echo ""
    echo "  4. Run ETL with verbose output:"
    echo "     docker run --rm --env-file .env <your-image> \\"
    echo "       python3 scripts/etl/run_pipeline.py"
    echo ""

elif [ "$CONTAINER_EXIT_CODE" = "137" ]; then
    echo -e "${YELLOW}Container ran out of memory${NC}"
    echo ""
    echo "To fix:"
    echo "  1. Check available memory: free -h"
    echo "  2. Increase Docker memory limit"
    echo "  3. Run pipeline phases separately"
    echo ""

elif [ "$CONTAINER_EXIT_CODE" = "0" ]; then
    echo -e "${GREEN}Container completed successfully!${NC}"
    echo ""
    echo "Check the logs above to verify pipeline ran correctly."
    echo "If you expected it to keep running, you may need to add"
    echo "a 'tail -f /dev/null' at the end of your entrypoint."
    echo ""

else
    echo -e "${YELLOW}Unexpected exit code${NC}"
    echo ""
    echo "Review the container logs above for specific error messages."
fi

echo "======================================================================"
echo ""

echo -e "${CYAN}Quick Commands:${NC}"
echo ""
echo "# View full logs:"
echo "docker logs $CONTAINER_NAME"
echo ""
echo "# Restart container:"
echo "docker start $CONTAINER_NAME"
echo ""
echo "# Run interactively for debugging:"
echo "docker run -it --rm --env-file .env <your-image> /bin/bash"
echo ""
echo "# Check docker-compose status:"
echo "docker-compose ps"
echo ""
echo "======================================================================"
echo ""

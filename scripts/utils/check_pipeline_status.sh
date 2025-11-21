#!/bin/bash
#
# Pipeline Status Checker - Diagnose stuck or long-running ETL
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "======================================================================"
echo "  Pipeline Status Check"
echo "======================================================================"
echo ""

# Check for running Python processes
echo -e "${CYAN}[1] Checking for running pipeline processes...${NC}"
RUNNING=$(ps aux | grep -E "python.*pipeline|python.*appd_extract|python.*snow_enrichment|python.*finalize" | grep -v grep)
if [ -z "$RUNNING" ]; then
    echo -e "  ${YELLOW}⚠️  No pipeline processes found running${NC}"
else
    echo -e "  ${GREEN}✓ Pipeline processes found:${NC}"
    echo "$RUNNING" | while read line; do
        echo "    $line"
    done
fi
echo ""

# Check database connections
echo -e "${CYAN}[2] Checking database activity...${NC}"
if command -v psql &> /dev/null; then
    DB_HOST="${DB_HOST:-localhost}"
    DB_NAME="${DB_NAME:-appdynamics_analytics}"
    DB_USER="${DB_USER:-appdynamics_user}"

    # Check active queries
    ACTIVE_QUERIES=$(PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*)
        FROM pg_stat_activity
        WHERE state = 'active'
        AND query NOT LIKE '%pg_stat_activity%'
    " 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo -e "  Active database queries: ${GREEN}$ACTIVE_QUERIES${NC}"

        # Show long-running queries
        echo ""
        echo -e "${CYAN}[3] Long-running queries (>30 seconds):${NC}"
        PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "
            SELECT
                pid,
                now() - query_start AS duration,
                state,
                LEFT(query, 80) AS query
            FROM pg_stat_activity
            WHERE state = 'active'
            AND query NOT LIKE '%pg_stat_activity%'
            AND now() - query_start > interval '30 seconds'
            ORDER BY duration DESC;
        " 2>/dev/null
    else
        echo -e "  ${YELLOW}⚠️  Could not connect to database${NC}"
        echo "  Check DB_HOST, DB_NAME, DB_USER, DB_PASSWORD environment variables"
    fi
else
    echo -e "  ${YELLOW}⚠️  psql not available - skipping database check${NC}"
fi
echo ""

# Check table row counts to see progress
echo -e "${CYAN}[4] Checking data pipeline progress...${NC}"
if command -v psql &> /dev/null && [ -n "$DB_PASSWORD" ]; then
    PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT
            'applications_dim' AS table_name,
            COUNT(*) AS row_count,
            MAX(created_at) AS latest_record
        FROM applications_dim
        UNION ALL
        SELECT
            'license_usage_fact',
            COUNT(*),
            MAX(ts)
        FROM license_usage_fact
        UNION ALL
        SELECT
            'license_cost_fact',
            COUNT(*),
            MAX(ts)
        FROM license_cost_fact
        UNION ALL
        SELECT
            'chargeback_fact',
            COUNT(*),
            MAX(created_at)
        FROM chargeback_fact;
    " 2>/dev/null || echo -e "  ${YELLOW}⚠️  Could not query database${NC}"
else
    echo -e "  ${YELLOW}⚠️  Database credentials not available${NC}"
fi
echo ""

# Check recent log activity
echo -e "${CYAN}[5] Recent log activity (if available)...${NC}"
if [ -f "pipeline.log" ]; then
    echo -e "  ${GREEN}✓ Found pipeline.log${NC}"
    echo "  Last 10 lines:"
    tail -10 pipeline.log | sed 's/^/    /'
elif [ -f "/var/log/etl/pipeline.log" ]; then
    echo -e "  ${GREEN}✓ Found /var/log/etl/pipeline.log${NC}"
    echo "  Last 10 lines:"
    tail -10 /var/log/etl/pipeline.log | sed 's/^/    /'
else
    echo -e "  ${YELLOW}⚠️  No log file found${NC}"
    echo "  Check stdout of running process with: ps aux | grep python"
fi
echo ""

# Check network activity (are we making API calls?)
echo -e "${CYAN}[6] Checking network connections...${NC}"
APPD_CONNECTIONS=$(netstat -an 2>/dev/null | grep -E "appdynamics.com|443.*ESTABLISHED" | wc -l)
if [ $APPD_CONNECTIONS -gt 0 ]; then
    echo -e "  ${GREEN}✓ Active HTTPS connections found: $APPD_CONNECTIONS${NC}"
    echo "  Pipeline is likely making API calls"
else
    echo -e "  ${YELLOW}⚠️  No active HTTPS connections${NC}"
    echo "  Pipeline may be processing data locally or stuck"
fi
echo ""

# Suggest next steps
echo "======================================================================"
echo "  Diagnosis & Recommendations"
echo "======================================================================"
echo ""

if [ -n "$RUNNING" ]; then
    echo -e "${GREEN}Pipeline is running${NC}"
    echo ""
    echo "If it seems stuck:"
    echo "  1. Check the database for long-running queries (see above)"
    echo "  2. Monitor the process with: top -p <PID>"
    echo "  3. Check if it's waiting on API calls (network connections)"
    echo "  4. Review logs for errors or warnings"
    echo ""
    echo "Common reasons for long runtime:"
    echo "  • Large number of applications (100+)"
    echo "  • Generating 12 months of mock data (365 days × apps)"
    echo "  • Slow network/API responses"
    echo "  • Database index creation or materialized view refresh"
    echo ""
    echo "Expected runtime:"
    echo "  • Small deployment (<50 apps): 2-5 minutes"
    echo "  • Medium deployment (50-200 apps): 5-15 minutes"
    echo "  • Large deployment (200+ apps): 15-30 minutes"
else
    echo -e "${YELLOW}No pipeline processes running${NC}"
    echo ""
    echo "Pipeline may have:"
    echo "  • Completed successfully"
    echo "  • Crashed or exited with error"
    echo "  • Not been started yet"
    echo ""
    echo "Check exit status or logs for details"
fi

echo ""
echo "======================================================================"
echo ""

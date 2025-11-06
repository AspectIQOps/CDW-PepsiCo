#!/bin/bash
#
# Project Rename Script - Analytics Platform
# Updates all project files with new naming convention
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Project Rename to Analytics Platform${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Naming convention mappings
declare -A REPLACEMENTS=(
    # Database names
    ["testdb"]="cost_analytics_db"
    ["appd_licensing"]="cost_analytics_db"
    
    # User names
    ["appd_ro"]="etl_analytics"
    
    # SSM paths
    ["/aspectiq/demo"]="/pepsico"
    ["aspectiq/demo"]="pepsico"
    
    # Keep grafana_ro as is (already generic)
)

# Files to update (add more as needed)
FILES_TO_UPDATE=(
    "docker-compose.ec2.yaml"
    "sql/init/*.sql"
    "scripts/etl/*.py"
    "scripts/setup/*.sh"
    "scripts/utils/*.sh"
    "docs/*.md"
    ".env.example"
)

# Backup directory
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"

echo -e "${YELLOW}Creating backup in: ${BACKUP_DIR}${NC}"
mkdir -p "$BACKUP_DIR"

# Function to update a file
update_file() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        return
    fi
    
    echo -e "  Processing: ${file}"
    
    # Create backup
    cp "$file" "$BACKUP_DIR/"
    
    # Apply replacements
    for old in "${!REPLACEMENTS[@]}"; do
        new="${REPLACEMENTS[$old]}"
        sed -i.tmp "s|${old}|${new}|g" "$file"
        rm -f "${file}.tmp"
    done
}

# Process all files
echo -e "${YELLOW}Updating project files...${NC}"
echo ""

for pattern in "${FILES_TO_UPDATE[@]}"; do
    for file in $pattern; do
        if [ -f "$file" ]; then
            update_file "$file"
        fi
    done
done

# Special cases that need manual review
echo ""
echo -e "${YELLOW}Special updates that need attention:${NC}"
echo ""

# Update README or main docs with new naming
if [ -f "README.md" ]; then
    echo -e "  ${BLUE}→ README.md: Update project description${NC}"
fi

# Update docker service names
if [ -f "docker-compose.ec2.yaml" ]; then
    echo -e "  ${BLUE}→ docker-compose.ec2.yaml: Review service names${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Rename Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Backup created in: ${BACKUP_DIR}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review changes: git diff"
echo "2. Update SSM parameters on fresh AWS account"
echo "3. Launch new RDS with database name: cost_analytics_db"
echo "4. Launch new EC2 instance"
echo "5. Test end-to-end deployment"
echo ""
echo -e "${YELLOW}New Configuration:${NC}"
echo "  Database: cost_analytics_db"
echo "  ETL User: etl_analytics"
echo "  SSM Path: /pepsico/*"
echo ""
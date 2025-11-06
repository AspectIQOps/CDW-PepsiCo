#!/bin/bash
#
# Bulk Rename Script
# Performs find-and-replace across all project files
#
# Usage: ./bulk_rename.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Bulk Rename to Analytics Platform${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if we're in project root
if [ ! -f "docker-compose.ec2.yaml" ]; then
    echo -e "${RED}Error: Must run from project root directory${NC}"
    exit 1
fi

# Create backup
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
echo -e "${YELLOW}Creating backup in: ${BACKUP_DIR}${NC}"
mkdir -p "$BACKUP_DIR"

# Backup key files
cp -r sql "$BACKUP_DIR/"
cp -r scripts "$BACKUP_DIR/"
cp docker-compose.ec2.yaml "$BACKUP_DIR/"
cp .env.example "$BACKUP_DIR/" 2>/dev/null || true

echo -e "${GREEN}✓ Backup created${NC}"
echo ""

# Perform replacements
echo -e "${YELLOW}Performing bulk replacements...${NC}"
echo ""

# Function to replace in files
replace_in_files() {
    local old_text="$1"
    local new_text="$2"
    local file_pattern="$3"
    local description="$4"
    
    echo -e "  ${BLUE}→${NC} $description"
    
    find . -type f -name "$file_pattern" \
        ! -path "./.git/*" \
        ! -path "./backup_*/*" \
        ! -path "./__pycache__/*" \
        ! -path "./venv/*" \
        -exec sed -i.bak "s|${old_text}|${new_text}|g" {} \;
    
    # Clean up .bak files
    find . -type f -name "*.bak" -delete
}

# Database name changes
replace_in_files "cost_analytics_db" "cost_analytics_db" "*.yaml" "docker-compose files"
replace_in_files "cost_analytics_db" "cost_analytics_db" "*.yml" "YAML config files"
replace_in_files "cost_analytics_db" "cost_analytics_db" "*.sql" "SQL scripts"
replace_in_files "cost_analytics_db" "cost_analytics_db" "*.py" "Python scripts"
replace_in_files "cost_analytics_db" "cost_analytics_db" "*.sh" "Shell scripts"
replace_in_files "cost_analytics_db" "cost_analytics_db" "*.md" "Documentation"
replace_in_files "cost_analytics_db" "cost_analytics_db" ".env*" "Environment files"

replace_in_files "appd_licensing" "cost_analytics_db" "*.sql" "SQL scripts (alt name)"
replace_in_files "appd_licensing" "cost_analytics_db" "*.py" "Python scripts (alt name)"

# User name changes
replace_in_files "etl_analytics" "etl_analytics" "*.yaml" "docker-compose files"
replace_in_files "etl_analytics" "etl_analytics" "*.yml" "YAML config files"
replace_in_files "etl_analytics" "etl_analytics" "*.sql" "SQL scripts"
replace_in_files "etl_analytics" "etl_analytics" "*.py" "Python scripts"
replace_in_files "etl_analytics" "etl_analytics" "*.sh" "Shell scripts"
replace_in_files "etl_analytics" "etl_analytics" "*.md" "Documentation"
replace_in_files "etl_analytics" "etl_analytics" ".env*" "Environment files"

# SSM path changes
replace_in_files "/pepsico" "/pepsico" "*.yaml" "docker-compose files"
replace_in_files "/pepsico" "/pepsico" "*.yml" "YAML config files"
replace_in_files "/pepsico" "/pepsico" "*.py" "Python scripts"
replace_in_files "/pepsico" "/pepsico" "*.sh" "Shell scripts"
replace_in_files "/pepsico" "/pepsico" "*.md" "Documentation"
replace_in_files "/pepsico" "/pepsico" ".env*" "Environment files"

# SSM path changes (without leading slash)
replace_in_files "pepsico" "pepsico" "*.py" "Python scripts"
replace_in_files "pepsico" "pepsico" "*.sh" "Shell scripts"

# Container name
replace_in_files "pepsico-etl-unified" "pepsico-etl-analytics" "*.yaml" "docker-compose files"

echo ""
echo -e "${GREEN}✓ All replacements complete${NC}"
echo ""

# Show summary
echo -e "${BLUE}Files Modified:${NC}"
echo ""

find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.sql" -o -name "*.py" -o -name "*.sh" -o -name "*.md" -o -name ".env*" \) \
    ! -path "./.git/*" \
    ! -path "./backup_*/*" \
    ! -path "./__pycache__/*" \
    ! -path "./venv/*" \
    -exec echo "  - {}" \;

echo ""
echo -e "${YELLOW}Replacement Summary:${NC}"
echo "  cost_analytics_db → cost_analytics_db"
echo "  appd_licensing → cost_analytics_db"
echo "  etl_analytics → etl_analytics"
echo "  /pepsico → /pepsico"
echo "  pepsico-etl-unified → pepsico-etl-analytics"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Rename Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review changes: git diff"
echo "2. Test Docker build: docker compose -f docker-compose.ec2.yaml build"
echo "3. Commit changes: git add -A && git commit -m 'Rename to analytics platform'"
echo ""
echo -e "${YELLOW}Backup Location:${NC} $BACKUP_DIR"
echo ""
echo -e "${BLUE}To revert changes:${NC}"
echo "  rm -rf sql scripts docker-compose.ec2.yaml .env.example"
echo "  cp -r $BACKUP_DIR/* ."
echo ""
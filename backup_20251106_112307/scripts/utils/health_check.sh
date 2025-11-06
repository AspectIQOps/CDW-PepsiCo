#!/bin/bash
# ==========================================================
# System Health Check
# Verifies Docker, AWS CLI, SSM access, and database connectivity
# ==========================================================

set -e

echo "🏥 PepsiCo ETL Health Check"
echo "================================"

# Check Docker
if docker --version > /dev/null 2>&1; then
    echo "✅ Docker: $(docker --version)"
else
    echo "❌ Docker: Not installed"
    exit 1
fi

# Check Docker Compose
if docker compose version > /dev/null 2>&1; then
    echo "✅ Docker Compose: $(docker compose version)"
else
    echo "❌ Docker Compose: Not installed"
    exit 1
fi

# Check AWS CLI
if aws --version > /dev/null 2>&1; then
    echo "✅ AWS CLI: $(aws --version 2>&1 | head -n1)"
else
    echo "❌ AWS CLI: Not installed"
    exit 1
fi

# Check AWS credentials
if aws sts get-caller-identity > /dev/null 2>&1; then
    CALLER_INFO=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "✅ AWS Credentials: $CALLER_INFO"
else
    echo "❌ AWS Credentials: Not configured or invalid"
    exit 1
fi

# Check SSM access
if aws ssm get-parameter --name "/aspectiq/demo/DB_NAME" --region us-east-2 > /dev/null 2>&1; then
    echo "✅ AWS SSM: Can access /aspectiq/demo/* parameters"
else
    echo "❌ AWS SSM: Cannot access parameters"
    exit 1
fi

# Check database connectivity
DB_HOST=${DB_HOST:-grafana-test-db.cbymoaeqyga6.us-east-2.rds.amazonaws.com}
if nc -zv "$DB_HOST" 5432 2>&1 | grep -q succeeded; then
    echo "✅ Database: Reachable at $DB_HOST:5432"
else
    echo "❌ Database: Cannot reach $DB_HOST:5432"
    exit 1
fi

# Check PostgreSQL client
if psql --version > /dev/null 2>&1; then
    echo "✅ PostgreSQL Client: $(psql --version)"
else
    echo "⚠️  PostgreSQL Client: Not installed (optional)"
fi

echo "================================"
echo "✅ All health checks passed!"
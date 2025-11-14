#!/bin/bash
#
# Run Demo Data Population in Docker Container
#

set -e

cd "$(dirname "$0")/../.."

AWS_REGION="${AWS_REGION:-us-east-2}"

echo "========================================="
echo "Running Demo Data Population (Docker)"
echo "========================================="
echo ""

# Fetch credentials from SSM
echo "Fetching credentials from SSM..."
export DB_HOST=$(aws ssm get-parameter --name /pepsico/DB_HOST --region $AWS_REGION --query 'Parameter.Value' --output text)
export DB_NAME=$(aws ssm get-parameter --name /pepsico/DB_NAME --region $AWS_REGION --query 'Parameter.Value' --output text)
export DB_USER=$(aws ssm get-parameter --name /pepsico/DB_USER --region $AWS_REGION --query 'Parameter.Value' --output text)
export DB_PASSWORD=$(aws ssm get-parameter --name /pepsico/DB_PASSWORD --with-decryption --region $AWS_REGION --query 'Parameter.Value' --output text)

echo "✓ Credentials loaded"
echo ""

# Run in Docker using the ETL image
echo "Running demo data script in Docker container..."
docker run --rm \
  -e DB_HOST="$DB_HOST" \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -v "$(pwd)/scripts:/app/scripts:ro" \
  pepsico-analytics-etl:latest \
  python3 /app/scripts/utils/populate_demo_data.py

echo ""
echo "Done!"

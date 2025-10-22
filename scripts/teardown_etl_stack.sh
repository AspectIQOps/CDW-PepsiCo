#!/bin/bash
set -e

echo "Stopping and removing Docker containers..."
docker compose -f ~/etl_project/docker/docker-compose.yml down || true

echo "Removing Docker images..."
docker images -a | grep 'etl_project\|grafana\|postgres' | awk '{print $3}' | xargs -r docker rmi -f || true

echo "Dropping PostgreSQL database..."
sudo -i -u postgres psql -c "DROP DATABASE IF EXISTS appd_licensing;" || true
sudo -i -u postgres psql -c "DROP ROLE IF EXISTS appd_ro;" || true

echo "Removing Python virtual environment..."
rm -rf ~/etl_env

echo "Removing cloned repo..."
rm -rf ~/etl_project

echo "Cleaning up Docker volumes and networks..."
docker volume prune -f || true
docker network prune -f || true

echo "Teardown complete."

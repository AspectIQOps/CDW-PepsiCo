#!/bin/bash
set -e

# Source environment variables
if [[ -f /opt/appd-licensing/.env ]]; then
  export $(grep -v '^#' /opt/appd-licensing/.env | xargs)
fi

# Start cron
service cron start

# Execute the ETL Python script
python /app/etl/appd_etl.py

# Keep container running
tail -f /dev/null

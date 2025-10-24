#!/bin/bash
set -e

# Optional: activate virtual environment if you prefer venv
# source /app/venv/bin/activate

# Run ETL script
if [ -f "/app/etl/run_etl.py" ]; then
    python /app/etl/run_etl.py
else
    echo "No ETL script found at /app/etl/run_etl.py"
fi

# Start cron in foreground (needed for container to stay alive)
cron -f

FROM python:3.12-slim

# Set working directory to a simple /app (cleaner paths)
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # CRITICAL: aws-cli to fetch secrets from SSM
    aws-cli \
    # CRITICAL: postgresql-client for 'pg_isready' health check in entrypoint
    postgresql-client \
    # Clean up APT cache to keep the image small
    && rm -rf /var/lib/apt/lists/*

# Copy Python requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip
# Use --no-cache-dir to minimize final image size
RUN pip install --no-cache-dir -r requirements.txt

# Copy entrypoint script
COPY docker/etl/entrypoint.sh /app/entrypoint.sh

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Set entrypoint (this script runs BEFORE any Python code)
ENTRYPOINT ["/app/entrypoint.sh"]
# The final CMD (which Python script to run) is set in docker-compose.yaml

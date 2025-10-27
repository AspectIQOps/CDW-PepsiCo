FROM python:3.12-slim

# Set working directory inside the container
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # CRITICAL: postgresql-client for 'pg_isready' health check in entrypoint
    postgresql-client \
    # Clean up APT cache to keep the image small
    && rm -rf /var/lib/apt/lists/*

# FIX: Install the AWS CLI via pip, as the apt package is unavailable in this slim image.
# This provides the 'aws' binary required by entrypoint.sh for SSM secret retrieval.
RUN pip install awscli

# NOTE: Assuming requirements.txt is now at the root of the build context (CDW-PepsiCo/)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application scripts
COPY scripts/etl scripts/etl
COPY docker/etl/entrypoint.sh .

# Make entrypoint executable
RUN chmod +x entrypoint.sh

# Environment setup
ENV PYTHONPATH /app/scripts
ENV ETL_USER devuser

# Default command to run the AppD ETL, the snow ETL will override this
CMD ["./entrypoint.sh", "python", "scripts/etl/appd_etl.py"]

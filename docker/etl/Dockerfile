FROM python:3.12-slim

# Set working directory
WORKDIR /app/etl

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    cron \
    curl \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy Python requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Copy ETL scripts
COPY scripts/ /app/etl

# Copy cron schedule file
COPY docker/etl/etl_cron /etc/cron.d/etl-cron
RUN chmod 0644 /etc/cron.d/etl-cron \
    && crontab /etc/cron.d/etl-cron

# Copy entrypoint
COPY docker/etl/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy .env for licensing/config usage inside container
COPY .env /opt/appd-licensing/.env

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]

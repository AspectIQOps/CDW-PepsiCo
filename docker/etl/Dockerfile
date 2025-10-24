# Base image
FROM python:3.12-slim

# Set working directory
# Copy ETL scripts into container (optional if using volume)
# COPY scripts/ /app/etl

WORKDIR /app/etl

# Install cron and required system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    cron \
    curl \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy Python requirements and install
COPY requirements.txt .
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Copy ETL scripts into container
COPY etl/ /app/etl

# Copy entrypoint script
COPY docker/etl/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy cron schedule file
COPY docker/etl/etl-cron /etc/cron.d/etl-cron
RUN chmod 0644 /etc/cron.d/etl-cron \
    && crontab /etc/cron.d/etl-cron

# Set environment variables for DB connection (can also pass via docker-compose)
ENV POSTGRES_HOST=postgres
ENV POSTGRES_PORT=5432
ENV POSTGRES_DB=mydb
ENV POSTGRES_USER=myuser
ENV POSTGRES_PASSWORD=mypassword
ENV PYTHONUNBUFFERED=1

# Run cron in foreground
CMD ["/entrypoint.sh"]

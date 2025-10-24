CDW-PepsiCo Dockerized ETL Stack

This document outlines how to deploy the CDW-PepsiCo ETL stack using Docker and Docker Compose on a fresh Ubuntu VM.

Table of Contents

Overview

Prerequisites

Deployment Workflow

Accessing Grafana

Maintenance & Updates

Overview

This deployment uses Docker containers to isolate the different components of the ETL stack:

Component	Container/Service
PostgreSQL	postgres:18
ETL Python Scripts	Custom ETL container
Grafana	grafana/grafana:12.2.1

Key features:

Persistent PostgreSQL data

ETL container with future scheduling support

Grafana dashboards connected to PostgreSQL

Prerequisites

Ubuntu 24.04 EC2 instance (or similar)

Security group with:

TCP 3000 open (Grafana UI)

TCP 5432 if external DB access is needed

SSH access to the VM

Git installed locally

Deployment Workflow
1. Connect to your VM
ssh -i /path/to/your-key.pem ubuntu@<public-DNS>

2. Prepare the environment
cd /home/ubuntu/scripts
sudo ./setup_docker_env.sh


This installs Docker, Docker Compose, and system dependencies.

After it completes, log out and back in to refresh Docker group permissions:

exit
ssh -i /path/to/your-key.pem ubuntu@<public-DNS>

3. Clone the repository
git clone https://github.com/AspectIQOps/CDW-PepsiCo.git
cd CDW-PepsiCo


Optionally, check out a specific branch:

git fetch origin dockerization
git checkout dockerization

4. Configure environment variables

Edit .env in the repo root:

nano .env


Add the following values:

DB_USER=<your_postgres_user>
DB_PASSWORD=<your_postgres_password>
DB_NAME=<your_db_name>
SN_INSTANCE=<your_servicenow_instance>
SN_USER=<your_servicenow_user>
SN_PASS=<your_servicenow_password>

5. Deploy the Docker stack
chmod +x scripts/setup_docker_stack.sh
./scripts/setup_docker_stack.sh


Builds and starts Postgres, ETL, and Grafana containers.

6. Verify the deployment
chmod +x docker/docker_install_check.sh
./docker/docker_install_check.sh


Ensure all containers are up and healthy.

Accessing Grafana

Open a browser and navigate to:

http://<public-DNS>:3000


Login credentials (default):

Username: admin
Password: admin


You will be prompted to change the password on first login.

Maintenance & Updates

To update the stack:

cd CDW-PepsiCo
git fetch origin
git checkout dockerization
git pull origin dockerization
docker compose build
docker compose up -d


To stop the stack:

docker compose down


To view logs:

docker compose logs -f
🧭 ETL Stack Deployment Runbook (VM-Based)
1️⃣ Prerequisites

AWS EC2 instance:

OS: Ubuntu 24.04 LTS or later (tested on 25.04)

Instance type: t3.medium or larger

Security group:

Allow TCP 22 (SSH)

Allow TCP 3000 (Grafana UI)

IAM role or user with permissions to pull from GitHub (if private)

SSH key for access (e.g. your-key.pem)

2️⃣ Create and Configure the VM
# Launch EC2 instance via AWS console or CLI
# (use the correct key pair and security group)

# SSH into the instance
ssh -i /path/to/your-key.pem ubuntu@<EC2_PUBLIC_DNS>


3️⃣ Clone the Repository
git clone https://github.com/AspectIQOps/CDW-PepsiCo.git
cd CDW-PepsiCo

4️⃣ Configure Environment Variables

Create or edit the .env file in the project root.
Example .env template:

# PostgreSQL
POSTGRES_USER=db_user
POSTGRES_PASSWORD=db_password
POSTGRES_DB=db_name
POSTGRES_PORT=5432

# ETL Python venv path
ETL_VENV=/opt/appd-licensing/etl_env

# Grafana defaults
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASS=admin


⚠️ The .env is used by setup_etl_stack.sh. Adjust credentials or ports as needed before running the setup.

5️⃣ Run Setup Script
cd scripts
chmod +x setup_etl_stack.sh
sudo ./setup_etl_stack.sh


This will:

Install required dependencies (PostgreSQL, Python, Grafana)

Initialize PostgreSQL cluster

Create and seed the appd_licensing database

Set up ETL Python virtual environment

Configure and enable Grafana service

Perform service enablement and autostart configuration

6️⃣ Post-Install Health Check

Run:

sudo ./scripts/post_install_check.sh


Expected output:

✅ PostgreSQL service is active
✅ Grafana service is active
✅ DB connection OK
🎉 ETL stack post-install check complete!


Then open Grafana in your browser:

http://<EC2_PUBLIC_IP>:3000


(default credentials: admin/admin)

7️⃣ Snapshot the Working VM

After successful verification:

In AWS Console → Create Image (AMI) from this EC2 instance
Name: appd-licensing-base-v1

This snapshot becomes your gold image for future container builds or new environments.

8️⃣ Containerization Roadmap (Next Phase)

We’ll break the stack into 3 services:

Component	Purpose	Container Base	Notes
PostgreSQL	Persistent data store	postgres:16	Mount volume for /var/lib/postgresql/data
ETL Python	ETL scripts + scheduler	python:3.11-slim	Copy scripts + .env; use cron or Airflow later
Grafana	Dashboard UI	grafana/grafana:latest	Use environment vars for provisioning dashboards

Plan for next phase:

Write Dockerfile for the ETL component.

Create a docker-compose.yml that ties together Postgres, ETL, and Grafana.

Map the .env file to each container via env_file: directive.

Use volume mounts for persistent data and logs.

Add healthchecks to each container for orchestration readiness.

9️⃣ Maintenance / Rerun Notes

To reseed data:

sudo -u postgres psql -d appd_licensing -f /tmp/seed_all_tables.sql


To check logs:

sudo journalctl -u postgresql
sudo journalctl -u grafana-server


To uninstall stack completely:

sudo ./scripts/teardown_etl_stack.sh

✅ Summary
Step	Description	Status
VM Build	Ubuntu 24.04+ EC2 instance	✅
Environment Config	.env populated	✅
Stack Setup	setup_etl_stack.sh	✅
Health Check	post_install_check.sh	✅
Snapshot	AMI saved	⏳ next
Containerization	Define Dockerfiles & Compose	🔜 upcoming
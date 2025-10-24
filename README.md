# CDW-PepsiCo Project
# AppDynamics Licensing ETL Stack

## Overview

This repository contains scripts and configuration to set up a full ETL stack for AppDynamics licensing data, including:

- **PostgreSQL** database with schema and seed data  
- **Python** virtual environment for ETL scripts  
- **Grafana** for dashboards and visualization  
- ETL scripts to process AppDynamics licensing data  

The stack is designed to be installed on Ubuntu EC2 instances, with reproducible configuration through scripts and `.env` files.

---

## Repository Structure

CDW-PepsiCo/
├── scripts/
│ ├── setup_etl_stack.sh # Main installation script
│ ├── post_install_check.sh # Health check script
│ ├── snow_etl.py # Snowflake ETL script
│ └── appd_etl.py # Main AppDynamics ETL script
├── postgres/
│ └── seed_all_tables.sql # SQL seed script for DB
├── .env # Environment variables (not committed with sensitive data)
├── requirements.txt # Python dependencies
└── README.md

---

## Environment Variables (`.env`)

The `.env` file provides database credentials and connection information. Example:

# PostgreSQL
POSTGRES_USER=etl_user
POSTGRES_PASSWORD=change_me
POSTGRES_DB=etl_db
POSTGRES_PORT=5432

# Grafana Cloud / API
GRAFANA_API_KEY=your_grafana_api_key_here
GRAFANA_CLOUD_ORG=your_org_name
GRAFANA_CLOUD_URL=https://your-instance.grafana.net

# AppDynamics
APPD_CLIENT_ID=your_appd_client_id
APPD_CLIENT_SECRET=your_appd_client_secret
APPD_URL=https://example.saas.appdynamics.com

# ServiceNow
SNOW_INSTANCE=your_instance.service-now.com
SNOW_USERNAME=your_username
SNOW_PASSWORD=your_password
Note: The .env file should not be committed to the repository if it contains sensitive credentials.

Installation
Clone the repository:

bash
Copy code
git clone <repo_url>
cd CDW-PepsiCo
Create .env file in the repo root with your database credentials.

Run the setup script:

bash
Copy code
sudo ./scripts/setup_etl_stack.sh
This will:

Update system packages

Install PostgreSQL, Python, and required tools

Set up the PostgreSQL cluster, schema, and tables

Seed the database

Create a Python virtual environment and install dependencies

Install and start Grafana

Post-Install Checks
Run the post-install health check script to verify the environment:

bash
Copy code
sudo ./scripts/post_install_check.sh
Checks include:

.env file presence and permissions

Kernel update/reboot requirements

PostgreSQL service status

Database tables and row counts

Grafana service status

Python virtual environment and DB connectivity

Python Virtual Environment
Activate the environment to run ETL scripts:

source /opt/appd-licensing/etl_env/bin/activate

Install Python dependencies from requirements.txt (if updating):

pip install -r requirements.txt

#Running ETL Scripts
Activate the virtual environment:
source /opt/appd-licensing/etl_env/bin/activate

Run your ETL script, for example:
python ./scripts/snow_etl.py
or
python ./scripts/appd_etl.py

#Grafana
Grafana is installed on port 3000. Default credentials:

URL: http://<EC2_PUBLIC_IP>:3000
Username: admin
Password: admin

Configure your dashboards to visualize licensing data.

Notes & Best Practices
Commit all scripts and configuration (scripts/, postgres/, requirements.txt) to version control.

.env files should be managed securely and not committed with sensitive credentials.

Seed scripts and schema updates should be versioned alongside ETL scripts.

The system is designed to be rerunnable on a clean Ubuntu instance or containerized environment for reproducibility.
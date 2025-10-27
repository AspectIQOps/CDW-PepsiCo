# Repository Cleanup Guide

## 🎯 Goal
Streamline the repository to only essential files for production deployment.

## 📁 Current Repository Structure

```
CDW-PepsiCo/
├── .env                              ✅ KEEP (not in git)
├── .env.example                      ✅ CREATE (template)
├── .gitignore                        ✅ KEEP
├── README.md                         ✅ KEEP/UPDATE
├── docker-compose.yaml               ✅ KEEP
├── requirements.txt                  ✅ KEEP
│
├── config/
│   ├── grafana/
│   │   ├── dashboards/               ✅ KEEP (empty for now)
│   │   ├── datasources/
│   │   │   └── postgres.yaml         ✅ KEEP
│   │   └── provisioning/             🗑️ REMOVE (not used)
│   └── logging/                      🗑️ REMOVE (not used)
│
├── docker/
│   ├── etl/
│   │   ├── Dockerfile                ✅ KEEP
│   │   └── entrypoint.sh             ✅ KEEP
│   ├── grafana/                      🗑️ REMOVE (using stock image)
│   └── postgres/                     🗑️ REMOVE (using stock image)
│
├── scripts/
│   ├── etl/
│   │   ├── snow_etl.py               ✅ KEEP
│   │   ├── appd_etl.py               ✅ KEEP
│   │   └── etl_utils.py              ⚠️  EVALUATE (keep if used)
│   ├── setup/
│   │   ├── setup_docker_env.sh       ✅ KEEP
│   │   └── setup_docker_stack.sh     ✅ KEEP
│   └── utils/
│       ├── verify_setup.sh           ✅ KEEP
│       ├── post_install_check.sh     ⚠️  EVALUATE
│       └── teardown_docker_stack.sh  ✅ KEEP
│
├── sql/
│   └── init/
│       ├── 01_create_tables.sql      ✅ KEEP
│       ├── 02_seed_dimensions.sql    ✅ KEEP
│       └── 03_seed_tables.sql        🗑️ REMOVE (test data)
│
└── docs/
    ├── SoW.md                         ✅ KEEP
    ├── SETUP_INSTRUCTIONS.md          ✅ KEEP
    ├── SQL_FILE_ORDER.md              ✅ KEEP
    └── ETL Stack Deployment (VM-based).md  🗑️ ARCHIVE (old approach)
```

## 🧹 Cleanup Commands

```bash
cd ~/CDW-PepsiCo

# Remove unused directories
rm -rf config/grafana/provisioning
rm -rf config/logging
rm -rf docker/grafana
rm -rf docker/postgres

# Remove test data
rm -f sql/init/03_seed_tables.sql

# Archive old documentation
mkdir -p archive
mv "docs/ETL Stack Deployment (VM-based).md" archive/ 2>/dev/null || true

# Remove old datasource format if exists
rm -f config/grafana/datasources/appd_postgres_datasource.json

# Check for unused files
ls -la scripts/etl/etl_utils.py
ls -la scripts/utils/post_install_check.sh

# If those files aren't referenced anywhere, you can remove them:
# rm scripts/etl/etl_utils.py
# rm scripts/utils/post_install_check.sh
```

## ✅ Final Clean Structure

```
CDW-PepsiCo/
├── .env                          # Your secrets (gitignored)
├── .env.example                  # Template for others
├── .gitignore                   
├── README.md                     # Main documentation
├── docker-compose.yaml          
├── requirements.txt             
│
├── config/
│   └── grafana/
│       ├── dashboards/           # Future dashboards
│       └── datasources/
│           └── postgres.yaml     # DB connection
│
├── docker/
│   └── etl/
│       ├── Dockerfile           
│       └── entrypoint.sh        
│
├── scripts/
│   ├── etl/
│   │   ├── snow_etl.py          # ServiceNow integration
│   │   └── appd_etl.py          # AppDynamics integration
│   ├── setup/
│   │   ├── setup_docker_env.sh  # First-time VM setup
│   │   └── setup_docker_stack.sh # Deploy stack
│   └── utils/
│       ├── verify_setup.sh      # Health checks
│       └── teardown_docker_stack.sh # Cleanup script
│
├── sql/
│   └── init/
│       ├── 01_create_tables.sql      # Schema
│       └── 02_seed_dimensions.sql    # Defaults
│
└── docs/
    ├── SoW.md                    # Statement of Work
    ├── SETUP_INSTRUCTIONS.md     # Detailed setup guide
    └── SQL_FILE_ORDER.md         # SQL execution order
```

## 📝 Create Missing Files

### .env.example

```bash
cat > .env.example << 'EOF'
#AppDynamics - Leave empty to use AWS SSM
APPD_CONTROLLER=
APPD_ACCOUNT=
APPD_CLIENT_ID=
APPD_CLIENT_SECRET=

#ServiceNow - Leave empty to use AWS SSM
SN_INSTANCE=
SN_USER=
SN_PASS=

#Database - Leave empty to use AWS SSM (triggers SSM mode)
DB_HOST=postgres
DB_PORT=5432
DB_NAME=
DB_USER=
DB_PASSWORD=

#AWS Configuration
SSM_PATH=/aspectiq/demo
AWS_REGION=us-east-2
TZ=America/New_York
EOF
```

## 🎯 Verification

After cleanup, verify structure:

```bash
tree -L 3 -I '__pycache__|*.pyc|.git' ~/CDW-PepsiCo
```

Expected output: Clean, organized structure with only essential files.

## 📋 Checklist

- [ ] Removed unused directories
- [ ] Created .env.example
- [ ] Created utility scripts
- [ ] Updated README.md
- [ ] Archived old documentation
- [ ] Verified all scripts are executable
- [ ] Tested deployment with clean setup
- [ ] Committed changes to git

## 🚀 After Cleanup

Test the cleaned repository:

```bash
# Clean slate
docker compose down -v

# Deploy
./scripts/setup/setup_docker_stack.sh

# Verify
./scripts/utils/verify_setup.sh

# Run ETL
docker compose run --rm etl_snow
```
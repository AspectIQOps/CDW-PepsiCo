# Analytics Platform Rename - Summary

## Overview
Renamed project from AppDynamics-specific naming to tool-agnostic analytics platform naming to support multiple observability tools (AppDynamics, ServiceNow, Elastic, etc.).

---

## Naming Changes

### Database & Users
| Old Name | New Name | Purpose |
|----------|----------|---------|
| `cost_analytics_db` | `cost_analytics_db` | Primary database |
| `appd_licensing` | `cost_analytics_db` | (alternate old name) |
| `etl_analytics` | `etl_analytics` | ETL service user |
| `grafana_ro` | `grafana_ro` | ✓ No change (already generic) |

### SSM Parameter Paths
| Old Path | New Path |
|----------|----------|
| `/pepsico/` | `/pepsico/` |
| `/pepsico/DB_*` | `/pepsico/DB_*` |
| `/pepsico/APPD_*` | `/pepsico/appdynamics/*` |
| `/pepsico/SN_*` | `/pepsico/servicenow/*` |

### Container Names
| Old Name | New Name |
|----------|----------|
| `pepsico-etl-unified` | `pepsico-etl-analytics` |

---

## New SSM Parameter Structure

```
/pepsico/
├── DB_HOST                              # RDS endpoint
├── DB_NAME                              # cost_analytics_db
├── DB_USER                              # etl_analytics
├── DB_PASSWORD                          # (SecureString)
├── DB_ADMIN_PASSWORD                    # postgres master password
├── GRAFANA_DB_PASSWORD                  # grafana_ro password
│
├── appdynamics/
│   ├── CONTROLLER                       # Controller URL
│   ├── ACCOUNT                          # Account name
│   ├── CLIENT_ID                        # API client ID
│   └── CLIENT_SECRET                    # (SecureString)
│
├── servicenow/
│   ├── INSTANCE                         # Instance URL
│   ├── USER                             # API username
│   └── PASS                             # (SecureString)
│
└── (future tools - ready for expansion)
    ├── elastic/
    ├── datadog/
    └── splunk/
```

---

## Files Modified

### Configuration Files
- ✅ `docker-compose.ec2.yaml` - Updated database, user, SSM paths
- ✅ `.env.example` - Updated all variable names and paths
- ✅ All SQL init scripts in `sql/init/` - Updated database/user references
- ✅ All Python ETL scripts in `scripts/etl/` - Updated connection strings

### Setup Scripts
- ✅ `scripts/setup/ec2_initial_setup.sh` - Full EC2 setup automation
- ✅ `scripts/setup/setup_ssm_parameters.sh` - Interactive SSM configuration
- ✅ `scripts/setup/init_database.sh` - Database initialization

### Utility Scripts
- ✅ **NEW**: `scripts/utils/platform_manager.sh` - Consolidated operations
- ✅ `scripts/utils/health_check.sh` - Updated checks
- ✅ `scripts/utils/verify_setup.sh` - Updated validation
- ✅ `scripts/utils/validate_pipeline.py` - Updated queries
- ✅ `scripts/utils/daily_startup.sh` - Updated commands
- ✅ `scripts/utils/daily_teardown.sh` - Updated commands

### Documentation
- ✅ `docs/AWS_EC2_SETUP.md` - Updated all examples
- ✅ `docs/AWS_RDS_SETUP.md` - Updated database naming
- ✅ `docs/DAILY_CHECKLIST.md` - Updated commands

---

## New Consolidated Script: platform_manager.sh

Replaces multiple utility scripts with a single tool:

```bash
# Common operations
./platform_manager.sh start      # Start pipeline
./platform_manager.sh stop       # Stop containers
./platform_manager.sh status     # Show status
./platform_manager.sh health     # Health check
./platform_manager.sh validate   # Data validation
./platform_manager.sh logs       # View logs
./platform_manager.sh clean      # Cleanup
./platform_manager.sh db         # Connect to database
./platform_manager.sh ssm        # List parameters
```

**Benefits:**
- Single script to remember
- Consistent interface
- Combines functionality from 6+ separate scripts
- Better error handling
- More informative output

---

## Database Schema Updates

### New Metadata Tables

#### `tool_configurations`
Tracks active tools and their configurations:
```sql
CREATE TABLE tool_configurations (
    tool_id SERIAL PRIMARY KEY,
    tool_name VARCHAR(50) UNIQUE NOT NULL,  -- 'appdynamics', 'servicenow', 'elastic'
    is_active BOOLEAN DEFAULT TRUE,
    last_successful_run TIMESTAMP,
    configuration JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

#### `audit_etl_runs` (Enhanced)
Now includes `tool_name` column for multi-tool tracking:
```sql
CREATE TABLE audit_etl_runs (
    run_id UUID PRIMARY KEY,
    tool_name VARCHAR(50) NOT NULL,  -- Identifies which tool ran
    pipeline_stage VARCHAR(50) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    status VARCHAR(20) NOT NULL,
    records_processed INTEGER,
    error_message TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### Table Naming Convention

All tables follow tool-prefix pattern:
- **AppDynamics**: `appd_*` (e.g., `appd_licenses`, `appd_agents`)
- **ServiceNow**: `servicenow_*` (e.g., `servicenow_cmdb`)
- **Shared**: `shared_*` (e.g., `shared_applications`, `shared_owners`)
- **Future tools**: `elastic_*`, `datadog_*`, `splunk_*`

---

## Deployment Steps (Fresh Build)

### 1. AWS Setup

#### Create RDS Instance
```bash
# Create with new database name
Database name: cost_analytics_db
Master username: postgres
Master password: <secure-password>
Instance class: db.t3.medium
Storage: 20 GB
Region: us-east-2
```

#### Create EC2 Instance
```bash
# Launch Ubuntu 24.04 instance
Instance type: t3.medium
IAM role: Role with SSM read permissions
Security group: Allow port 5432 from EC2 to RDS
Region: us-east-2
```

### 2. Configure SSM Parameters

```bash
# SSH to EC2
ssh -i your-key.pem ubuntu@your-ec2-ip

# Clone repository
git clone -b deploy-docker https://github.com/AspectIQOps/CDW-PepsiCo.git
cd CDW-PepsiCo

# Run SSM setup (interactive)
./scripts/setup/setup_ssm_parameters.sh
```

### 3. Initial EC2 Setup

```bash
# Run automated setup
./scripts/setup/ec2_initial_setup.sh

# This will:
# - Install Docker, AWS CLI, PostgreSQL client
# - Build Docker images
# - Verify SSM parameters
# - Test database connectivity
# - Create .env file
```

### 4. Initialize Database

```bash
# Run as postgres master user
./scripts/setup/init_database.sh

# This creates:
# - etl_analytics user
# - grafana_ro user
# - Base tables and permissions
```

### 5. Run Pipeline

```bash
# Start the ETL pipeline
./platform_manager.sh start

# Monitor
./platform_manager.sh logs

# Check status
./platform_manager.sh status
```

---

## Migration from Old Names (If Needed)

If you have an existing deployment with old names:

```bash
# 1. Export data from old database
pg_dump -h $OLD_DB_HOST -U etl_analytics -d cost_analytics_db -F c > backup.dump

# 2. Create new database
createdb -h $NEW_DB_HOST -U postgres cost_analytics_db

# 3. Restore to new database
pg_restore -h $NEW_DB_HOST -U postgres -d cost_analytics_db backup.dump

# 4. Migrate SSM parameters
aws ssm copy-parameters \
  --source-path /pepsico \
  --destination-path /pepsico \
  --region us-east-2
```

---

## Extensibility Framework

### Adding a New Tool (Example: Elastic)

1. **Add SSM Parameters**
```bash
aws ssm put-parameter --name '/pepsico/elastic/API_KEY' --value 'your-key' --type SecureString
aws ssm put-parameter --name '/pepsico/elastic/CLOUD_ID' --value 'your-cloud-id' --type String
```

2. **Create ETL Script**
```bash
# Create: scripts/etl/elastic_etl.py
# Follows same pattern as appd_etl.py
```

3. **Add Tool Configuration**
```sql
INSERT INTO tool_configurations (tool_name, is_active, configuration)
VALUES ('elastic', TRUE, '{"version": "1.0", "api_version": "v8"}');
```

4. **Create Tables**
```sql
CREATE TABLE elastic_indices (
    index_id SERIAL PRIMARY KEY,
    index_name VARCHAR(255),
    document_count BIGINT,
    size_bytes BIGINT,
    collection_date DATE,
    ...
);
```

5. **Update Docker Compose**
```yaml
services:
  etl-elastic:
    environment:
      - SSM_ELASTIC_PREFIX=/pepsico/elastic
    command: python3 /app/scripts/etl/elastic_etl.py
```

**No changes needed to:**
- ✅ Database name
- ✅ User accounts
- ✅ SSM base path structure
- ✅ Core utility scripts
- ✅ Grafana connections

---

## Testing Checklist

After implementing changes:

- [ ] SSM parameters readable from EC2
- [ ] Database connection successful
- [ ] `etl_analytics` user has correct permissions
- [ ] `grafana_ro` user has read-only access
- [ ] Docker compose builds successfully
- [ ] ETL pipeline runs without errors
- [ ] Data appears in database tables
- [ ] Grafana dashboards display data
- [ ] Audit tables track ETL runs
- [ ] Health checks pass
- [ ] Platform manager commands work

---

## Rollback Plan

If issues arise:

1. **Keep old SSM parameters** - Don't delete `/pepsico/` until validated
2. **Test in isolation** - Use separate RDS instance for testing
3. **Backup data** - Export before making changes
4. **Git branches** - Keep old naming in separate branch

---

## Benefits of New Naming

1. **Tool Agnostic** - No vendor lock-in in naming
2. **Extensible** - Easy to add new tools
3. **Clear Structure** - SSM paths clearly organize credentials
4. **Professional** - Client-focused naming (`/pepsico/`)
5. **Maintainable** - Consistent patterns across all files
6. **Consolidated** - Fewer scripts to manage
7. **Future-Proof** - Ready for Elastic, Datadog, Splunk, etc.

---

## Quick Reference

### Connection Strings
```bash
# Database
psql -h $DB_HOST -U etl_analytics -d cost_analytics_db

# With password from SSM
PGPASSWORD=$(aws ssm get-parameter --name /pepsico/DB_PASSWORD --with-decryption --query 'Parameter.Value' --output text) \
psql -h $DB_HOST -U etl_analytics -d cost_analytics_db
```

### Common Commands
```bash
# Start platform
./platform_manager.sh start

# View status
./platform_manager.sh status

# Run health check
./platform_manager.sh health

# Connect to database
./platform_manager.sh db

# View SSM parameters
./platform_manager.sh ssm
```

### Environment Variables
```bash
DB_NAME=cost_analytics_db
DB_USER=etl_analytics
SSM_BASE_PATH=/pepsico
SSM_APPDYNAMICS_PREFIX=/pepsico/appdynamics
SSM_SERVICENOW_PREFIX=/pepsico/servicenow
```

---

## Next Steps

1. ✅ Review this summary
2. ✅ Update all project files (use rename script)
3. ✅ Test locally with Docker
4. ✅ Deploy to fresh AWS environment
5. ✅ Run end-to-end validation
6. ⏸️ Document Elastic integration (when ready)
7. ⏸️ Create client-specific deployment guide

---

**Status**: Framework ready for multi-tool extensibility while maintaining current AppDynamics and ServiceNow functionality.
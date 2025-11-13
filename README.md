# Analytics Platform - Multi-Tool Cost & Usage Analytics

> **Enterprise observability cost management platform**  
> Currently supporting: AppDynamics, ServiceNow  
> Extensible to: Elastic, Datadog, Splunk, New Relic, and more

---

## Overview

The Analytics Platform is a tool-agnostic cost and usage analytics solution designed for enterprise observability tools. It extracts data from multiple sources, transforms it into a unified data model, and provides actionable insights through interactive dashboards.

### Current Features
- 📊 **AppDynamics License Analytics** - Track licenses, agents, usage patterns
- 🔄 **ServiceNow CMDB Integration** - Application ownership and metadata
- 💰 **Cost Forecasting** - Predict future spend based on historical trends
- 📈 **Grafana Dashboards** - Interactive visualization and reporting
- 🔐 **Secure Credential Management** - AWS SSM Parameter Store integration
- 🐳 **Containerized Deployment** - Docker-based for easy deployment

### Extensibility Framework
Built with a tool-agnostic architecture ready to integrate:
- **Elastic** - Log analytics and search costs
- **Datadog** - Infrastructure monitoring usage
- **Splunk** - Log management and analytics
- **Dynatrace** - Application performance monitoring
- **New Relic** - Full-stack observability

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Data Sources                          │
├─────────────────────────────────────────────────────────┤
│  AppDynamics API  │  ServiceNow API  │  Future Tools    │
└──────────┬──────────────────┬───────────────────────────┘
           │                  │
           ▼                  ▼
    ┌──────────────────────────────┐
    │   ETL Pipeline (Docker)      │
    │                              │
    │  • Extract from APIs         │
    │  • Transform & Enrich        │
    │  • Load to PostgreSQL        │
    │  • Validate Data Quality     │
    └──────────┬───────────────────┘
               │
               ▼
    ┌─────────────────────────────┐
    │  PostgreSQL Database        │
    │  (cost_analytics_db)        │
    │                             │
    │  • AppD Usage/Cost Tables   │
    │  • ServiceNow CMDB Data     │
    │  • Cross-Tool Analytics     │
    │  • Audit & Metadata         │
    └──────────┬──────────────────┘
               │
               ▼
    ┌─────────────────────────────┐
    │   Grafana Dashboards        │
    │                             │
    │  • License Utilization      │
    │  • Cost Trends              │
    │  • Forecasts                │
    │  • Application Breakdown    │
    └─────────────────────────────┘
```

---

## Quick Start

### Prerequisites
- AWS account (EC2, RDS, SSM)
- Docker installed
- PostgreSQL client
- AWS CLI configured

### 1. Clone Repository
```bash
git clone -b deploy-docker https://github.com/AspectIQOps/CDW-PepsiCo.git
cd CDW-PepsiCo
```

### 2. Deploy to AWS
```bash
# Run on EC2 instance
./scripts/setup/ec2_initial_setup.sh
./scripts/setup/setup_ssm_parameters.sh
./scripts/setup/init_database.sh
```

### 3. Start Pipeline
```bash
./scripts/utils/platform_manager.sh start
```

📖 **See [QUICKSTART.md](QUICKSTART.md) for detailed deployment guide**

---

## Configuration

### Database
- **Name**: `cost_analytics_db`
- **Users**: 
  - `etl_analytics` - ETL pipeline operations
  - `grafana_ro` - Dashboard read-only access

### SSM Parameter Structure
```
/pepsico/
├── DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
├── appdynamics/
│   ├── CONTROLLER
│   ├── ACCOUNT
│   ├── CLIENT_NAME
│   └── CLIENT_SECRET
├── servicenow/
│   ├── INSTANCE
│   ├── USER
│   └── PASS
└── (future tools)/
```

### Environment Variables
```bash
DB_NAME=cost_analytics_db
DB_USER=etl_analytics
AWS_REGION=us-east-2
SSM_BASE_PATH=/pepsico
```

---

## Usage

### Platform Management

```bash
# Start pipeline
./scripts/utils/platform_manager.sh start

# Check status
./scripts/utils/platform_manager.sh status

# View logs
./scripts/utils/platform_manager.sh logs

# Run health check
./scripts/utils/platform_manager.sh health

# Validate data
./scripts/utils/platform_manager.sh validate

# Stop pipeline
./scripts/utils/platform_manager.sh stop
```

### Database Access

```bash
# Connect via platform manager
./scripts/utils/platform_manager.sh db

# Or manually
PGPASSWORD=$(aws ssm get-parameter --name /pepsico/DB_PASSWORD --with-decryption --query 'Parameter.Value' --output text --region us-east-2) \
psql -h YOUR_RDS_ENDPOINT -U etl_analytics -d cost_analytics_db
```

---

## Project Structure

```
CDW-PepsiCo/
├── scripts/
│   ├── setup/              # Initial deployment scripts
│   │   ├── ec2_initial_setup.sh
│   │   ├── setup_ssm_parameters.sh
│   │   └── init_database.sh
│   │
│   ├── etl/                # ETL pipeline code
│   │   ├── run_pipeline.py
│   │   ├── appd_etl.py
│   │   └── servicenow_etl.py
│   │
│   └── utils/              # Operational utilities
│       ├── platform_manager.sh     # Main management tool
│       ├── health_check.sh
│       ├── verify_setup.sh
│       └── validate_pipeline.py
│
├── sql/
│   └── init/               # Database schema
│       ├── 01_init_users_and_schema.sql
│       ├── 02_create_appd_tables.sql
│       └── 03_create_servicenow_tables.sql
│
├── docs/                   # Documentation
│   ├── QUICKSTART.md       # ⭐ Start here
│   ├── AWS_EC2_SETUP.md
│   ├── AWS_RDS_SETUP.md
│   └── RENAME_SUMMARY.md
│
├── docker-compose.ec2.yaml # Container orchestration
├── Dockerfile              # Container build
└── .env.example            # Environment template
```

---

## Key Features

### 🔄 Multi-Tool Support
- Tool-agnostic data model
- Separate ETL pipelines per tool
- Unified analytics across tools
- Easy to add new integrations

### 📊 AppDynamics Integration
- License usage tracking
- Agent inventory
- Cost allocation by application
- Forecasting and trends

### 🗂️ ServiceNow CMDB
- Application metadata
- Ownership information
- Sector/capability mapping
- Cross-reference with usage data

### 🔐 Security
- No hardcoded credentials
- AWS SSM Parameter Store
- IAM role-based access
- Read-only dashboard user

### 📈 Analytics
- Historical trend analysis
- Cost forecasting
- Usage pattern detection
- Anomaly identification

---

## Data Model

### Core Tables

#### Tool Configurations
```sql
tool_configurations
├── tool_name (appdynamics, servicenow, elastic, etc.)
├── is_active
├── last_successful_run
└── configuration (JSONB)
```

#### Audit Trail
```sql
audit_etl_runs
├── run_id (UUID)
├── tool_name
├── pipeline_stage
├── start_time / end_time
├── status
└── metadata (JSONB)
```

#### AppDynamics Tables
- `appd_applications` - Application catalog
- `appd_licenses` - License inventory
- `appd_agents` - Agent inventory
- `appd_usage_daily` - Daily usage metrics
- `appd_cost_forecasts` - Projected costs

#### ServiceNow Tables
- `servicenow_cmdb` - CMDB records
- Ownership and metadata

---

## Extending the Platform

### Adding a New Tool

1. **Create SSM Parameters**
```bash
aws ssm put-parameter --name /pepsico/newtool/API_KEY --value 'your-key' --type SecureString
```

2. **Add Tool Configuration**
```sql
INSERT INTO tool_configurations (tool_name, is_active)
VALUES ('newtool', TRUE);
```

3. **Create ETL Script**
```python
# scripts/etl/newtool_etl.py
# Follow pattern from appd_etl.py
```

4. **Create Tables**
```sql
-- sql/init/XX_create_newtool_tables.sql
CREATE TABLE newtool_data (...);
```

5. **Update Docker Compose**
```yaml
services:
  etl-newtool:
    environment:
      - SSM_NEWTOOL_PREFIX=/pepsico/newtool
```

📖 **See [RENAME_SUMMARY.md](docs/RENAME_SUMMARY.md) for detailed extensibility guide**

---

## Monitoring & Operations

### Health Checks
```bash
# Comprehensive health check
./scripts/utils/platform_manager.sh health

# Check individual components
- Docker status
- AWS IAM role
- Database connectivity
- Required tables
- Disk space
```

### Data Validation
```bash
# Run data quality checks
./scripts/utils/platform_manager.sh validate

# Validates:
- Record counts
- Data freshness
- Completeness
- Referential integrity
```

### Logs
```bash
# Live logs
./scripts/utils/platform_manager.sh logs

# Logs location
./logs/etl_YYYYMMDD_HHMMSS.log
```

---

## Cost Optimization

### Daily Runtime (8-10 hours)
- EC2 t3.medium: ~$0.35/day
- RDS db.t3.medium: ~$0.60/day
- **Total: ~$1.00/day** (~$30/month)

### Cost-Saving Tips
```bash
# Stop when not in use
./scripts/utils/platform_manager.sh stop

# Stop RDS instance
aws rds stop-db-instance --db-instance-identifier your-db --region us-east-2

# Use reserved instances for production
# Schedule ETL runs for off-peak hours
```

---

## Troubleshooting

### Common Issues

**Database Connection Failed**
```bash
# Check security group allows EC2 → RDS
# Verify credentials in SSM
./scripts/utils/platform_manager.sh health
```

**SSM Parameters Not Found**
```bash
# List parameters
./scripts/utils/platform_manager.sh ssm

# Verify IAM role has SSM read permissions
aws sts get-caller-identity
```

**Docker Build Fails**
```bash
# Rebuild without cache
docker compose -f docker-compose.ec2.yaml build --no-cache

# Check logs
docker compose -f docker-compose.ec2.yaml logs
```

---

## Development

### Local Development
```bash
# Use mock data
export USE_MOCK_DATA=true

# Run locally
python3 scripts/etl/run_pipeline.py

# Run tests
pytest tests/
```

### Adding Features
1. Create feature branch
2. Update ETL scripts
3. Add SQL migrations
4. Update documentation
5. Test end-to-end
6. Submit PR

---

## Documentation

- 📘 [Quick Start Guide](QUICKSTART.md) - Get up and running
- 📗 [EC2 Setup Guide](docs/AWS_EC2_SETUP.md) - Detailed EC2 configuration
- 📙 [RDS Setup Guide](docs/AWS_RDS_SETUP.md) - Detailed RDS configuration
- 📕 [Rename Summary](docs/RENAME_SUMMARY.md) - Architecture and extensibility
- 📓 [Daily Checklist](docs/DAILY_CHECKLIST.md) - Daily operations

---

## Contributing

This is currently a private repository for PepsiCo's internal use. If you have access and want to contribute:

1. Follow the development workflow above
2. Maintain consistent naming conventions
3. Update documentation for any changes
4. Test thoroughly before committing

---

## License

Proprietary - PepsiCo Internal Use Only

---

## Support

For issues or questions:
1. Check documentation in `docs/`
2. Review troubleshooting section above
3. Run health checks: `./scripts/utils/platform_manager.sh health`
4. Contact: AspectIQ Operations Team

---

## Technology Stack

- **Language**: Python 3.11+
- **Database**: PostgreSQL 16.3
- **Container**: Docker & Docker Compose
- **Cloud**: AWS (EC2, RDS, SSM)
- **Orchestration**: Custom ETL pipeline
- **Visualization**: Grafana
- **APIs**: AppDynamics REST API, ServiceNow REST API

---

## Roadmap

### Current Phase (Q4 2024)
- ✅ AppDynamics integration
- ✅ ServiceNow CMDB integration
- ✅ Cost forecasting
- ✅ Grafana dashboards

### Next Phase (Q1 2025)
- ⏳ Elastic integration
- ⏳ Enhanced forecasting models
- ⏳ Automated alerting
- ⏳ API endpoints for external access

### Future Phases
- 🔮 Datadog integration
- 🔮 Splunk integration
- 🔮 Machine learning for anomaly detection
- 🔮 Self-service dashboard builder

---
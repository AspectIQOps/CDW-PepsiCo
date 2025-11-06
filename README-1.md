# PepsiCo AppDynamics Cost Analytics

ETL pipeline for AppDynamics licensing cost tracking, forecasting, and chargeback with ServiceNow CMDB integration.

## Quick Start

### Full Daily Setup (from scratch)
```bash
./scripts/setup/daily_startup.sh
```

### Manual ETL Run Only
```bash
docker compose -f docker-compose.ec2.yaml up
```

### Daily Teardown
```bash
./scripts/utils/daily_teardown.sh
```

## Directory Structure
```
├── docker/                  # Container definitions
├── scripts/
│   ├── etl/                # ETL pipeline scripts
│   ├── setup/              # One-time & daily setup
│   └── utils/              # Operational utilities
├── sql/init/               # Database initialization
├── config/                 # Configuration files
│   ├── AWS/               # AWS setup documentation
│   └── grafana/           # Grafana dashboards
├── docs/                   # Documentation
└── archive/                # Deprecated files
```

## Utility Scripts

| Script | Purpose |
|--------|---------|
| `health_check.sh` | Verify system health |
| `validate_pipeline.py` | Validate ETL data quality |
| `verify_setup.sh` | Check database setup |
| `teardown_docker_stack.sh` | Stop Docker containers |
| `daily_startup.sh` | Complete daily setup |
| `daily_teardown.sh` | Daily shutdown routine |

## Requirements

- Docker & Docker Compose
- AWS CLI with SSM access
- PostgreSQL client (psql)
- Python 3.12+

## AWS Resources

- **EC2**: Ubuntu instance with IAM role `aspectiq-demo-role`
- **RDS**: PostgreSQL database
- **SSM**: Parameters at `/pepsico/*`

See `config/AWS/` for detailed setup instructions.

## Documentation

- `docs/technical_architecture.md` - System design
- `docs/data_dictionary.md` - Database schema reference
- `docs/operations_runbook.md` - Operational procedures
- `docs/quick_reference.md` - Common commands

## Grafana Dashboards

Located in `config/grafana/dashboards/`:
- Executive Overview
- Cost Analytics
- Peak vs Pro Analysis
- Usage by License Type
- Trends & Forecasts
- Allocation & Chargeback
- Architecture Analysis
- Admin Panel
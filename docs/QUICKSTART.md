# Analytics Platform - Quick Start Guide

## Fresh Deployment (Recommended Path)

### Prerequisites
- AWS account with permissions for EC2, RDS, SSM
- GitHub repository access
- Basic understanding of Docker and PostgreSQL

---


## Step 2: Create AWS Resources (15 minutes)

### A. Launch RDS PostgreSQL

```bash
# Via AWS Console or CLI
aws rds create-db-instance \
  --db-instance-identifier pepsico-analytics-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 17.6 \
  --master-username postgres \
  --master-user-password "postgrespassword" \
  --allocated-storage 10 \
  --storage-type gp2 \
  --db-name cost_analytics_db \
  --vpc-security-group-ids sg-04bcb80f17d14777d \
  --region us-east-2 \
  --publicly-accessible \
  --no-multi-az \
  --backup-retention-period 0 \
  --no-deletion-protection
```

**Save the endpoint:** `pepsico-analytics-db.xxxxxxxxxx.us-east-2.rds.amazonaws.com`

### B. Launch EC2 Ubuntu Instance

```bash
# Via AWS Console or CLI
aws ec2 run-instances \
  --image-id ami-0ea3c35c5c3284d82 \
  --instance-type t3.micro \
  --iam-instance-profile Name=aspectiq-demo-role \
  --security-group-ids sg-04bcb80f17d14777d \
  --region us-east-2 \
  --key-name aws-test-key \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=\"pepsico-analytics\"}]" \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp2,DeleteOnTermination=true}"
```

### C. Configure Security Group

```bash
# Allow EC2 to access RDS on port 5432
aws ec2 authorize-security-group-ingress \
  --group-id sg-04bcb80f17d14777d \
  --protocol tcp \
  --port 5432 \
  --source-group sg-04bcb80f17d14777d \
  --region us-east-2
```

---

## Step 3: Configure SSM Parameters (10 minutes)

```bash
# SSH to EC2
ssh -i your-key.pem ubuntu@YOUR-EC2-IP

# Clone repository
git clone -b deploy-docker https://github.com/AspectIQOps/CDW-PepsiCo.git
cd CDW-PepsiCo

# Run interactive SSM setup
chmod +x scripts/setup/setup_ssm_parameters.sh
./scripts/setup/setup_ssm_parameters.sh
```

**You'll be prompted for:**
- RDS endpoint
- Database credentials
- AppDynamics API credentials
- ServiceNow credentials

**Result:** Parameters created at `/pepsico/*`

---

## Step 4: Initial EC2 Setup (15 minutes)

```bash
# Still on EC2, run automated setup
chmod +x scripts/setup/ec2_initial_setup.sh
sudo ./scripts/setup/ec2_initial_setup.sh
```

**What this installs:**
- Docker & Docker Compose
- AWS CLI
- PostgreSQL client
- Python dependencies
- Builds Docker images
- Verifies SSM access
- Tests database connectivity

---

## Step 5: Initialize Database (5 minutes)

```bash
# Run database initialization
chmod +x scripts/setup/init_database.sh
./scripts/setup/init_database.sh
```

**What this creates:**
- Users: `etl_analytics`, `grafana_ro`
- Base tables: `audit_etl_runs`, `tool_configurations`
- Permissions and grants
- Extensions: `uuid-ossp`, `pg_trgm`

---

## Step 6: Run ETL Pipeline (5 minutes)

```bash
# Make platform manager executable
chmod +x scripts/utils/platform_manager.sh

# Start the pipeline
./scripts/utils/platform_manager.sh start

# Monitor logs
./scripts/utils/platform_manager.sh logs
```

**Watch for:**
- ✓ AppDynamics API connection
- ✓ ServiceNow API connection
- ✓ Data extraction
- ✓ Data transformation
- ✓ Database loading

---

## Step 7: Verify Deployment (5 minutes)

```bash
# Check platform status
./scripts/utils/platform_manager.sh status

# Run health check
./scripts/utils/platform_manager.sh health

# Validate data
./scripts/utils/platform_manager.sh validate

# Connect to database
./scripts/utils/platform_manager.sh db
```

---

## Total Time: ~1 hour

---

## Common Commands Reference

### Daily Operations

```bash
# Start pipeline
./scripts/utils/platform_manager.sh start

# Stop pipeline
./scripts/utils/platform_manager.sh stop

# Restart
./scripts/utils/platform_manager.sh restart

# View logs (live)
./scripts/utils/platform_manager.sh logs
```

### Monitoring

```bash
# Platform status
./scripts/utils/platform_manager.sh status

# Health check
./scripts/utils/platform_manager.sh health

# Data validation
./scripts/utils/platform_manager.sh validate
```

### Database Access

```bash
# Connect to database
./scripts/utils/platform_manager.sh db

# Or manually
PGPASSWORD=$(aws ssm get-parameter --name /pepsico/DB_PASSWORD --with-decryption --query 'Parameter.Value' --output text --region us-east-2) \
psql -h YOUR_RDS_ENDPOINT -U etl_analytics -d cost_analytics_db
```

### SSM Parameters

```bash
# List all parameters
./scripts/utils/platform_manager.sh ssm

# Get specific parameter
aws ssm get-parameter --name /pepsico/DB_HOST --region us-east-2

# Get secure parameter
aws ssm get-parameter --name /pepsico/DB_PASSWORD --with-decryption --region us-east-2
```

---

## Troubleshooting

### Database Connection Issues

```bash
# Test connectivity
./scripts/utils/platform_manager.sh health

# Check security group
aws ec2 describe-security-groups --group-ids sg-XXXXXXXXX --region us-east-2

# Verify SSM parameters
aws ssm get-parameters-by-path --path /pepsico --recursive --region us-east-2
```

### Docker Issues

```bash
# Rebuild image
docker compose -f docker-compose.ec2.yaml build --no-cache

# View logs
docker compose -f docker-compose.ec2.yaml logs

# Check container status
docker ps -a
```

### SSM Access Issues

```bash
# Verify IAM role
aws sts get-caller-identity

# Test SSM access
aws ssm get-parameter --name /pepsico/DB_HOST --region us-east-2
```

---

## Configuration Files

### Key Files to Review

- **docker-compose.ec2.yaml** - Container configuration
- **.env** - Environment variables (auto-generated)
- **sql/init/*.sql** - Database schema
- **scripts/etl/*.py** - ETL pipeline code

### Environment Variables

```bash
# Database
DB_HOST=your-rds-endpoint.us-east-2.rds.amazonaws.com
DB_NAME=cost_analytics_db
DB_USER=etl_analytics
DB_PASSWORD=<from-ssm>

# AWS
AWS_REGION=us-east-2
SSM_BASE_PATH=/pepsico

# Tools
SSM_APPDYNAMICS_PREFIX=/pepsico/appdynamics
SSM_SERVICENOW_PREFIX=/pepsico/servicenow
```

---

## Directory Structure

```
CDW-PepsiCo/
├── docker-compose.ec2.yaml      # Container orchestration
├── Dockerfile                   # Container build
├── .env                         # Environment config (auto-generated)
├── .env.example                 # Environment template
│
├── scripts/
│   ├── setup/
│   │   ├── ec2_initial_setup.sh       # EC2 automation
│   │   ├── setup_ssm_parameters.sh    # SSM configuration
│   │   └── init_database.sh           # Database init
│   │
│   ├── etl/
│   │   ├── run_pipeline.py            # Main orchestrator
│   │   ├── appd_etl.py                # AppDynamics ETL
│   │   └── servicenow_etl.py          # ServiceNow ETL
│   │
│   └── utils/
│       ├── platform_manager.sh        # ⭐ Main utility
│       ├── health_check.sh
│       ├── verify_setup.sh
│       └── validate_pipeline.py
│
├── sql/
│   └── init/
│       ├── 01_init_users_and_schema.sql
│       ├── 02_create_appd_tables.sql
│       └── 03_create_servicenow_tables.sql
│
└── docs/
    ├── AWS_EC2_SETUP.md
    ├── AWS_RDS_SETUP.md
    ├── QUICKSTART.md                  # ⭐ This file
    └── RENAME_SUMMARY.md
```

---

## Cost Estimates

### Daily Runtime (8-10 hours)
- EC2 t3.medium: ~$0.35/day
- RDS db.t3.medium: ~$0.60/day
- **Total: ~$1.00/day**

### Monthly Estimate
- **~$30/month** for 8-10 hours/day usage

### Cost Optimization
```bash
# Stop instances when not in use
./scripts/utils/platform_manager.sh stop

# Stop RDS (manual in console)
aws rds stop-db-instance --db-instance-identifier pepsico-analytics-db --region us-east-2
```

---

## Next Steps After Deployment

1. **Configure Grafana** - Connect to `cost_analytics_db` with `grafana_ro` user
2. **Schedule ETL** - Set up cron job or use AWS EventBridge
3. **Add Monitoring** - CloudWatch alarms for ETL failures
4. **Backup Strategy** - Enable RDS automated backups
5. **Documentation** - Update client-specific procedures

---

## Adding New Tools (Future)

### Example: Adding Elastic

1. **Add SSM parameters**
```bash
aws ssm put-parameter --name /pepsico/elastic/API_KEY --value 'your-key' --type SecureString --region us-east-2
```

2. **Create ETL script**
```bash
# Create: scripts/etl/elastic_etl.py
# Follow pattern from appd_etl.py
```

3. **Add to database**
```sql
INSERT INTO tool_configurations (tool_name, is_active)
VALUES ('elastic', TRUE);

CREATE TABLE elastic_indices (...);
```

4. **Update docker-compose**
```yaml
services:
  etl-elastic:
    environment:
      - SSM_ELASTIC_PREFIX=/pepsico/elastic
```

**Framework is ready!** No changes needed to database name, users, or core structure.

---

## Support

### Documentation
- `docs/AWS_EC2_SETUP.md` - Detailed EC2 setup
- `docs/AWS_RDS_SETUP.md` - Detailed RDS setup
- `docs/RENAME_SUMMARY.md` - Complete naming changes

### Scripts Help
```bash
# View all commands
./scripts/utils/platform_manager.sh

# Get help on any script
./scripts/setup/ec2_initial_setup.sh --help
```

---

## Success Criteria

✅ All health checks pass  
✅ ETL pipeline runs without errors  
✅ Data appears in database tables  
✅ Grafana can connect and query data  
✅ Platform manager commands work  
✅ SSM parameters are accessible  
✅ No hardcoded credentials in code  

---

**You're ready to go!** 🚀
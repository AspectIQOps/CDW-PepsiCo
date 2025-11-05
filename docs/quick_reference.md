# Quick Reference - PepsiCo AppDynamics Licensing

## 🔗 Important Links

- **Grafana Cloud:** https://aspectiq.grafana.net/
- **Cloudflare Dashboard:** https://one.dash.cloudflare.com/
- **AWS Console:** https://console.aws.amazon.com/
- **GitHub Repo:** [Your repo URL]

---

## 🗄️ Database Connection

**RDS Endpoint:** `your-endpoint.us-east-1.rds.amazonaws.com`
**Database:** `appd_licensing`
**User (ETL):** `appd_ro`
**User (Grafana):** `grafana_cloud`
**Port:** `5432`

---

## 📊 Dashboard UIDs

| Dashboard | UID |
|-----------|-----|
| Executive Overview | `pepsico-executive-overview` |
| Usage by License Type | `pepsico-usage-by-license` |
| Cost Analytics | `pepsico-cost-analytics` |
| Peak vs Pro Analysis | `pepsico-peak-pro-analysis` |
| Architecture Analysis | `pepsico-architecture-analysis` |
| Trends & Forecasts | `pepsico-trends-forecasts` |
| Allocation & Chargeback | `pepsico-allocation-chargeback` |
| Admin Panel | `pepsico-admin-panel` |

---

## 🔐 Secrets Location

**Current:** Manual environment variables
**Phase 3:** AWS Systems Manager Parameter Store
**SSM Path:** `/aspectiq/demo/`

---

## 🐳 Docker Commands

```bash
# Start local stack (Phase 1 - deprecated)
docker-compose up -d

# View logs
docker logs pepsico-postgres

# Connect to database
docker exec -it pepsico-postgres psql -U appd_ro -d appd_licensing

# Stop stack
docker-compose down

📅 Data Coverage
Start Date: July 30, 2025
End Date: October 28, 2025
Total Days: 91 days
Applications: 40 total (6 monitored)
Capabilities: APM, MRUM

🚨 Troubleshooting
Grafana Not Showing Data
Check time range (must be July 30 - Oct 28, 2025)
Verify RDS connection in data source settings
Test query in Explore tab
ETL Fails
Check environment variables are set
Verify RDS endpoint is correct
Check AWS credentials
Review script output for errors
Dashboard Import Fails
Ensure PostgreSQL data source named correctly
Check data source UID matches
Verify JSON is valid

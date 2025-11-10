# AppDynamics API Requirements

## Overview

Based on the SoW Section 2.4.1, this document outlines the AppDynamics API endpoints and data required for the ETL pipeline.

## Required Data from AppDynamics

### 1. License Usage Metrics (Primary Data Source)

**Endpoint:** `/controller/licensing/usage`

**Data Needed:**
- License consumption by type (APM, RUM, Synthetic, DB)
- Peak vs. Pro tier attribution
- Time-series usage data (daily/hourly granularity)
- License allocation by application
- Node count and consumption metrics

**SoW Requirements Met:**
- Section 2.1: License Coverage & Analytics
- Section 2.2: Cost Analysis & Financial Management
- Section 2.3: Trend Analysis & Forecasting

### 2. Application Configuration

**Endpoint:** `/controller/rest/applications?output=JSON`

**Data Needed:**
- Application ID and name
- Application description
- Tier information
- Custom properties and tags
- Application owner metadata

**SoW Requirements Met:**
- Section 2.1: Per-application license consumption
- Section 2.4.1: Application tags and custom properties

### 3. Application Tiers

**Endpoint:** `/controller/rest/applications/{app-id}/tiers?output=JSON`

**Data Needed:**
- Tier names and IDs
- Tier type (e.g., Java, .NET, Node.js)
- Agent count per tier
- Tier-level metrics

**SoW Requirements Met:**
- Section 2.1: Tier-based reporting and trends
- Section 2.4.1: Application, tier, node, and server configuration

### 4. Nodes and Servers

**Endpoint:** `/controller/rest/applications/{app-id}/nodes?output=JSON`

**Data Needed:**
- Node names and IDs
- Machine agent details
- Node health status
- Node tier assignment

**SoW Requirements Met:**
- Section 2.1: Node and server level tracking
- Section 2.4.1: Node configuration details

### 5. Peak vs. Pro Attribution

**Critical Requirement from SoW Section 2.1:**

> Peak vs. Pro Usage Differentiation:
> - Application-level attribution
> - Cost implications analysis
> - Optimization opportunity identification
> - Tier-based reporting and trends

**Implementation Strategy:**

**Option 1: Use Application Tags** (Preferred)
- Tag applications with "license-tier: peak" or "license-tier: pro"
- Query: `/controller/rest/applications?output=JSON` and parse tags

**Option 2: Use Custom Properties**
- Set custom property "LicenseTier" on each application
- Retrieve via application metadata

**Option 3: License Usage API**
- Check if `/controller/licensing/usage` includes tier metadata
- Parse license allocation details

**Option 4: Heuristic Analysis**
- Analyze usage patterns to infer Peak vs. Pro
- Based on feature usage (e.g., Peak has Business Transactions, custom dashboards)

**Client Action Required:**
- Confirm which approach is feasible in their environment
- If tagging: Ensure applications are tagged with license tier
- Provide metadata mapping for Peak vs. Pro identification

### 6. Architectural Pattern Classification

**SoW Section 2.1 Requirement:**

> Monolith vs. Microservices Categorization:
> - Architectural pattern classification
> - Roll-up reporting by architecture type
> - License efficiency analysis by pattern
> - Transformation impact tracking

**Implementation Strategy:**

**Option 1: Application Tags**
- Tag: "architecture: monolith" or "architecture: microservices"

**Option 2: Tier Count Heuristic**
- Monolith: 1-3 tiers
- Microservices: 4+ tiers or multiple independent applications

**Option 3: Service Naming Conventions**
- Pattern matching on application/tier names
- E.g., "-svc-", "-api-", "-service-" indicates microservices

**Option 4: Manual Classification**
- Populate in database via admin UI
- Maintain in `architecture_dim` table

**Client Action Required:**
- Preferred classification method
- If tagging: Implement architecture tags
- If heuristic: Validate rules against current applications

## Authentication

### OAuth 2.0 Client Credentials Flow

**Token Endpoint:** `/controller/api/oauth/access_token`

**Request:**
```bash
curl -X POST "https://${CONTROLLER}/controller/api/oauth/access_token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${CLIENT_ID}@${ACCOUNT}&client_secret=${CLIENT_SECRET}"
```

**Response:**
```json
{
  "access_token": "eyJraWQiOiI...",
  "expires_in": 300
}
```

**Usage:**
```bash
curl "https://${CONTROLLER}/controller/rest/applications?output=JSON" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

**Note:** Token expires in 5 minutes - implement token caching and refresh logic

## ETL Implementation Plan

### Phase 1: Basic Integration (Implemented)
- [x] OAuth authentication with token caching
- [x] Application list retrieval
- [ ] License usage data extraction (pending CLIENT_ID)

### Phase 2: Enhanced Metadata
- [ ] Tier and node data collection
- [ ] Custom properties and tags parsing
- [ ] Peak vs. Pro attribution logic
- [ ] Architectural pattern classification

### Phase 3: Historical Data
- [ ] Time-series usage metrics (90 days)
- [ ] Trend analysis
- [ ] Baseline establishment

## Data Model Mapping

### AppDynamics → Database Schema

**applications_dim:**
```sql
appd_application_id    <- Application ID
appd_application_name  <- Application Name
architecture_id        <- Derived from tier count or tags
license_tier          <- "Peak" or "Pro" (from tags/properties)
```

**license_usage_fact:**
```sql
ts                    <- Usage timestamp
app_id                <- Foreign key to applications_dim
capability_id         <- License type (APM, RUM, etc.)
tier                  <- Peak or Pro
units_consumed        <- Usage units
nodes_count           <- Node count
```

**license_cost_fact:**
```sql
ts                    <- Cost timestamp
app_id                <- Foreign key to applications_dim
capability_id         <- License type
tier                  <- Peak or Pro
usd_cost             <- Calculated cost (usage × price)
```

## Rate Limiting

AppDynamics APIs have rate limits:
- Default: 100 requests per minute
- Token refresh: 5-minute expiry
- Implement exponential backoff on 429 errors

**Implementation:**
```python
import time
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

retry_strategy = Retry(
    total=3,
    backoff_factor=2,
    status_forcelist=[429, 500, 502, 503, 504]
)
```

## Data Quality Checks

### Required Validations:
1. **License Data Completeness**
   - All applications have usage data
   - No negative usage values
   - Usage within expected ranges

2. **Peak vs. Pro Attribution**
   - Every application classified as Peak or Pro
   - Default to Pro if uncertain (conservative costing)
   - Alert on unclassified applications

3. **Architecture Classification**
   - All applications have architecture type
   - Validate against known patterns
   - Manual review queue for ambiguous cases

4. **Node Count Consistency**
   - Node count matches license consumption
   - Alert on discrepancies >10%

## Testing Checklist

Before going live with real AppDynamics data:

- [ ] OAuth token successfully obtained
- [ ] Applications list retrieved
- [ ] License usage data parsed correctly
- [ ] Peak vs. Pro logic validated
- [ ] Architecture classification accurate (sample of 10 apps)
- [ ] Cost calculations match manual spreadsheet
- [ ] Historical data loaded (90 days minimum)
- [ ] Data reconciliation with ServiceNow >95%
- [ ] Performance: Full ETL completes within 30 minutes

## Client Deliverables Needed

### Immediate (Blocking ETL Development)
1. **CLIENT_ID** for "License Dashboard Client Key" API client
2. Confirmation that OAuth client has permissions for:
   - `/controller/licensing/usage`
   - `/controller/rest/applications`
   - `/controller/rest/applications/{id}/tiers`
   - `/controller/rest/applications/{id}/nodes`

### Short-term (For Peak/Pro Attribution)
3. Strategy for identifying Peak vs. Pro:
   - Application tags? (requires tagging implementation)
   - Custom properties? (requires property setup)
   - License usage metadata? (need API documentation)
   - Manual mapping? (need initial classification spreadsheet)

### Short-term (For Architecture Classification)
4. Strategy for Monolith vs. Microservices:
   - Application tags?
   - Tier count heuristic validation
   - Manual classification list

### Before Production
5. Validate sample data against known applications
6. Provide test scenarios for UAT
7. Sign off on cost calculation methodology

## References

- AppDynamics REST API Documentation: https://docs.appdynamics.com/
- SoW Section 2.4.1: AppDynamics Integration
- SoW Section 2.1: License Coverage & Analytics
- Current test credentials in SSM: `/pepsico/appdynamics/*`

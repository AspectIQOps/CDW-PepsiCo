#!/usr/bin/env python3
"""
Populate Demo Data - Generate realistic data for client demonstration

Creates:
- 50+ applications across 3 controllers
- 6 months of historical usage and cost data
- ServiceNow CMDB enrichment data
- Chargeback records with H-codes
- Forecast data
- Architecture classifications (Monolith/Microservices)
- Peak vs Pro license distribution

This provides complete data for all 8 SOW-required dashboards.
"""
import psycopg2
import os
import sys
from datetime import datetime, timedelta
import random
from decimal import Decimal

# Database credentials from environment
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

# Demo data configuration
CONTROLLERS = [
    'pepsi-test.saas.appdynamics.com',
    'pepsico-nonprod.saas.appdynamics.com',
    'pepsicoeu-test.saas.appdynamics.com'
]

SECTORS = [
    'Finance', 'Supply Chain', 'Sales', 'IT Operations',
    'Corporate/Shared Services', 'Global IT', 'Manufacturing'
]

OWNERS = [
    ('John Smith', 'john.smith@pepsico.com', 'IT Operations'),
    ('Sarah Johnson', 'sarah.johnson@pepsico.com', 'Finance'),
    ('Mike Chen', 'mike.chen@pepsico.com', 'Supply Chain'),
    ('Lisa Anderson', 'lisa.anderson@pepsico.com', 'Sales'),
    ('David Martinez', 'david.martinez@pepsico.com', 'Global IT'),
]

H_CODES = [
    '1234567890',  # Finance
    '2345678901',  # Supply Chain
    '3456789012',  # Sales
    '4567890123',  # IT Operations
    '5678901234',  # Corporate Services
    '6789012345',  # Global IT
    '7890123456',  # Manufacturing
]

ARCHITECTURES = ['Monolithic', 'Microservices', 'Serverless', 'Legacy']

APP_NAMES = [
    'Customer Portal', 'Order Management', 'Inventory System', 'Billing Engine',
    'CRM Platform', 'Supply Chain Hub', 'Analytics Dashboard', 'Mobile App Backend',
    'Payment Gateway', 'Warehouse Management', 'Sales Force Automation', 'ERP System',
    'Marketing Automation', 'Customer Service Portal', 'Product Catalog',
    'Shipping Tracker', 'Returns Processing', 'Loyalty Program', 'Procurement System',
    'Asset Management', 'HR Portal', 'Expense Management', 'Time Tracking',
    'Document Management', 'Collaboration Suite', 'Email Gateway', 'API Gateway',
    'Data Warehouse', 'Business Intelligence', 'Machine Learning Pipeline',
    'IoT Platform', 'Edge Computing', 'Cloud Migration Tool', 'Security Monitor',
    'Compliance Dashboard', 'Audit System', 'Identity Management', 'Access Control',
    'Network Monitor', 'Application Firewall', 'Load Balancer', 'Cache Service',
    'Message Queue', 'Event Bus', 'Workflow Engine', 'Notification Service',
    'Search Engine', 'Recommendation Engine', 'Fraud Detection', 'Risk Analysis'
]

CAPABILITIES = ['APM', 'MRUM', 'BRUM', 'ANALYTICS', 'INFRA']
TIERS = ['Peak', 'Pro']

def get_conn():
    """Connect to database"""
    return psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

def clear_existing_data(conn):
    """Clear existing data (optional - for clean demo)"""
    print("🗑️  Clearing existing data...")
    cursor = conn.cursor()

    tables = [
        'forecast_fact',
        'chargeback_fact',
        'license_cost_fact',
        'license_usage_fact',
        'app_server_mapping',
        'applications_dim',
        'servers_dim',
        'reconciliation_log',
        'data_lineage',
        'user_actions',
    ]

    for table in tables:
        cursor.execute(f"TRUNCATE TABLE {table} CASCADE")
        print(f"   ✓ Cleared {table}")

    conn.commit()
    cursor.close()
    print()

def populate_owners_sectors(conn):
    """Populate owners and sectors"""
    print("👥 Populating Owners and Sectors...")
    cursor = conn.cursor()

    # Insert owners
    for name, email, dept in OWNERS:
        cursor.execute("""
            INSERT INTO owners_dim (owner_name, email, department)
            VALUES (%s, %s, %s)
            ON CONFLICT (owner_name) DO NOTHING
        """, (name, email, dept))

    print(f"   ✓ Created {len(OWNERS)} owners")

    # Sectors already seeded in init script
    conn.commit()
    cursor.close()
    print()

def populate_applications(conn):
    """Create realistic application portfolio"""
    print("📱 Populating Applications...")
    cursor = conn.cursor()

    # Get dimension IDs
    cursor.execute("SELECT owner_id, owner_name FROM owners_dim WHERE owner_name != 'Unassigned'")
    owners = cursor.fetchall()

    cursor.execute("SELECT sector_id, sector_name FROM sectors_dim WHERE sector_name != 'Unassigned'")
    sectors = cursor.fetchall()

    cursor.execute("SELECT architecture_id, pattern_name FROM architecture_dim WHERE pattern_name != 'Unknown'")
    architectures = cursor.fetchall()

    apps_created = 0

    # Create 60 applications across controllers
    for i in range(60):
        controller = random.choice(CONTROLLERS)
        app_name = f"{random.choice(APP_NAMES)} - {random.choice(['Prod', 'QA', 'Dev', 'Staging'])}"
        owner = random.choice(owners)
        sector = random.choice(sectors)
        arch = random.choice(architectures)
        tier = random.choice(TIERS)
        h_code = random.choice(H_CODES) if random.random() > 0.15 else None  # 85% coverage

        # Create ServiceNow sys_id for 70% of apps
        sn_sys_id = f"sn_{i:04d}" if random.random() > 0.3 else None

        cursor.execute("""
            INSERT INTO applications_dim (
                appd_application_id, appd_application_name, appd_controller,
                sn_sys_id, sn_service_name, h_code,
                owner_id, sector_id, architecture_id, license_tier,
                metadata
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
        """, (
            f"appd_{i:04d}",
            app_name,
            controller,
            sn_sys_id,
            app_name if sn_sys_id else None,
            h_code,
            owner[0],
            sector[0],
            arch[0],
            tier,
            f'{{"tier_count": {random.randint(1, 15)}, "node_count": {random.randint(2, 50)}}}'
        ))
        apps_created += 1

    conn.commit()
    print(f"   ✓ Created {apps_created} applications")
    print(f"   ✓ Controllers: {len(CONTROLLERS)}")
    print(f"   ✓ ~85% with H-codes")
    print(f"   ✓ ~70% CMDB matched")
    cursor.close()
    print()

def populate_servers(conn):
    """Create servers for matched applications"""
    print("🖥️  Populating Servers...")
    cursor = conn.cursor()

    # Get apps with ServiceNow IDs
    cursor.execute("""
        SELECT app_id, sn_sys_id
        FROM applications_dim
        WHERE sn_sys_id IS NOT NULL
    """)
    apps = cursor.fetchall()

    servers_created = 0
    mappings_created = 0

    for app_id, sn_sys_id in apps:
        # Each app has 2-8 servers
        num_servers = random.randint(2, 8)

        for i in range(num_servers):
            server_name = f"server-{sn_sys_id}-{i:02d}.pepsico.com"

            cursor.execute("""
                INSERT INTO servers_dim (
                    sn_sys_id, server_name, ip_address, os, is_virtual
                ) VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (sn_sys_id) DO NOTHING
                RETURNING server_id
            """, (
                f"{sn_sys_id}_srv_{i:02d}",
                server_name,
                f"10.{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}",
                random.choice(['Red Hat Linux', 'Windows Server 2019', 'Ubuntu 20.04', 'CentOS 7']),
                random.choice([True, False])
            ))

            result = cursor.fetchone()
            if result:
                server_id = result[0]
                servers_created += 1

                # Map to application
                cursor.execute("""
                    INSERT INTO app_server_mapping (app_id, server_id, relationship_type)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (app_id, server_id) DO NOTHING
                """, (app_id, server_id, 'Runs on::Runs'))
                mappings_created += 1

    conn.commit()
    print(f"   ✓ Created {servers_created} servers")
    print(f"   ✓ Created {mappings_created} app-server mappings")
    cursor.close()
    print()

def populate_usage_and_costs(conn):
    """Generate 6 months of usage and cost data"""
    print("💰 Populating Usage and Cost Data (6 months)...")
    cursor = conn.cursor()

    # Get all applications
    cursor.execute("SELECT app_id FROM applications_dim")
    apps = [row[0] for row in cursor.fetchall()]

    # Get capability IDs
    cursor.execute("SELECT capability_id, capability_code FROM capabilities_dim")
    capabilities = cursor.fetchall()

    # Get price config
    cursor.execute("""
        SELECT pc.capability_id, pc.tier, pc.unit_rate
        FROM price_config pc
        WHERE pc.end_date IS NULL OR pc.end_date > CURRENT_DATE
    """)
    prices = {(row[0], row[1]): row[2] for row in cursor.fetchall()}

    # Generate data for last 6 months (daily)
    end_date = datetime.now()
    start_date = end_date - timedelta(days=180)

    usage_records = 0
    cost_records = 0

    print("   Generating daily data points...")

    for app_id in apps:
        # Each app uses 1-3 capabilities
        app_capabilities = random.sample(capabilities, random.randint(1, 3))

        current_date = start_date
        while current_date <= end_date:
            for cap_id, cap_code in app_capabilities:
                tier = random.choice(TIERS)

                # Generate realistic usage with growth trend
                base_usage = random.uniform(10, 500)
                growth_factor = 1 + (current_date - start_date).days / 365 * 0.15  # 15% annual growth
                daily_variation = random.uniform(0.8, 1.2)
                units = base_usage * growth_factor * daily_variation

                # Insert usage
                cursor.execute("""
                    INSERT INTO license_usage_fact (
                        ts, app_id, capability_id, tier, units_consumed, nodes_count
                    ) VALUES (%s, %s, %s, %s, %s, %s)
                """, (
                    current_date,
                    app_id,
                    cap_id,
                    tier,
                    round(units, 2),
                    random.randint(1, 20)
                ))
                usage_records += 1

                # Calculate and insert cost
                price_key = (cap_id, tier)
                if price_key in prices:
                    cost = Decimal(str(units)) * prices[price_key]

                    cursor.execute("""
                        INSERT INTO license_cost_fact (
                            ts, app_id, capability_id, tier, usd_cost, price_id
                        ) VALUES (%s, %s, %s, %s, %s,
                            (SELECT price_id FROM price_config
                             WHERE capability_id = %s AND tier = %s
                             AND (end_date IS NULL OR end_date > CURRENT_DATE)
                             LIMIT 1)
                        )
                    """, (
                        current_date,
                        app_id,
                        cap_id,
                        tier,
                        round(cost, 2),
                        cap_id,
                        tier
                    ))
                    cost_records += 1

            current_date += timedelta(days=1)

            # Commit every 1000 records
            if usage_records % 1000 == 0:
                conn.commit()
                print(f"      {usage_records:,} usage records, {cost_records:,} cost records...")

    conn.commit()
    print(f"   ✓ Created {usage_records:,} usage records")
    print(f"   ✓ Created {cost_records:,} cost records")
    print(f"   ✓ Date range: {start_date.date()} to {end_date.date()}")
    cursor.close()
    print()

def populate_chargeback(conn):
    """Generate monthly chargeback records"""
    print("🧾 Populating Chargeback Data...")
    cursor = conn.cursor()

    # Generate for last 6 months
    for month_offset in range(6):
        month_start = (datetime.now().replace(day=1) - timedelta(days=30 * month_offset)).replace(day=1)

        cursor.execute("""
            INSERT INTO chargeback_fact (month_start, app_id, h_code, sector_id, owner_id, usd_amount)
            SELECT
                %s,
                a.app_id,
                a.h_code,
                a.sector_id,
                a.owner_id,
                COALESCE(SUM(lc.usd_cost), 0)
            FROM applications_dim a
            LEFT JOIN license_cost_fact lc ON a.app_id = lc.app_id
                AND DATE_TRUNC('month', lc.ts) = %s
            GROUP BY a.app_id, a.h_code, a.sector_id, a.owner_id
            HAVING COALESCE(SUM(lc.usd_cost), 0) > 0
            ON CONFLICT (month_start, app_id, sector_id) DO NOTHING
        """, (month_start, month_start))

    conn.commit()
    cursor.execute("SELECT COUNT(*) FROM chargeback_fact")
    count = cursor.fetchone()[0]
    print(f"   ✓ Created {count:,} monthly chargeback records")
    cursor.close()
    print()

def populate_forecasts(conn):
    """Generate forecast data for next 12 months"""
    print("📈 Populating Forecast Data...")
    cursor = conn.cursor()

    # Get recent average usage per app/capability
    cursor.execute("""
        SELECT
            app_id,
            capability_id,
            tier,
            AVG(units_consumed) as avg_units,
            AVG(usd_cost) as avg_cost
        FROM (
            SELECT
                lu.app_id,
                lu.capability_id,
                lu.tier,
                lu.units_consumed,
                lc.usd_cost
            FROM license_usage_fact lu
            JOIN license_cost_fact lc ON lu.ts = lc.ts
                AND lu.app_id = lc.app_id
                AND lu.capability_id = lc.capability_id
            WHERE lu.ts >= NOW() - INTERVAL '30 days'
        ) recent
        GROUP BY app_id, capability_id, tier
    """)

    baseline_data = cursor.fetchall()

    forecast_records = 0

    for app_id, cap_id, tier, avg_units, avg_cost in baseline_data:
        # Forecast next 12 months with 10% growth and seasonal variation
        for month_ahead in range(1, 13):
            forecast_date = (datetime.now().replace(day=1) + timedelta(days=30 * month_ahead)).replace(day=1)

            # Apply growth trend
            growth_factor = 1 + (month_ahead / 12) * 0.10  # 10% annual growth

            # Add seasonal variation
            seasonal_factor = 1 + 0.1 * random.choice([-1, 0, 1])  # ±10% seasonal

            projected_units = float(avg_units) * growth_factor * seasonal_factor
            projected_cost = float(avg_cost) * growth_factor * seasonal_factor

            # Confidence intervals (±15%)
            confidence_low = projected_cost * 0.85
            confidence_high = projected_cost * 1.15

            cursor.execute("""
                INSERT INTO forecast_fact (
                    month_start, app_id, capability_id, tier,
                    projected_units, projected_cost,
                    confidence_interval_low, confidence_interval_high,
                    method
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (month_start, app_id, capability_id, tier) DO NOTHING
            """, (
                forecast_date,
                app_id,
                cap_id,
                tier,
                round(projected_units, 2),
                round(projected_cost, 2),
                round(confidence_low, 2),
                round(confidence_high, 2),
                'ensemble'
            ))
            forecast_records += 1

    conn.commit()
    print(f"   ✓ Created {forecast_records:,} forecast records")
    print(f"   ✓ 12-month projection for all active app/capability pairs")
    cursor.close()
    print()

def populate_reconciliation_log(conn):
    """Create reconciliation records"""
    print("🔗 Populating Reconciliation Log...")
    cursor = conn.cursor()

    cursor.execute("""
        SELECT app_id, appd_application_name, sn_sys_id, sn_service_name
        FROM applications_dim
    """)
    apps = cursor.fetchall()

    for app_id, appd_name, sn_sys_id, sn_name in apps:
        if sn_sys_id:
            # Matched record
            confidence = random.uniform(85, 100)
            cursor.execute("""
                INSERT INTO reconciliation_log (
                    source_a, source_b, match_key_a, match_key_b,
                    confidence_score, match_status, resolved_app_id
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (
                'appdynamics', 'servicenow',
                appd_name, sn_name,
                round(confidence, 2),
                'auto_matched' if confidence > 90 else 'manual_review',
                app_id
            ))
        else:
            # Unmatched AppD app
            cursor.execute("""
                INSERT INTO reconciliation_log (
                    source_a, source_b, match_key_a, match_key_b,
                    confidence_score, match_status, resolved_app_id
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (
                'appdynamics', 'servicenow',
                appd_name, None,
                0,
                'no_match',
                app_id
            ))

    conn.commit()
    cursor.execute("SELECT COUNT(*) FROM reconciliation_log")
    count = cursor.fetchone()[0]
    print(f"   ✓ Created {count:,} reconciliation records")
    cursor.close()
    print()

def refresh_materialized_views(conn):
    """Refresh all materialized views"""
    print("🔄 Refreshing Materialized Views...")
    cursor = conn.cursor()

    views = [
        'mv_daily_cost_by_controller',
        'mv_daily_usage_by_capability',
        'mv_cost_by_sector_controller',
        'mv_cost_by_owner_controller',
        'mv_architecture_metrics_90d',
        'mv_app_cost_rankings_monthly',
        'mv_monthly_chargeback_summary',
        'mv_peak_pro_comparison',
    ]

    for view in views:
        try:
            cursor.execute(f"REFRESH MATERIALIZED VIEW CONCURRENTLY {view}")
            conn.commit()
            print(f"   ✓ Refreshed {view}")
        except Exception as e:
            print(f"   ⚠️  Could not refresh {view}: {e}")

    cursor.close()
    print()

def print_summary(conn):
    """Print data summary"""
    cursor = conn.cursor()

    print("=" * 70)
    print("📊 DEMO DATA POPULATION SUMMARY")
    print("=" * 70)

    tables = [
        ('applications_dim', 'Applications'),
        ('servers_dim', 'Servers'),
        ('app_server_mapping', 'App-Server Mappings'),
        ('license_usage_fact', 'Usage Records'),
        ('license_cost_fact', 'Cost Records'),
        ('chargeback_fact', 'Chargeback Records'),
        ('forecast_fact', 'Forecast Records'),
        ('reconciliation_log', 'Reconciliation Records'),
    ]

    for table, label in tables:
        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        count = cursor.fetchone()[0]
        print(f"   {label:.<35} {count:>12,}")

    print()
    print("📅 Data Coverage:")
    cursor.execute("SELECT MIN(ts), MAX(ts) FROM license_usage_fact")
    min_date, max_date = cursor.fetchone()
    print(f"   Historical Data: {min_date.date()} to {max_date.date()}")

    cursor.execute("SELECT MIN(month_start), MAX(month_start) FROM forecast_fact")
    min_forecast, max_forecast = cursor.fetchone()
    if min_forecast:
        print(f"   Forecast Data: {min_forecast.date()} to {max_forecast.date()}")

    print()
    print("🎯 Data Quality:")
    cursor.execute("""
        SELECT
            COUNT(*) FILTER (WHERE h_code IS NOT NULL) as with_hcode,
            COUNT(*) as total
        FROM applications_dim
    """)
    with_hcode, total = cursor.fetchone()
    print(f"   H-Code Coverage: {with_hcode}/{total} ({with_hcode/total*100:.1f}%)")

    cursor.execute("""
        SELECT
            COUNT(*) FILTER (WHERE sn_sys_id IS NOT NULL) as matched,
            COUNT(*) as total
        FROM applications_dim
    """)
    matched, total = cursor.fetchone()
    print(f"   CMDB Match Rate: {matched}/{total} ({matched/total*100:.1f}%)")

    cursor.execute("SELECT SUM(usd_cost) FROM license_cost_fact")
    total_cost = cursor.fetchone()[0]
    print(f"   Total Cost Tracked: ${total_cost:,.2f}")

    print()
    print("=" * 70)
    print("✅ Demo data ready for client presentation!")
    print("=" * 70)

    cursor.close()

def main():
    """Main execution"""
    print("=" * 70)
    print("🎬 POPULATING DEMO DATA FOR CLIENT PRESENTATION")
    print("=" * 70)
    print()

    if not all([DB_HOST, DB_NAME, DB_USER, DB_PASSWORD]):
        print("❌ Database credentials not found in environment")
        sys.exit(1)

    try:
        conn = get_conn()
        print(f"✅ Connected to {DB_HOST}/{DB_NAME}")
        print()

        # Confirm before clearing
        response = input("⚠️  Clear existing data? (yes/no): ").strip().lower()
        if response == 'yes':
            clear_existing_data(conn)

        # Populate all data
        populate_owners_sectors(conn)
        populate_applications(conn)
        populate_servers(conn)
        populate_usage_and_costs(conn)
        populate_chargeback(conn)
        populate_forecasts(conn)
        populate_reconciliation_log(conn)
        refresh_materialized_views(conn)

        # Summary
        print_summary(conn)

        conn.close()

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()

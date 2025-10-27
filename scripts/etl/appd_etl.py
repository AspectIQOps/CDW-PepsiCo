#!/usr/bin/env python3
"""
AppDynamics ETL Script
Pulls license usage data from AppDynamics and loads into PostgreSQL
"""

import sys
from datetime import datetime, timedelta
import requests
import psycopg2
from psycopg2.extras import execute_batch
import pandas as pd # Explicitly imported for potential future use or if upsert logic changes

# Import centralized utilities and configuration
try:
    from .etl_utils import ETLConfig, get_db_connection, log_etl_start, log_etl_finish, logger
except ImportError:
    # Allows script to run outside package structure for testing
    from etl_utils import ETLConfig, get_db_connection, log_etl_start, log_etl_finish, logger

class AppDynamicsETL:
    """AppDynamics ETL Handler"""
    
    def __init__(self):
        """Initialize with configuration variables from ETLConfig."""
        # --- AppDynamics Config (from ETLConfig which reads environment) ---
        # Note: APPD_CONTROLLER is used to match the environment variable exported by entrypoint.sh
        self.controller_url = ETLConfig.APPD_CONTROLLER
        self.account = ETLConfig.APPD_ACCOUNT
        self.client_id = ETLConfig.APPD_CLIENT_ID
        self.client_secret = ETLConfig.APPD_CLIENT_SECRET
        
        # --- Internal Setup ---
        self._validate_appd_config()
        self.session = requests.Session()
        self.access_token = None
    
    def _validate_appd_config(self):
        """Validate required AppDynamics configuration."""
        required = {
            'APPD_CONTROLLER': self.controller_url,
            'APPD_ACCOUNT': self.account,
            'APPD_CLIENT_ID': self.client_id,
            'APPD_CLIENT_SECRET': self.client_secret,
        }
        
        missing = [k for k, v in required.items() if not v]
        if missing:
            logger.error(f"FATAL: Missing required AppDynamics environment variables: {', '.join(missing)}")
            raise EnvironmentError(f"Incomplete AppDynamics configuration: {', '.join(missing)}")
    
    def authenticate(self):
        """
        Authenticate with AppDynamics using OAuth2
        """
        # Ensure the controller URL ends with a slash for consistent pathing
        base_url = self.controller_url.rstrip('/')
        token_url = f"{base_url}/controller/api/oauth/access_token"
        
        payload = {
            'grant_type': 'client_credentials',
            'client_id': self.client_id,
            'client_secret': self.client_secret
        }
        
        try:
            logger.info("Authenticating with AppDynamics...")
            response = self.session.post(token_url, data=payload, timeout=30)
            response.raise_for_status()
            
            token_data = response.json()
            self.access_token = token_data.get('access_token')
            
            if not self.access_token:
                raise ValueError("No access token found in authentication response")
            
            self.session.headers.update({
                'Authorization': f'Bearer {self.access_token}',
                'Content-Type': 'application/json'
            })
            
            logger.info("Authentication successful")
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Authentication failed (URL: {token_url}): {e}")
            raise
    
    def get_applications(self):
        """
        Retrieve all applications from AppDynamics
        
        Returns:
            List of application objects
        """
        base_url = self.controller_url.rstrip('/')
        url = f"{base_url}/controller/rest/applications"
        
        try:
            logger.info("Fetching applications list...")
            response = self.session.get(url, params={'output': 'JSON'}, timeout=60)
            response.raise_for_status()
            
            apps = response.json()
            logger.info(f"Retrieved {len(apps)} applications")
            return apps
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch applications from {url}: {e}")
            raise
    
    def get_license_usage(self, app_id, start_time, end_time):
        """
        Get license usage for a specific application
        
        Args:
            app_id: Application ID
            start_time: Start timestamp (milliseconds)
            end_time: End timestamp (milliseconds)
            
        Returns:
            License usage data
        """
        base_url = self.controller_url.rstrip('/')
        url = f"{base_url}/controller/rest/applications/{app_id}/metric-data"
        
        # Metric paths for different license types (as defined in original script)
        metrics = [
            'Licenses|APM|Peak', 'Licenses|APM|Pro',
            'Licenses|RUM|MRUM|Peak', 'Licenses|RUM|MRUM|Pro',
            'Licenses|RUM|BRUM|Peak', 'Licenses|RUM|BRUM|Pro',
            'Licenses|Synthetic|Peak', 'Licenses|Synthetic|Pro',
            'Licenses|Database|Peak', 'Licenses|Database|Pro'
        ]
        
        params = {
            'metric-path': '|'.join(metrics),
            'time-range-type': 'BETWEEN_TIMES',
            'start-time': start_time,
            'end-time': end_time,
            'rollup': 'false', # Raw data for better granularity
            'output': 'JSON'
        }
        
        try:
            response = self.session.get(url, params=params, timeout=60)
            response.raise_for_status()
            return response.json()
            
        except requests.exceptions.RequestException as e:
            # Use warning here, as failure for one app shouldn't stop the entire run
            logger.warning(f"Failed to fetch license usage for app ID {app_id}: {e}")
            return []
    
    def parse_metric_path(self, metric_path):
        """
        Parse metric path to extract license type and tier
        
        Args:
            metric_path: Metric path string (e.g., 'Licenses|APM|Peak')
            
        Returns:
            Tuple of (capability_code, tier)
        """
        parts = metric_path.split('|')
        
        if len(parts) < 3:
            return None, None
        
        # Map license types to capability codes (consistent with your original map)
        license_type_map = {
            'APM': 'APM',
            'MRUM': 'MRUM',
            'BRUM': 'BRUM',
            'Synthetic': 'SYN',
            'Database': 'DB'
        }
        
        license_type = parts[1] if len(parts) > 1 else None
        if len(parts) > 2 and parts[1] == 'RUM':
            license_type = parts[2]  # MRUM or BRUM
        
        tier = parts[-1]  # Peak or Pro
        
        capability_code = license_type_map.get(license_type)
        
        return capability_code, tier
    
    def upsert_applications(self, conn, applications):
        """
        Upsert applications into applications_dim table
        
        Args:
            conn: Database connection
            applications: List of application records
        """
        cur = conn.cursor()
        
        try:
            upsert_data = []
            
            for app in applications:
                appd_application_id = app.get('id')
                appd_application_name = app.get('name')
                
                # We need to map to the applications_dim columns. sn_sys_id, h_code, etc. are unknown here.
                upsert_data.append((appd_application_id, appd_application_name))
            
            logger.info(f"Upserting {len(upsert_data)} applications...")
            
            # NOTE: Updated query to handle ON CONFLICT for the unique key (appd_application_id)
            execute_batch(cur, """
                INSERT INTO applications_dim(
                    appd_application_id, appd_application_name
                )
                VALUES (%s, %s)
                ON CONFLICT (appd_application_id) DO UPDATE SET
                    appd_application_name = EXCLUDED.appd_application_name,
                    updated_at = now()
            """, upsert_data)
            
            conn.commit()
            logger.info(f"Successfully upserted {len(applications)} applications into applications_dim.")
            
        except psycopg2.Error as e:
            conn.rollback()
            logger.error(f"Database error during application upsert: {e}")
            raise
        finally:
            cur.close()
    
    def upsert_license_usage(self, conn, run_id, license_data):
        """
        Upsert license usage data into license_usage_fact
        
        Args:
            conn: Database connection
            run_id: ETL run ID
            license_data: List of parsed license usage records
        """
        cur = conn.cursor()
        
        try:
            # 1. Get dimension mappings in one transaction
            cur.execute("SELECT capability_id, capability_code FROM capabilities_dim")
            capability_map = {row[1]: row[0] for row in cur.fetchall()}
            
            cur.execute("SELECT app_id, appd_application_id FROM applications_dim WHERE appd_application_id IS NOT NULL")
            app_map = {row[1]: row[0] for row in cur.fetchall()}
            
            # 2. Prepare data for batch insert
            upsert_data = []
            lineage_data = []
            
            for record in license_data:
                # Map external ID to internal surrogate key
                app_id = app_map.get(record['appd_app_id'])
                capability_id = capability_map.get(record['capability_code'])
                
                if not app_id or not capability_id:
                    logger.warning(f"Skipping record - missing dimension mapping: AppD ID={record['appd_app_id']}, Code={record['capability_code']}")
                    continue
                
                # Data for license_usage_fact
                upsert_data.append((
                    record['timestamp'],
                    app_id,
                    capability_id,
                    record['tier'],
                    record['units'],
                    record.get('nodes', 0)
                ))
                
                # Data for data_lineage
                # Target PK stored as JSONB string
                target_pk = f'{{"ts": "{record["timestamp"]}", "app_id": {app_id}, "capability_id": {capability_id}, "tier": "{record["tier"]}"}}'
                lineage_data.append((
                    run_id,
                    'AppDynamics',
                    f"applications/{record['appd_app_id']}/metric-data",
                    'license_usage_fact',
                    target_pk
                ))
            
            if not upsert_data:
                logger.warning("No valid license usage data to insert.")
                return 0
            
            # 3. Execute Batch Insert for Fact Table
            logger.info(f"Upserting {len(upsert_data)} license usage records...")
            execute_batch(cur, """
                INSERT INTO license_usage_fact(
                    ts, app_id, capability_id, tier, units, nodes
                )
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (ts, app_id, capability_id, tier) DO UPDATE SET
                    units = EXCLUDED.units,
                    nodes = EXCLUDED.nodes
            """, upsert_data)
            
            # 4. Execute Batch Insert for Lineage Table
            logger.info(f"Inserting {len(lineage_data)} lineage records...")
            execute_batch(cur, """
                INSERT INTO data_lineage(
                    run_id, source_system, source_endpoint, target_table, target_pk
                )
                VALUES (%s, %s, %s, %s, %s::jsonb)
            """, lineage_data)
            
            conn.commit()
            logger.info(f"Successfully upserted {len(upsert_data)} license usage records.")
            return len(upsert_data)
            
        except psycopg2.Error as e:
            conn.rollback()
            logger.error(f"Database error during license usage upsert: {e}")
            raise
        finally:
            cur.close()
    
    def run(self):
        """Execute the ETL process"""
        start_time = datetime.now()
        job_name = 'appd_pull'
        
        conn = None
        run_id = None
        rows_ingested = 0
        
        try:
            # 1. Authenticate and Connect
            self.authenticate()
            conn = get_db_connection()
            
            # 2. Start ETL run log using utility
            run_id = log_etl_start(job_name, conn)
            
            # 3. Get all applications
            applications = self.get_applications()
            
            if not applications:
                logger.warning("No applications retrieved from AppDynamics. Ending run.")
                log_etl_finish(run_id, 'SUCCESS (No Data)', 0, conn)
                return
            
            # 4. Upsert applications dimension
            self.upsert_applications(conn, applications)
            
            # 5. Determine time window (Last 24 hours)
            end_time = int(datetime.now().timestamp() * 1000)
            start_time_ms = int((datetime.now() - timedelta(days=1)).timestamp() * 1000)
            
            all_license_data = []
            
            # 6. Fetch license usage for each application
            for app in applications:
                app_id = app.get('id')
                app_name = app.get('name')
                
                logger.debug(f"Fetching license usage for app: {app_name} (ID: {app_id})")
                
                usage_data = self.get_license_usage(app_id, start_time_ms, end_time)
                
                # 7. Parse and aggregate data
                for metric in usage_data:
                    metric_path = metric.get('metricPath')
                    capability_code, tier = self.parse_metric_path(metric_path)
                    
                    if not capability_code or not tier:
                        continue
                    
                    for value_point in metric.get('metricValues', []):
                        timestamp = datetime.fromtimestamp(value_point['startTimeInMillis'] / 1000)
                        units = value_point.get('value', 0)
                        
                        all_license_data.append({
                            'appd_app_id': app_id,
                            'timestamp': timestamp,
                            'capability_code': capability_code,
                            'tier': tier,
                            'units': units,
                            'nodes': 0  # Placeholder, as nodes need separate API
                        })
            
            # 8. Upsert all license usage data
            rows_ingested = self.upsert_license_usage(conn, run_id, all_license_data)
            
            # 9. Update ETL log using utility
            log_etl_finish(run_id, 'SUCCESS', rows_ingested, conn)
            
            duration = (datetime.now() - start_time).total_seconds()
            logger.info("=" * 60)
            logger.info(f"AppDynamics ETL Completed Successfully in {duration:.2f}s")
            logger.info(f"Processed {len(applications)} applications, loaded {rows_ingested} records.")
            logger.info("=" * 60)
            
        except Exception as e:
            duration = (datetime.now() - start_time).total_seconds()
            logger.error("=" * 60)
            logger.error(f"AppDynamics ETL Failed after {duration:.2f}s")
            logger.error(f"Error: {e}", exc_info=True) # exc_info=True prints full traceback
            logger.error("=" * 60)
            
            # Log failure using utility
            if conn and run_id:
                log_etl_finish(run_id, 'FAILED', rows_ingested, conn, error_message=str(e)[:255])
            
            # Exit with status code 1 for Docker/Scheduler to catch the failure
            sys.exit(1)
            
        finally:
            if conn:
                conn.close()


def main():
    """Main entry point"""
    try:
        # Before running, ensure DB connection configuration is validated
        ETLConfig.validate_db_config()
        
        etl = AppDynamicsETL()
        etl.run()
    except Exception as e:
        logger.error(f"Fatal execution error in main: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()

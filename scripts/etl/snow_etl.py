#!/usr/bin/env python3
"""
ServiceNow ETL Script
Pulls Configuration Items (CI Services) from ServiceNow and
upserts them into the PostgreSQL applications_dim table.
"""

import sys
from datetime import datetime
import requests
import psycopg2
from psycopg2.extras import execute_batch

# Import centralized utilities and configuration
try:
    from .etl_utils import ETLConfig, get_db_connection, log_etl_start, log_etl_finish, logger
except ImportError:
    # Allows script to run outside package structure for testing
    from etl_utils import ETLConfig, get_db_connection, log_etl_start, log_etl_finish, logger


class ServiceNowETL:
    """ServiceNow ETL Handler for pulling CI Service data."""
    
    JOB_NAME = 'snow_pull'
    
    def __init__(self):
        """Initialize with configuration variables from ETLConfig."""
        # --- ServiceNow Config (from ETLConfig) ---
        self.instance = ETLConfig.SN_INSTANCE
        self.user = ETLConfig.SN_USER
        self.password = ETLConfig.SN_PASS
        
        self._validate_config()
        
        # --- Internal Setup ---
        self.base_url = f"https://{self.instance}.service-now.com/api/now/table"
        self.session = requests.Session()
        # ServiceNow uses Basic Auth
        self.session.auth = (self.user, self.password)

    def _validate_config(self):
        """Validate required ServiceNow configuration."""
        required = {
            'SN_INSTANCE': self.instance,
            'SN_USER': self.user,
            'SN_PASS': self.password,
        }
        
        missing = [k for k, v in required.items() if not v]
        if missing:
            logger.error(f"FATAL: Missing required ServiceNow environment variables: {', '.join(missing)}")
            raise EnvironmentError(f"Incomplete ServiceNow configuration: {', '.join(missing)}")

    def pull(self, table, fields, query=None):
        """
        Pulls data from a ServiceNow table using defined fields and query.
        
        Args:
            table (str): ServiceNow table name (e.g., 'cmdb_ci_service').
            fields (list): List of field names to retrieve.
            query (str, optional): ServiceNow query string.
            
        Returns:
            list: List of dictionary results.
        """
        url = f"{self.base_url}/{table}"
        # Set a high limit for full dataset retrieval
        params = {'sysparm_fields': ','.join(fields), 'sysparm_limit': 10000}
        if query:
            params['sysparm_query'] = query
        
        try:
            logger.info(f"Pulling data from ServiceNow table: {table} (Query: {query or 'None'})")
            # Use longer timeout for potentially large data pulls
            response = self.session.get(url, params=params, timeout=120) 
            response.raise_for_status()

            # Detect HTML responses (e.g., hibernating instance)
            content_type = response.headers.get('Content-Type', '')
            if 'text/html' in content_type:
                logger.error(f"Received HTML instead of JSON. ServiceNow instance may be hibernating: {url}")
                raise requests.exceptions.RequestException(f"HTML response from ServiceNow: {url}")

            results = response.json().get('result', [])
            logger.info(f"Successfully retrieved {len(results)} records from {table}")
            return results
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to pull data from {table}: {e}")
            raise
        except (KeyError, ValueError) as e:
            logger.error(f"Failed to parse JSON response from ServiceNow for {table}: {e}")
            raise

    def upsert_services(self, conn, run_id, services):
        """
        Upsert application/service data into applications_dim and insert lineage records.
        
        Args:
            conn: Database connection
            run_id: ETL run ID
            services: List of service records from ServiceNow
            
        Returns:
            Number of rows ingested/updated.
        """
        if not services:
            logger.warning("No services data provided for upsert.")
            return 0
            
        cur = conn.cursor()
        
        try:
            upsert_data = []
            lineage_data = []
            source_endpoint = 'cmdb_ci_service'
            target_table = 'applications_dim'
            
            for s in services:
                sys_id = s.get('sys_id')
                
                # Data for applications_dim (Note: appd_application_name is defaulted to sn_service_name here)
                upsert_data.append((
                    s.get('name'),    # appd_application_name
                    sys_id,           # sn_sys_id (Unique key)
                    s.get('name'),    # sn_service_name
                    s.get('u_h_code'),# h_code
                    s.get('u_sector') # sector
                ))
                
                # Data for data_lineage
                target_pk = f'{{"sn_sys_id": "{sys_id}"}}'
                lineage_data.append((
                    run_id,
                    'ServiceNow',
                    source_endpoint,
                    target_table,
                    target_pk
                ))
                
            # 1. Execute Batch Insert/Update for applications_dim
            logger.info(f"Upserting {len(upsert_data)} service records into {target_table}...")
            # Use COALESCE on appd_application_name to ensure AppD name isn't overwritten if it was previously populated
            execute_batch(cur, """
                INSERT INTO applications_dim(
                    appd_application_name, sn_sys_id, sn_service_name, h_code, sector
                )
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (sn_sys_id) DO UPDATE SET
                  appd_application_name = COALESCE(applications_dim.appd_application_name, EXCLUDED.appd_application_name),
                  sn_service_name = EXCLUDED.sn_service_name,
                  h_code = EXCLUDED.h_code,
                  sector = EXCLUDED.sector,
                  updated_at = now()
            """, upsert_data)
            
            # 2. Execute Batch Insert for data_lineage
            logger.info(f"Inserting {len(lineage_data)} lineage records...")
            execute_batch(cur, """
                INSERT INTO data_lineage(
                    run_id, source_system, source_endpoint, target_table, target_pk
                )
                VALUES (%s, %s, %s, %s, %s::jsonb)
            """, lineage_data)
            
            conn.commit()
            logger.info(f"Successfully upserted and recorded lineage for {len(services)} services.")
            return len(services)
            
        except psycopg2.Error as e:
            conn.rollback()
            logger.error(f"Database error during ServiceNow upsert: {e}")
            raise
        finally:
            cur.close()

    def run(self):
        """Execute the ETL process"""
        start_time = datetime.now()
        conn = None
        run_id = None
        rows_ingested = 0
        
        try:
            # 1. Get database connection and log start
            conn = get_db_connection()
            run_id = log_etl_start(self.JOB_NAME, conn)
            
            # 2. Pull data from ServiceNow (cmdb_ci_service)
            # Query: active operational services (install_status=1^operational_status=1)
            services = self.pull(
                table='cmdb_ci_service', 
                fields=['sys_id','name','owner','u_h_code','u_sector'], 
                query='install_status=1^operational_status=1'
            )
            
            # 3. Upsert data
            rows_ingested = self.upsert_services(conn, run_id, services)
            
            # 4. Log successful finish
            log_etl_finish(run_id, 'SUCCESS', rows_ingested, conn)
            
            duration = (datetime.now() - start_time).total_seconds()
            logger.info("=" * 60)
            logger.info(f"ServiceNow ETL Completed Successfully in {duration:.2f}s")
            logger.info(f"Loaded {rows_ingested} service records.")
            logger.info("=" * 60)
            
        except Exception as e:
            # Log failure
            duration = (datetime.now() - start_time).total_seconds()
            logger.error("=" * 60)
            logger.error(f"ServiceNow ETL Failed after {duration:.2f}s")
            logger.error(f"Error: {e}", exc_info=True)
            logger.error("=" * 60)
            
            if conn and run_id:
                log_etl_finish(run_id, 'FAILED', rows_ingested, conn, error_message=str(e)[:255])
            
            sys.exit(1)
            
        finally:
            if conn:
                conn.close()


def main():
    """Main entry point"""
    try:
        # Before running, ensure all necessary config is validated
        ETLConfig.validate_db_config()
        etl = ServiceNowETL()
        etl.run()
    except Exception as e:
        logger.error(f"Fatal execution error in main: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()

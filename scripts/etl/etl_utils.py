import os
import logging
import psycopg2
import pandas as pd
from datetime import datetime

# --- Configuration & Logging ---

LOG_LEVEL = os.environ.get('ETL_LOG_LEVEL', 'INFO').upper()
# Set up basic logging configuration
logging.basicConfig(
    level=LOG_LEVEL,
    format='%(asctime)s - %(levelname)s - %(name)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('ETL_Base')

class ETLConfig:
    """
    Class to hold and validate essential configuration variables fetched from entrypoint.sh.
    All secrets come from AWS SSM via the entrypoint.sh script.
    """
    # Database Settings (SSM Parameters)
    DB_HOST = os.environ.get('DB_HOST')
    DB_PORT = os.environ.get('DB_PORT', '5432')
    DB_NAME = os.environ.get('DB_NAME')
    DB_USER = os.environ.get('DB_USER')
    DB_PASSWORD = os.environ.get('DB_PASSWORD')

    # AppDynamics Settings (SSM Parameters)
    APPD_CONTROLLER = os.environ.get('APPD_CONTROLLER')
    APPD_ACCOUNT = os.environ.get('APPD_ACCOUNT')
    APPD_CLIENT_ID = os.environ.get('APPD_CLIENT_ID')
    APPD_CLIENT_SECRET = os.environ.get('APPD_CLIENT_SECRET')

    # ServiceNow Settings (SSM Parameters)
    SN_INSTANCE = os.environ.get('SN_INSTANCE')
    SN_USER = os.environ.get('SN_USER')
    SN_PASS = os.environ.get('SN_PASS')

    @classmethod
    def validate_db_config(cls):
        """Checks if minimum DB config is available."""
        required = [cls.DB_HOST, cls.DB_NAME, cls.DB_USER, cls.DB_PASSWORD]
        if any(v is None or v == '' for v in required):
            logger.error("FATAL: Missing one or more required database configuration environment variables (DB_HOST, DB_NAME, DB_USER, DB_PASSWORD).")
            # Note: entrypoint.sh should prevent reaching this point if SSM fails, but this is a final guard.
            raise EnvironmentError("Incomplete database configuration.")

# --- Database Connection and Loading Functions ---

def get_db_connection():
    """Establishes a connection to the PostgreSQL database."""
    ETLConfig.validate_db_config()
    conn = None
    try:
        conn = psycopg2.connect(
            host=ETLConfig.DB_HOST,
            port=ETLConfig.DB_PORT,
            dbname=ETLConfig.DB_NAME,
            user=ETLConfig.DB_USER,
            password=ETLConfig.DB_PASSWORD
        )
        logger.info("Successfully connected to the PostgreSQL database.")
        return conn
    except Exception as e:
        logger.error(f"Failed to connect to the database: {e}")
        raise

def insert_dataframe_to_postgres(df: pd.DataFrame, table_name: str, connection: psycopg2.connect, if_exists='append'):
    """
    Inserts a Pandas DataFrame into a specified PostgreSQL table.

    Args:
        df (pd.DataFrame): The DataFrame to insert.
        table_name (str): The name of the target table.
        connection (psycopg2.connect): An active database connection object.
        if_exists (str): How to handle existing data ('fail', 'replace', 'append').
    """
    try:
        # Use pandas to_sql method for bulk loading
        df.to_sql(
            table_name,
            connection,
            schema='public',
            if_exists=if_exists,
            index=False, # We use sequence-generated IDs in the database
            method='multi' # Efficient bulk insert method
        )
        logger.info(f"Successfully inserted {len(df)} rows into table: {table_name}")
    except Exception as e:
        logger.error(f"Failed to insert data into {table_name}: {e}")
        raise

def log_etl_start(job_name: str, connection: psycopg2.connect) -> int:
    """Logs the start of an ETL job and returns the run_id."""
    try:
        with connection.cursor() as cur:
            cur.execute(
                "INSERT INTO etl_execution_log (job_name, status) VALUES (%s, 'RUNNING') RETURNING run_id",
                (job_name,)
            )
            run_id = cur.fetchone()[0]
            connection.commit()
            logger.info(f"ETL job '{job_name}' started. Run ID: {run_id}")
            return run_id
    except Exception as e:
        logger.error(f"Failed to log ETL start: {e}")
        connection.rollback()
        raise

def log_etl_finish(run_id: int, status: str, rows_ingested: int, connection: psycopg2.connect, error_message: str = None):
    """Logs the completion or failure of an ETL job."""
    try:
        with connection.cursor() as cur:
            cur.execute(
                """
                UPDATE etl_execution_log
                SET finished_at = NOW(), status = %s, rows_ingested = %s, error_message = %s
                WHERE run_id = %s
                """,
                (status, rows_ingested, error_message, run_id)
            )
            connection.commit()
        logger.info(f"ETL job (ID: {run_id}) finished with status: {status}. Rows ingested: {rows_ingested}")
    except Exception as e:
        logger.error(f"Failed to log ETL finish for run_id {run_id}: {e}")
        connection.rollback()

"""
Audit Logger for Analytics Platform

NOTE: This module provides advanced audit logging capabilities with UUID-based tracking,
stage-level metrics, and JSONB metadata support via the audit_etl_runs table.

CURRENT STATUS: Not actively used in MVP. ETL scripts use the simpler etl_execution_log 
table directly for job-level tracking (start time, end time, status, row count).

FUTURE USE: Can be integrated if client requires:
- Per-stage tracking (extract/transform/load separately)
- Detailed metrics (records_inserted vs records_updated vs records_failed)
- Data lineage tracking
- Enhanced metadata capture

For now, keeping this module for future extensibility but not calling it from ETL scripts.
"""

import os
import uuid
from datetime import datetime
from typing import Optional, Dict, Any
import psycopg2
from psycopg2.extras import Json
import logging

logger = logging.getLogger(__name__)


class AuditLogger:
    """
    Handles audit logging for ETL pipeline runs.
    Tracks execution by tool, stage, status, and metrics.
    
    NOTE: Currently not in use - kept for future enhancement.
    """
    
    def __init__(self, db_connection=None):
        """
        Initialize audit logger with database connection.
        
        Args:
            db_connection: Existing psycopg2 connection, or None to create new
        """
        self.conn = db_connection
        self.should_close = False
        
        if self.conn is None:
            self._create_connection()
            self.should_close = True
    
    def _create_connection(self):
        """Create database connection from environment variables."""
        try:
            self.conn = psycopg2.connect(
                host=os.getenv('DB_HOST'),
                database=os.getenv('DB_NAME', 'appd_licensing'),
                user=os.getenv('DB_USER', 'appd_ro'),
                password=os.getenv('DB_PASSWORD'),
                port=os.getenv('DB_PORT', 5432)
            )
            logger.info("Audit logger connected to database")
        except Exception as e:
            logger.error(f"Failed to connect to database: {e}")
            raise
    
    def start_run(
        self,
        tool_name: str,
        pipeline_stage: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Log the start of an ETL run.
        
        Args:
            tool_name: Name of the tool (e.g., 'appdynamics', 'servicenow')
            pipeline_stage: Stage of pipeline (e.g., 'extract', 'transform', 'load')
            metadata: Optional metadata dictionary
            
        Returns:
            run_id: UUID string for this run
        """
        run_id = str(uuid.uuid4())
        
        try:
            with self.conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO audit_etl_runs (
                        run_id,
                        tool_name,
                        pipeline_stage,
                        start_time,
                        status,
                        metadata
                    ) VALUES (%s, %s, %s, %s, %s, %s)
                """, (
                    run_id,
                    tool_name,
                    pipeline_stage,
                    datetime.now(),
                    'running',
                    Json(metadata) if metadata else None
                ))
                self.conn.commit()
                
            logger.info(f"Started {tool_name} {pipeline_stage} run: {run_id}")
            return run_id
            
        except Exception as e:
            logger.error(f"Failed to log run start: {e}")
            self.conn.rollback()
            raise
    
    def end_run(
        self,
        run_id: str,
        status: str,
        records_processed: Optional[int] = None,
        records_inserted: Optional[int] = None,
        records_updated: Optional[int] = None,
        records_failed: Optional[int] = None,
        error_message: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ):
        """
        Log the completion of an ETL run.
        
        Args:
            run_id: UUID of the run to update
            status: Final status ('success', 'failed', 'partial')
            records_processed: Total records processed
            records_inserted: Records inserted
            records_updated: Records updated
            records_failed: Records that failed
            error_message: Error message if status is 'failed'
            metadata: Optional metadata dictionary
        """
        try:
            with self.conn.cursor() as cur:
                cur.execute("""
                    UPDATE audit_etl_runs
                    SET 
                        end_time = %s,
                        status = %s,
                        records_processed = %s,
                        records_inserted = %s,
                        records_updated = %s,
                        records_failed = %s,
                        error_message = %s,
                        metadata = COALESCE(metadata, '{}'::jsonb) || %s::jsonb
                    WHERE run_id = %s
                """, (
                    datetime.now(),
                    status,
                    records_processed,
                    records_inserted,
                    records_updated,
                    records_failed,
                    error_message,
                    Json(metadata) if metadata else Json({}),
                    run_id
                ))
                self.conn.commit()
                
            logger.info(f"Completed run {run_id} with status: {status}")
            
        except Exception as e:
            logger.error(f"Failed to log run end: {e}")
            self.conn.rollback()
            raise
    
    def log_run(
        self,
        tool_name: str,
        pipeline_stage: str,
        status: str,
        records_processed: Optional[int] = None,
        records_inserted: Optional[int] = None,
        records_updated: Optional[int] = None,
        records_failed: Optional[int] = None,
        error_message: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Convenience method to log a complete run in one call.
        Use this for simple runs or when start/end tracking isn't needed.
        
        Args:
            tool_name: Name of the tool (e.g., 'appdynamics', 'servicenow')
            pipeline_stage: Stage of pipeline
            status: Run status
            records_processed: Total records processed
            records_inserted: Records inserted
            records_updated: Records updated
            records_failed: Records that failed
            error_message: Error message if failed
            metadata: Optional metadata dictionary
            
        Returns:
            run_id: UUID string for this run
        """
        run_id = str(uuid.uuid4())
        
        try:
            with self.conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO audit_etl_runs (
                        run_id,
                        tool_name,
                        pipeline_stage,
                        start_time,
                        end_time,
                        status,
                        records_processed,
                        records_inserted,
                        records_updated,
                        records_failed,
                        error_message,
                        metadata
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    run_id,
                    tool_name,
                    pipeline_stage,
                    datetime.now(),
                    datetime.now(),
                    status,
                    records_processed,
                    records_inserted,
                    records_updated,
                    records_failed,
                    error_message,
                    Json(metadata) if metadata else None
                ))
                self.conn.commit()
                
            logger.info(f"Logged {tool_name} {pipeline_stage} run: {status}")
            return run_id
            
        except Exception as e:
            logger.error(f"Failed to log run: {e}")
            self.conn.rollback()
            raise
    
    def update_tool_last_run(self, tool_name: str):
        """
        Update the last_successful_run timestamp in tool_configurations.
        Call this after a successful ETL run for a tool.
        
        Args:
            tool_name: Name of the tool that completed successfully
        """
        try:
            with self.conn.cursor() as cur:
                cur.execute("""
                    UPDATE tool_configurations
                    SET last_successful_run = %s,
                        updated_at = %s
                    WHERE tool_name = %s
                """, (
                    datetime.now(),
                    datetime.now(),
                    tool_name
                ))
                self.conn.commit()
                
            logger.info(f"Updated last_successful_run for {tool_name}")
            
        except Exception as e:
            logger.warning(f"Failed to update tool_configurations: {e}")
            self.conn.rollback()
    
    def check_tool_active(self, tool_name: str) -> bool:
        """
        Check if a tool is marked as active in tool_configurations.
        
        Args:
            tool_name: Name of the tool to check
            
        Returns:
            True if tool is active, False otherwise
        """
        try:
            with self.conn.cursor() as cur:
                cur.execute("""
                    SELECT is_active 
                    FROM tool_configurations 
                    WHERE tool_name = %s
                """, (tool_name,))
                
                result = cur.fetchone()
                
                if result is None:
                    logger.warning(f"Tool {tool_name} not found in tool_configurations")
                    return False
                
                return result[0]
                
        except Exception as e:
            logger.error(f"Failed to check tool status: {e}")
            return False
    
    def close(self):
        """Close database connection if we created it."""
        if self.should_close and self.conn:
            self.conn.close()
            logger.info("Audit logger connection closed")
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - close connection."""
        self.close()
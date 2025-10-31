# scripts/etl/audit_logger.py
#!/usr/bin/env python3

"""Audit logging utilities for ETL pipeline"""
import json

def log_user_action(conn, user, action_type, target_table, details):
    """Log administrative actions"""
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO user_actions (user_name, action_type, target_table, details)
        VALUES (%s, %s, %s, %s)
    """, (user, action_type, target_table, json.dumps(details)))
    conn.commit()
    cursor.close()

def log_data_lineage(conn, run_id, source_system, target_table, target_pk, action):
    """Log data changes for audit trail"""
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO data_lineage (run_id, source_system, target_table, target_pk, action)
        VALUES (%s, %s, %s, %s, %s)
    """, (run_id, source_system, target_table, json.dumps(target_pk), action))
    conn.commit()
    cursor.close()
#!/usr/bin/env bash
set -euo pipefail

#LOG_DIR="/app/logs"
#LOG_FILE="$LOG_DIR/etl_run_$(date +'%Y%m%d_%H%M%S').log"

#mkdir -p "$LOG_DIR"

#exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Starting ETL pipeline execution at $(date)"
echo "=========================================="

run_step() {
  STEP_NAME="$1"
  SCRIPT_PATH="$2"

  echo ""
  echo "------------------------------------------"
  echo "Running: $STEP_NAME"
  echo "------------------------------------------"

  if python3 "$SCRIPT_PATH"; then
    echo "✅ SUCCESS: $STEP_NAME completed."
  else
 #   echo "❌ ERROR: $STEP_NAME failed. Check log: $LOG_FILE"
    exit 1
  fi
}

run_step "ServiceNow ETL - Loading CMDB data (applications, servers, relationships)" "./scripts/etl/snow_etl.py"
run_step "AppDynamics ETL - Loading usage data and calculating costs" "./scripts/etl/appd_etl.py"
run_step "Reconciliation - Fuzzy matching AppD and ServiceNow applications" "./scripts/etl/reconciliation_engine.py"
run_step "Advanced Forecasting - Generating 12-month projections" "./scripts/etl/advanced_forecasting.py"
run_step "Allocation Engine - Distributing shared service costs" "./scripts/etl/allocation_engine.py"

echo ""
echo "=========================================="
echo "✅ ETL Pipeline Complete at $(date)"
#echo "Logs saved to: $LOG_FILE"
echo "=========================================="

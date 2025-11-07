#!/usr/bin/env python3
"""
ETL Pipeline Orchestrator
Runs all ETL steps in the correct order with error handling
"""
import sys
import os
import subprocess
from datetime import datetime

# Color output
class Colors:
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

def log_step(message, color=Colors.BLUE):
    """Log a pipeline step"""
    print(f"{color}{'='*60}{Colors.NC}")
    print(f"{color}{message}{Colors.NC}")
    print(f"{color}{'='*60}{Colors.NC}")

def run_etl_script(script_name, description):
    """Run an ETL script and handle errors"""
    print(f"\n{Colors.YELLOW}▶ Running: {description}{Colors.NC}")
    
    script_path = f"/app/scripts/etl/{script_name}"
    
    try:
        result = subprocess.run(
            ["python3", script_path],
            check=True,
            capture_output=False,
            text=True
        )
        print(f"{Colors.GREEN}✅ {description} completed successfully{Colors.NC}\n")
        return True
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}❌ {description} failed with exit code {e.returncode}{Colors.NC}")
        return False
    except FileNotFoundError:
        print(f"{Colors.RED}❌ Script not found: {script_path}{Colors.NC}")
        return False
    except Exception as e:
        print(f"{Colors.RED}❌ {description} failed: {str(e)}{Colors.NC}")
        return False

def main():
    """Main pipeline orchestration"""
    log_step("Starting ETL Pipeline", Colors.BLUE)
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Define pipeline steps
    pipeline_steps = [
        ("snow_etl.py", "ServiceNow CMDB Extraction"),
        ("appd_etl.py", "AppDynamics Usage Data Generation"),
        ("reconciliation_engine.py", "Application Reconciliation"),
        ("advanced_forecasting.py", "Usage Forecasting"),
        ("allocation_engine.py", "Cost Allocation"),
    ]
    
    # Track results
    results = []
    
    # Execute each step
    for script_name, description in pipeline_steps:
        success = run_etl_script(script_name, description)
        results.append((description, success))
        
        # Stop on critical failures (snow_etl, appd_etl)
        if not success and script_name in ["snow_etl.py", "appd_etl.py"]:
            log_step("Pipeline Failed - Critical Step Failed", Colors.RED)
            sys.exit(1)
    
    # Run validation
    print(f"\n{Colors.YELLOW}▶ Running: Data Validation{Colors.NC}")
    try:
        from validate_pipeline import validate_pipeline
        validate_pipeline()
        results.append(("Data Validation", True))
        print(f"{Colors.GREEN}✅ Data Validation completed successfully{Colors.NC}\n")
    except Exception as e:
        print(f"{Colors.YELLOW}⚠️  Data Validation failed: {str(e)}{Colors.NC}\n")
        results.append(("Data Validation", False))
    
    # Print summary
    log_step("Pipeline Execution Summary", Colors.BLUE)
    
    success_count = sum(1 for _, success in results if success)
    total_count = len(results)
    
    for description, success in results:
        status = f"{Colors.GREEN}✅ SUCCESS{Colors.NC}" if success else f"{Colors.RED}❌ FAILED{Colors.NC}"
        print(f"  {description:<40} {status}")
    
    print(f"\n{Colors.BLUE}Results: {success_count}/{total_count} steps successful{Colors.NC}")
    print(f"Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Exit with appropriate code
    if success_count == total_count:
        log_step("✅ Pipeline Completed Successfully!", Colors.GREEN)
        sys.exit(0)
    elif success_count >= total_count - 1:
        log_step("⚠️  Pipeline Completed with Warnings", Colors.YELLOW)
        sys.exit(0)
    else:
        log_step("❌ Pipeline Failed", Colors.RED)
        sys.exit(1)

if __name__ == "__main__":
    main()
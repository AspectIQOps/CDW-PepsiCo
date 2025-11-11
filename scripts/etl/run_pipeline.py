#!/usr/bin/env python3
"""
ETL Pipeline Orchestrator
Runs all ETL steps in the correct order with error handling and dependency management
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

def run_etl_script(script_name, description, timeout=300):
    """Run an ETL script and handle errors"""
    print(f"\n{Colors.YELLOW}▶ Running: {description}{Colors.NC}")
    
    script_path = f"/app/scripts/etl/{script_name}"
    
    try:
        result = subprocess.run(
            ["python3", script_path],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        print(result.stdout)
        if result.stderr:
            print(f"{Colors.YELLOW}{result.stderr}{Colors.NC}")
        print(f"{Colors.GREEN}✅ {description} completed successfully{Colors.NC}\n")
        return True
    except subprocess.TimeoutExpired:
        print(f"{Colors.RED}❌ {description} timed out after {timeout} seconds{Colors.NC}")
        return False
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}❌ {description} failed with exit code {e.returncode}{Colors.NC}")
        print(f"STDOUT: {e.stdout}")
        print(f"STDERR: {e.stderr}")
        return False
    except FileNotFoundError:
        print(f"{Colors.RED}❌ Script not found: {script_path}{Colors.NC}")
        return False
    except Exception as e:
        print(f"{Colors.RED}❌ {description} failed: {str(e)}{Colors.NC}")
        return False

def validate_credentials():
    """Validate all required credentials are available"""
    print(f"{Colors.YELLOW}Validating credentials...{Colors.NC}")

    missing = []
    warnings = []
    
    # Track which data sources are available
    has_servicenow = False
    has_appdynamics = False

    # Database credentials (required)
    db_creds = ['DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD']
    for cred in db_creds:
        if not os.getenv(cred):
            missing.append(f"Database: {cred}")

    # ServiceNow credentials (at least one auth method required)
    sn_oauth = os.getenv('SN_CLIENT_ID') and os.getenv('SN_CLIENT_SECRET')
    sn_basic = os.getenv('SN_USER') and os.getenv('SN_PASS')
    sn_instance = os.getenv('SN_INSTANCE')

    if not sn_instance:
        warnings.append("ServiceNow: SN_INSTANCE not configured (will skip ServiceNow ETL)")
    elif not (sn_oauth or sn_basic):
        warnings.append("ServiceNow: No authentication method available (will skip ServiceNow ETL)")
    else:
        has_servicenow = True

    # AppDynamics credentials (optional for now, since appd_etl uses mock data)
    appd_complete = (os.getenv('APPD_CONTROLLER') and os.getenv('APPD_ACCOUNT')
                     and os.getenv('APPD_CLIENT_ID') and os.getenv('APPD_CLIENT_SECRET'))

    if appd_complete:
        has_appdynamics = True
    else:
        warnings.append("AppDynamics: Credentials incomplete (using mock data)")

    # Print results
    if missing:
        print(f"{Colors.RED}✗ Missing required credentials:{Colors.NC}")
        for item in missing:
            print(f"  - {item}")
        return False, has_servicenow, has_appdynamics

    if warnings:
        print(f"{Colors.YELLOW}⚠ Warnings:{Colors.NC}")
        for item in warnings:
            print(f"  - {item}")

    print(f"{Colors.GREEN}✓ Core credentials validated{Colors.NC}")
    return True, has_servicenow, has_appdynamics

def main():
    """Main pipeline orchestration"""
    log_step("Starting ETL Pipeline", Colors.BLUE)
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    # Validate credentials before starting
    creds_valid, has_servicenow, has_appdynamics = validate_credentials()
    
    if not creds_valid:
        log_step("Pipeline Aborted - Missing Required Credentials", Colors.RED)
        print(f"\n{Colors.RED}Please ensure all required credentials are loaded via entrypoint.sh{Colors.NC}")
        print(f"{Colors.RED}Or set them in AWS SSM Parameter Store at /pepsico/*{Colors.NC}\n")
        sys.exit(1)

    print()

    # Define pipeline steps with dependency information
    pipeline_steps = []
    
    # Step 1: ServiceNow (if available) - MUST run first as it populates applications_dim
    if has_servicenow:
        pipeline_steps.append({
            'script': 'snow_etl.py',
            'description': 'ServiceNow CMDB Extraction',
            'critical': True,
            'reason': 'Loads applications_dim which is required for all downstream steps'
        })
    else:
        print(f"{Colors.YELLOW}⊘ Skipping ServiceNow ETL (credentials not configured){Colors.NC}\n")
    
    # Step 2: AppDynamics - Depends on applications_dim
    pipeline_steps.append({
        'script': 'appd_etl.py',
        'description': 'AppDynamics Usage Data Generation',
        'critical': True,
        'reason': 'Generates usage data for cost allocation'
    })
    
    # Step 3: Reconciliation - Depends on both ServiceNow and AppDynamics data
    pipeline_steps.append({
        'script': 'reconciliation_engine.py',
        'description': 'Application Reconciliation',
        'critical': False,
        'reason': 'Improves data quality but not blocking'
    })
    
    # Step 4: Forecasting - Depends on usage data
    pipeline_steps.append({
        'script': 'advanced_forecasting.py',
        'description': 'Usage Forecasting',
        'critical': False,
        'reason': 'Provides predictive insights'
    })
    
    # Step 5: Cost Allocation - Depends on all upstream data
    pipeline_steps.append({
        'script': 'allocation_engine.py',
        'description': 'Cost Allocation',
        'critical': False,
        'reason': 'Final cost calculations'
    })
    
    # Track results
    results = []
    
    # Execute each step
    for step in pipeline_steps:
        success = run_etl_script(step['script'], step['description'])
        results.append((step['description'], success))
        
        # Stop on critical failures
        if not success and step['critical']:
            log_step(f"Pipeline Failed - Critical Step Failed", Colors.RED)
            print(f"{Colors.RED}Reason: {step['reason']}{Colors.NC}")
            print(f"{Colors.RED}Cannot continue without this data.{Colors.NC}\n")
            sys.exit(1)
        elif not success:
            print(f"{Colors.YELLOW}⚠ Non-critical step failed, continuing...{Colors.NC}")
            print(f"{Colors.YELLOW}Note: {step['reason']}{Colors.NC}\n")
    
    # Run validation
    print(f"\n{Colors.YELLOW}▶ Running: Data Validation{Colors.NC}")
    try:
        # Add /app to Python path so imports work
        sys.path.insert(0, '/app')
        from scripts.utils.validate_pipeline import validate_pipeline
        validate_pipeline()
        results.append(("Data Validation", True))
        print(f"{Colors.GREEN}✅ Data Validation completed successfully{Colors.NC}\n")
    except ImportError as e:
        print(f"{Colors.YELLOW}⚠️ Data Validation module not found: {str(e)}{Colors.NC}")
        print(f"{Colors.YELLOW}Skipping validation step{Colors.NC}\n")
        results.append(("Data Validation", None))
    except Exception as e:
        print(f"{Colors.YELLOW}⚠️ Data Validation failed: {str(e)}{Colors.NC}\n")
        results.append(("Data Validation", False))
    
    # Print summary
    log_step("Pipeline Execution Summary", Colors.BLUE)
    
    success_count = sum(1 for _, success in results if success is True)
    failed_count = sum(1 for _, success in results if success is False)
    skipped_count = sum(1 for _, success in results if success is None)
    total_count = len(results)
    
    for description, success in results:
        if success is True:
            status = f"{Colors.GREEN}✅ SUCCESS{Colors.NC}"
        elif success is False:
            status = f"{Colors.RED}❌ FAILED{Colors.NC}"
        else:
            status = f"{Colors.YELLOW}⊘ SKIPPED{Colors.NC}"
        print(f"  {description:<40} {status}")
    
    print(f"\n{Colors.BLUE}Results: {success_count}/{total_count} steps successful", end="")
    if failed_count > 0:
        print(f", {failed_count} failed", end="")
    if skipped_count > 0:
        print(f", {skipped_count} skipped", end="")
    print(f"{Colors.NC}")
    print(f"Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Exit with appropriate code
    if success_count == total_count:
        log_step("✅ Pipeline Completed Successfully!", Colors.GREEN)
        sys.exit(0)
    elif failed_count == 0:
        log_step("✅ Pipeline Completed (Some Steps Skipped)", Colors.GREEN)
        sys.exit(0)
    elif success_count >= total_count - failed_count:
        log_step("⚠️ Pipeline Completed with Warnings", Colors.YELLOW)
        sys.exit(0)
    else:
        log_step("❌ Pipeline Failed", Colors.RED)
        sys.exit(1)

if __name__ == "__main__":
    main()
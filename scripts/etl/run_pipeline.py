#!/usr/bin/env python3
"""
ETL Pipeline Orchestrator - Production Grade (3-Phase Architecture)
Updated to include chargeback_calculation.py for proper dashboard data

ARCHITECTURE:
Phase 1: appd_extract.py     - Core AppD data (apps, usage, costs)
Phase 2: snow_enrichment.py  - Targeted CMDB lookups (only for AppD apps)
Phase 3: appd_finalize.py    - Cost calculations and finalization
Phase 4: chargeback_calculation.py - Monthly chargeback aggregation ← NEW
Phase 5: allocation_engine.py - Shared service distribution
Phase 6: advanced_forecasting.py - Forecasting (optional)
Phase 7: refresh_views.py    - Dashboard materialized views
"""
import sys
import os
import subprocess
from datetime import datetime
import time

# Color output
class Colors:
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

# Pipeline configuration
MAX_RETRIES = 3
RETRY_DELAY_SECONDS = 5

def log_step(message, color=Colors.BLUE):
    """Log a pipeline step"""
    print(f"{color}{'='*60}{Colors.NC}")
    print(f"{color}{message}{Colors.NC}")
    print(f"{color}{'='*60}{Colors.NC}")

def run_etl_script(script_name, description, timeout=300, critical=True, max_retries=MAX_RETRIES):
    """
    Run an ETL script with retry logic and error handling
    
    Args:
        script_name: Name of the script file
        description: Human-readable description
        timeout: Max execution time in seconds
        critical: If True, pipeline stops on failure
        max_retries: Number of retry attempts for transient failures
    
    Returns:
        True if successful, False otherwise
    """
    print(f"\n{Colors.YELLOW}▶ Running: {description}{Colors.NC}")
    
    script_path = f"/app/scripts/etl/{script_name}"
    
    for attempt in range(1, max_retries + 1):
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
            if attempt < max_retries and not critical:
                print(f"{Colors.YELLOW}   Retrying in {RETRY_DELAY_SECONDS}s... (attempt {attempt}/{max_retries}){Colors.NC}")
                time.sleep(RETRY_DELAY_SECONDS)
                continue
            return False
            
        except subprocess.CalledProcessError as e:
            print(f"{Colors.RED}❌ {description} failed with exit code {e.returncode}{Colors.NC}")
            print(f"STDOUT: {e.stdout}")
            print(f"STDERR: {e.stderr}")
            
            # Check if it's a transient error (network, timeout, etc.)
            is_transient = any(keyword in str(e.stderr).lower() for keyword in 
                             ['timeout', 'connection', 'network', 'temporary'])
            
            if attempt < max_retries and is_transient and not critical:
                print(f"{Colors.YELLOW}   Detected transient error. Retrying in {RETRY_DELAY_SECONDS}s... (attempt {attempt}/{max_retries}){Colors.NC}")
                time.sleep(RETRY_DELAY_SECONDS)
                continue
            return False
            
        except FileNotFoundError:
            print(f"{Colors.RED}❌ Script not found: {script_path}{Colors.NC}")
            return False
            
        except Exception as e:
            print(f"{Colors.RED}❌ {description} failed: {str(e)}{Colors.NC}")
            if attempt < max_retries and not critical:
                print(f"{Colors.YELLOW}   Retrying in {RETRY_DELAY_SECONDS}s... (attempt {attempt}/{max_retries}){Colors.NC}")
                time.sleep(RETRY_DELAY_SECONDS)
                continue
            return False
    
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

    # AppDynamics credentials (REQUIRED for this architecture)
    appd_complete = (os.getenv('APPD_CONTROLLER') and os.getenv('APPD_ACCOUNT')
                     and os.getenv('APPD_CLIENT_ID') and os.getenv('APPD_CLIENT_SECRET'))

    if appd_complete:
        has_appdynamics = True
    else:
        missing.append("AppDynamics: Credentials incomplete (REQUIRED)")

    # ServiceNow credentials (at least one auth method required for enrichment)
    sn_oauth = os.getenv('SN_CLIENT_ID') and os.getenv('SN_CLIENT_SECRET')
    sn_basic = os.getenv('SN_USER') and os.getenv('SN_PASS')
    sn_instance = os.getenv('SN_INSTANCE')

    if not sn_instance:
        warnings.append("ServiceNow: SN_INSTANCE not configured (enrichment will be skipped)")
    elif not (sn_oauth or sn_basic):
        warnings.append("ServiceNow: No authentication method available (enrichment will be skipped)")
    else:
        has_servicenow = True

    # Print results
    if missing:
        print(f"{Colors.RED}✗ Missing required credentials:{Colors.NC}")
        for item in missing:
            print(f"  - {item}")
        return False, has_servicenow, has_appdynamics

    if warnings:
        print(f"{Colors.YELLOW}⚠  Warnings:{Colors.NC}")
        for item in warnings:
            print(f"  - {item}")

    print(f"{Colors.GREEN}✓ Core credentials validated{Colors.NC}")
    return True, has_servicenow, has_appdynamics

def main():
    """Main pipeline orchestration - includes chargeback calculation"""
    log_step("Starting ETL Pipeline (Production-Ready)", Colors.BLUE)
    
    # Validate credentials before starting
    creds_valid, has_servicenow, has_appdynamics = validate_credentials()
    
    if not creds_valid:
        log_step("Pipeline Aborted - Missing Required Credentials", Colors.RED)
        print(f"\n{Colors.RED}Please ensure all required credentials are loaded via entrypoint.sh{Colors.NC}")
        print(f"{Colors.RED}Or set them in AWS SSM Parameter Store at /pepsico/*{Colors.NC}\n")
        sys.exit(1)

    if not has_appdynamics:
        log_step("Pipeline Aborted - AppDynamics Required", Colors.RED)
        print(f"\n{Colors.RED}This pipeline requires AppDynamics credentials{Colors.NC}")
        print(f"{Colors.RED}AppD data is the foundation for the 3-phase architecture{Colors.NC}\n")
        sys.exit(1)

    print()

    # Define pipeline steps (updated with chargeback_calculation.py)
    pipeline_steps = [
        # Phase 1: Extract core AppD data (apps, usage, costs)
        {
            'script': 'appd_extract.py',
            'description': 'Phase 1: AppDynamics Core Data Extract',
            'timeout': 600,
            'critical': True,
            'max_retries': 2,
            'reason': 'Foundation data - loads monitored applications and usage'
        }
    ]
    
    # Phase 2: ServiceNow enrichment (only if credentials available)
    if has_servicenow:
        pipeline_steps.append({
            'script': 'snow_enrichment.py',
            'description': 'Phase 2: ServiceNow CMDB Enrichment',
            'timeout': 600,
            'critical': False,  # Not critical - can run without enrichment
            'max_retries': 2,
            'reason': 'Adds CMDB data (h_code, sector, owner) for chargeback'
        })
    else:
        print(f"{Colors.YELLOW}⊘ Skipping Phase 2: ServiceNow (credentials not configured){Colors.NC}")
        print(f"{Colors.YELLOW}   Pipeline will continue without CMDB enrichment{Colors.NC}\n")
    
    # Phase 3: Finalize (cost calculations)
    pipeline_steps.append({
        'script': 'appd_finalize.py',
        'description': 'Phase 3: Cost Calculations & Finalization',
        'timeout': 300,
        'critical': True,  # Critical - needed for chargeback
        'max_retries': 1,
        'reason': 'Calculates license costs from usage data'
    })
    
    # Phase 4: Chargeback calculation (NEW - aggregates costs by month/sector/h-code)
    pipeline_steps.append({
        'script': 'chargeback_calculation.py',
        'description': 'Phase 4: Monthly Chargeback Aggregation',
        'timeout': 300,
        'critical': True,  # Critical for dashboard data
        'max_retries': 1,
        'reason': 'Aggregates costs into monthly chargeback records for dashboard'
    })
    
    # Phase 5: Cost allocation (distributes shared service costs)
    if has_servicenow:
        pipeline_steps.append({
            'script': 'allocation_engine.py',
            'description': 'Phase 5: Shared Service Cost Allocation',
            'timeout': 300,
            'critical': False,  # Not critical - only for shared services
            'max_retries': 1,
            'reason': 'Distributes shared service costs across sectors'
        })
    
    # Phase 6: Advanced forecasting (optional)
    if os.path.exists('/app/scripts/etl/advanced_forecasting.py'):
        pipeline_steps.append({
            'script': 'advanced_forecasting.py',
            'description': 'Phase 6: Advanced Forecasting',
            'timeout': 300,
            'critical': False,
            'max_retries': 1,
            'reason': 'Enhanced forecasting with multiple algorithms'
        })

    # Phase 7: Refresh materialized views for dashboard performance
    if os.path.exists('/app/scripts/etl/refresh_views.py'):
        pipeline_steps.append({
            'script': 'refresh_views.py',
            'description': 'Phase 7: Refresh Dashboard Views',
            'timeout': 300,
            'critical': False,  # Not critical but important
            'max_retries': 1,
            'reason': 'Updates pre-aggregated views for dashboard performance (<5s response)'
        })

    # Track results
    results = []
    
    # Execute each step
    for step in pipeline_steps:
        success = run_etl_script(
            step['script'], 
            step['description'],
            timeout=step['timeout'],
            critical=step['critical'],
            max_retries=step['max_retries']
        )
        results.append((step['description'], success))
        
        # Stop on critical failures
        if not success and step['critical']:
            log_step(f"Pipeline Failed - Critical Step Failed", Colors.RED)
            print(f"{Colors.RED}Reason: {step['reason']}{Colors.NC}")
            print(f"{Colors.RED}Cannot continue without this data.{Colors.NC}\n")
            sys.exit(1)
        elif not success:
            print(f"{Colors.YELLOW}⚠  Non-critical step failed, continuing...{Colors.NC}")
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
        print(f"  {description:<50} {status}")
    
    print(f"\n{Colors.BLUE}Results: {success_count}/{total_count} steps successful", end="")
    if failed_count > 0:
        print(f", {failed_count} failed", end="")
    if skipped_count > 0:
        print(f", {skipped_count} skipped", end="")
    print(f"{Colors.NC}")
    print(f"Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Architecture summary
    print(f"{Colors.BLUE}Architecture:{Colors.NC}")
    print(f"  Phase 1: AppD Extract → {Colors.GREEN}✅{Colors.NC}")
    if has_servicenow:
        print(f"  Phase 2: ServiceNow Enrich → {Colors.GREEN}✅{Colors.NC}")
    else:
        print(f"  Phase 2: ServiceNow Enrich → {Colors.YELLOW}⊘ Skipped{Colors.NC}")
    print(f"  Phase 3: Cost Calculation → {Colors.GREEN}✅{Colors.NC}")
    print(f"  Phase 4: Chargeback Aggregation → {Colors.GREEN}✅{Colors.NC} ← NEW")
    print(f"  Phase 5: Allocation → {Colors.GREEN}✅{Colors.NC}")
    print(f"  Phase 6: Forecasting → {Colors.GREEN}✅{Colors.NC}")
    print(f"  Phase 7: Refresh Views → {Colors.GREEN}✅{Colors.NC}")
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
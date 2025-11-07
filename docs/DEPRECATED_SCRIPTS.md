# Deprecated Scripts

These scripts have been consolidated into `platform_manager.sh` and can be safely deleted after verifying the new script works.

## Scripts to Delete

### ✅ Replaced by `platform_manager.sh`

| Old Script | New Command | Notes |
|------------|-------------|-------|
| `scripts/utils/daily_startup.sh` | `platform_manager.sh start` | Starts ETL pipeline |
| `scripts/utils/daily_teardown.sh` | `platform_manager.sh stop` | Stops all containers |
| `scripts/utils/teardown_docker_stack.sh` | `platform_manager.sh stop` | Same functionality as daily_teardown |
| `scripts/utils/health_check.sh` | `platform_manager.sh health` | Comprehensive health checks |
| `scripts/utils/verify_setup.sh` | `platform_manager.sh status` | System status and verification |

### ⚠️ Keep These Scripts

| Script | Reason |
|--------|--------|
| `scripts/utils/validate_pipeline.py` | Called by `platform_manager.sh validate` - still needed |
| `scripts/setup/*` | Setup scripts used for initial deployment - keep all |

---

## Migration Steps

### 1. Test New Script First

```bash
# Make executable
chmod +x scripts/utils/platform_manager.sh

# Test all commands
./scripts/utils/platform_manager.sh health
./scripts/utils/platform_manager.sh status
./scripts/utils/platform_manager.sh start
./scripts/utils/platform_manager.sh logs
./scripts/utils/platform_manager.sh stop
```

### 2. Update Any Cron Jobs or Scripts

If you have any automation that calls the old scripts, update them:

```bash
# Old
./scripts/utils/daily_startup.sh

# New
./scripts/utils/platform_manager.sh start
```

### 3. Delete Old Scripts

```bash
# Once verified, delete deprecated scripts
rm scripts/utils/daily_startup.sh
rm scripts/utils/daily_teardown.sh
rm scripts/utils/teardown_docker_stack.sh
rm scripts/utils/health_check.sh
rm scripts/utils/verify_setup.sh
```

---

## Functionality Mapping

### daily_startup.sh → platform_manager.sh start
- Verifies SSM parameters
- Checks if already running
- Builds and starts containers
- Shows monitoring commands

### daily_teardown.sh + teardown_docker_stack.sh → platform_manager.sh stop
- Stops all containers
- Removes containers cleanly
- Single consolidated command

### health_check.sh → platform_manager.sh health
- Docker status check
- AWS CLI and IAM check
- PostgreSQL client check
- SSM parameters verification
- Database connectivity test
- Required tables check
- Disk space check

### verify_setup.sh → platform_manager.sh status
- Container status
- Database connection info
- Table counts
- Recent ETL runs
- Active tools
- SSM parameter count

### NEW: Additional Commands

```bash
platform_manager.sh restart   # Stop + Start
platform_manager.sh validate  # Run data validation
platform_manager.sh logs      # Follow container logs
platform_manager.sh clean     # Cleanup old logs and containers
platform_manager.sh db        # Connect to database
platform_manager.sh ssm       # List SSM parameters
```

---

## Benefits of Consolidation

✅ **Single script to remember** - One command for all operations
✅ **Consistent interface** - All commands follow same pattern  
✅ **Better error handling** - Unified error messages and exit codes  
✅ **Easier maintenance** - Update logic in one place  
✅ **More features** - Added restart, clean, db, ssm commands  
✅ **Color-coded output** - Better visibility of status  

---

## Rollback Plan

If you need to revert:

1. The old scripts still exist in your git history
2. Checkout previous commit: `git checkout HEAD~1 -- scripts/utils/`
3. Or restore from backup if you created one

---

## Testing Checklist

Before deleting old scripts, verify:

- [ ] `platform_manager.sh start` starts containers successfully
- [ ] `platform_manager.sh stop` stops containers cleanly
- [ ] `platform_manager.sh health` shows all checks passing
- [ ] `platform_manager.sh status` displays correct info
- [ ] `platform_manager.sh logs` follows container output
- [ ] `platform_manager.sh validate` runs Python validation
- [ ] `platform_manager.sh db` connects to database
- [ ] All functionality from old scripts is present

---

**Once all checks pass, safe to delete deprecated scripts!**
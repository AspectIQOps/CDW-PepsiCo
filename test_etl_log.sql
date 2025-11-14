-- Test ETL Execution Log Data
-- Run this to diagnose Admin Panel dashboard issues

-- 1. Check if any ETL runs exist
SELECT 'Total ETL Runs' as test, COUNT(*) as count FROM etl_execution_log;

-- 2. Check runs in last 7 days
SELECT 'Runs in Last 7 Days' as test, COUNT(*) as count
FROM etl_execution_log
WHERE started_at >= NOW() - INTERVAL '7 days';

-- 3. Show actual timestamps and status
SELECT
    run_id,
    job_name,
    started_at,
    finished_at,
    status,
    NOW() - started_at as age,
    CASE
        WHEN started_at >= NOW() - INTERVAL '7 days' THEN 'Within 7 days'
        ELSE 'Older than 7 days'
    END as recency
FROM etl_execution_log
ORDER BY started_at DESC
LIMIT 20;

-- 4. Test the "Last 7 Days ETL Status" query
SELECT
    CASE
        WHEN COUNT(*) = 0 THEN 'no data'
        WHEN COUNT(*) FILTER (WHERE status = 'success') = COUNT(*) THEN 'success'
        WHEN COUNT(*) FILTER (WHERE status = 'failed') > 0 THEN 'failed'
        ELSE 'partial'
    END as "ETL Status",
    COUNT(*) as total_runs,
    COUNT(*) FILTER (WHERE status = 'success') as success_count,
    COUNT(*) FILTER (WHERE status = 'failed') as failed_count,
    COUNT(*) FILTER (WHERE status = 'partial') as partial_count
FROM etl_execution_log
WHERE started_at >= NOW() - INTERVAL '7 days';

-- 5. Test the time-series query (should show runs by day)
SELECT
    DATE_TRUNC('day', started_at) as time,
    status as metric,
    COUNT(*) as value
FROM etl_execution_log
WHERE started_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('day', started_at), status
ORDER BY time, status;

-- 6. Check for timezone issues
SELECT
    started_at,
    started_at::timestamptz as with_tz,
    NOW() as now_timestamp,
    NOW()::timestamptz as now_with_tz,
    CURRENT_TIMESTAMP as current_ts
FROM etl_execution_log
LIMIT 5;

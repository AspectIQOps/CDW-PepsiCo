#!/usr/bin/env python3
"""
Advanced Forecasting Engine with Multiple Algorithms
Implements linear regression, exponential smoothing, and ensemble methods
"""
import psycopg2
import numpy as np
from datetime import datetime, timedelta
from scipy import stats
import os

DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_NAME = os.getenv('DB_NAME', 'appd_licensing')
DB_USER = os.getenv('DB_USER', 'appd_ro')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'appd_pass')

def get_conn():
    return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)

def linear_regression_forecast(usage_history, periods=12):
    """
    Linear trend-based forecasting
    Returns: projected values and confidence intervals
    """
    if len(usage_history) < 7:
        return None, None, None
    
    # FIX: Convert to numpy arrays explicitly with proper dtype
    x = np.arange(len(usage_history), dtype=np.float64)
    y = np.array(usage_history, dtype=np.float64)
    
    # Check for constant values (zero variance) - causes linregress to fail
    if np.std(y) == 0:
        # If all values are the same, just return that constant
        constant_value = y[0]
        projections = np.full(periods, constant_value, dtype=np.float64)
        return projections, projections, projections
    
    # Linear regression: y = mx + b
    slope, intercept, r_value, p_value, std_err = stats.linregress(x, y)
    
    # Project future values
    future_x = np.arange(len(usage_history), len(usage_history) + periods, dtype=np.float64)
    projections = slope * future_x + intercept
    
    # Calculate confidence intervals (95%)
    prediction_std = std_err * np.sqrt(1 + 1/len(x) + (future_x - np.mean(x))**2 / np.sum((x - np.mean(x))**2))
    ci_high = projections + 1.96 * prediction_std
    ci_low = projections - 1.96 * prediction_std
    
    return projections, ci_low, ci_high

def exponential_smoothing(usage_history, alpha=0.3, periods=12):
    """
    Exponential smoothing for trend forecasting
    alpha: smoothing factor (0-1)
    """
    if len(usage_history) < 2:
        return None, None, None
    
    # FIX: Convert to numpy array explicitly
    usage_array = np.array(usage_history, dtype=np.float64)
    
    # Simple exponential smoothing
    smoothed = [usage_array[0]]
    for i in range(1, len(usage_array)):
        smoothed.append(alpha * usage_array[i] + (1 - alpha) * smoothed[i-1])
    
    # Project forward
    last_value = smoothed[-1]
    trend = (smoothed[-1] - smoothed[-2]) if len(smoothed) > 1 else 0
    
    projections = []
    for i in range(periods):
        projections.append(last_value + trend * (i + 1))
    
    # Confidence intervals based on historical variance
    std_dev = np.std(usage_array)
    ci_low = [p - 1.96 * std_dev for p in projections]
    ci_high = [p + 1.96 * std_dev for p in projections]
    
    return np.array(projections, dtype=np.float64), np.array(ci_low, dtype=np.float64), np.array(ci_high, dtype=np.float64)

def seasonal_decomposition(usage_history, period=30):
    """
    Detect and account for seasonal patterns
    period: seasonality cycle (e.g., 30 days for monthly patterns)
    """
    if len(usage_history) < period * 2:
        return None
    
    # Convert to numpy array
    usage_array = np.array(usage_history, dtype=np.float64)
    
    # Simple moving average for trend
    trend = np.convolve(usage_array, np.ones(period)/period, mode='valid')
    
    # Detrended series
    detrended = usage_array[len(usage_array)-len(trend):] - trend
    
    # Seasonal component (average pattern over cycles)
    seasonal = []
    for i in range(period):
        seasonal.append(np.mean(detrended[i::period]))
    
    return seasonal

def ensemble_forecast(usage_history, periods=12):
    """
    Combine multiple forecasting methods for improved accuracy
    """
    linear_proj, linear_low, linear_high = linear_regression_forecast(usage_history, periods)
    exp_proj, exp_low, exp_high = exponential_smoothing(usage_history, periods=periods)
    
    if linear_proj is None or exp_proj is None:
        return None, None, None
    
    # Weighted average (60% linear, 40% exponential)
    ensemble_proj = 0.6 * linear_proj + 0.4 * exp_proj
    ensemble_low = 0.6 * linear_low + 0.4 * exp_low
    ensemble_high = 0.6 * linear_high + 0.4 * exp_high
    
    return ensemble_proj, ensemble_low, ensemble_high

def generate_advanced_forecasts(conn):
    """
    Generate forecasts using multiple algorithms for all applications
    """
    cursor = conn.cursor()
    
    print("📈 Generating advanced forecasts...")
    
    # Get applications with sufficient history (90+ days)
    cursor.execute("""
        SELECT DISTINCT app_id, capability_id, tier
        FROM license_usage_fact
        WHERE ts >= NOW() - INTERVAL '90 days'
        GROUP BY app_id, capability_id, tier
        HAVING COUNT(*) >= 30
    """)
    
    app_capability_pairs = cursor.fetchall()
    
    if not app_capability_pairs:
        print("⚠️  No applications with sufficient history (30+ days) for forecasting")
        cursor.close()
        return 0
    
    print(f"Found {len(app_capability_pairs)} app/capability pairs to forecast")
    forecast_count = 0
    
    for app_id, capability_id, tier in app_capability_pairs:
        # Get historical usage
        cursor.execute("""
            SELECT DATE(ts), AVG(units_consumed)
            FROM license_usage_fact
            WHERE app_id = %s 
              AND capability_id = %s 
              AND tier = %s
              AND ts >= NOW() - INTERVAL '90 days'
            GROUP BY DATE(ts)
            ORDER BY DATE(ts)
        """, (app_id, capability_id, tier))
        
        history = [float(row[1]) for row in cursor.fetchall()]
        
        if len(history) < 30:
            continue
        
        # Generate ensemble forecast
        projections, ci_low, ci_high = ensemble_forecast(history, periods=12)
        
        if projections is None:
            continue
        
        # Get current pricing for cost projection
        cursor.execute("""
            SELECT unit_rate FROM price_config
            WHERE capability_id = %s
              AND tier = %s
              AND NOW()::date BETWEEN start_date AND COALESCE(end_date, NOW()::date)
            LIMIT 1
        """, (capability_id, tier))
        
        price_row = cursor.fetchone()
        unit_rate = price_row[0] if price_row else 0.50
        
        # Insert forecasts for next 12 months
        base_date = datetime.now().replace(day=1)
        for i in range(12):
            month_start = (base_date + timedelta(days=32*i)).replace(day=1)
            
            cursor.execute("""
                INSERT INTO forecast_fact 
                (month_start, app_id, capability_id, tier, 
                 projected_units, projected_cost, 
                 confidence_interval_low, confidence_interval_high, method)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (month_start, app_id, capability_id, tier) 
                DO UPDATE SET
                    projected_units = EXCLUDED.projected_units,
                    projected_cost = EXCLUDED.projected_cost,
                    confidence_interval_low = EXCLUDED.confidence_interval_low,
                    confidence_interval_high = EXCLUDED.confidence_interval_high,
                    method = EXCLUDED.method
            """, (
                month_start.date(),
                app_id,
                capability_id,
                tier,
                round(float(projections[i]) * 30, 2),  # Daily to monthly
                round(float(projections[i]) * 30 * float(unit_rate), 2),
                round(float(ci_low[i]) * 30, 2),
                round(float(ci_high[i]) * 30, 2),
                'ensemble_linear_exp'
            ))
            
            forecast_count += 1
    
    conn.commit()
    cursor.close()
    
    print(f"✅ Generated {forecast_count} forecast records using ensemble method")
    return forecast_count

def validate_forecast_accuracy(conn):
    """
    Back-test forecast accuracy against historical data
    """
    cursor = conn.cursor()
    
    print("🔍 Validating forecast accuracy...")
    
    # Compare forecasts made 30 days ago with actual usage
    cursor.execute("""
        WITH forecast_comparison AS (
            SELECT 
                f.app_id,
                f.capability_id,
                f.projected_units,
                COALESCE(SUM(u.units_consumed), 0) as actual_units
            FROM forecast_fact f
            LEFT JOIN license_usage_fact u 
                ON u.app_id = f.app_id
                AND u.capability_id = f.capability_id
                AND DATE_TRUNC('month', u.ts) = f.month_start
            WHERE f.month_start = DATE_TRUNC('month', NOW() - INTERVAL '1 month')
            GROUP BY f.app_id, f.capability_id, f.projected_units
        )
        SELECT 
            AVG(ABS(projected_units - actual_units) / NULLIF(actual_units, 0) * 100) as mape,
            COUNT(*) as sample_size
        FROM forecast_comparison
        WHERE actual_units > 0
    """)
    
    result = cursor.fetchone()
    if result and result[1] > 0:
        mape = result[0]
        print(f"✅ Forecast MAPE (Mean Absolute Percentage Error): {mape:.2f}%")
        print(f"   Sample size: {result[1]} forecasts validated")
    else:
        print("⚠️  Insufficient data for forecast validation")
    
    cursor.close()

if __name__ == '__main__':
    conn = get_conn()
    try:
        generate_advanced_forecasts(conn)
        validate_forecast_accuracy(conn)
    finally:
        conn.close()
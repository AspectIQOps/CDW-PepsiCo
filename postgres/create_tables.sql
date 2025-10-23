-- Capabilities dimension
CREATE TABLE IF NOT EXISTS capabilities_dim (
    capability_id SERIAL PRIMARY KEY,
    capability_code TEXT UNIQUE NOT NULL,
    description TEXT
);

-- Applications dimension
CREATE TABLE IF NOT EXISTS applications_dim (
    app_id SERIAL PRIMARY KEY,
    appd_application_id INT,
    appd_application_name TEXT,
    sn_sys_id TEXT,
    sn_service_name TEXT,
    h_code TEXT,
    sector TEXT
);

-- Time dimension
CREATE TABLE IF NOT EXISTS time_dim (
    ts TIMESTAMP PRIMARY KEY,
    y INT,
    m INT,
    d INT,
    yyyy_mm TEXT
);

-- License usage fact
CREATE TABLE IF NOT EXISTS license_usage_fact (
    ts TIMESTAMP NOT NULL,
    app_id INT REFERENCES applications_dim(app_id),
    capability_id INT REFERENCES capabilities_dim(capability_id),
    tier TEXT,
    units NUMERIC,
    nodes INT,
    PRIMARY KEY(ts, app_id, capability_id, tier)
);

-- License cost fact
CREATE TABLE IF NOT EXISTS license_cost_fact (
    ts TIMESTAMP,
    app_id INT REFERENCES applications_dim(app_id),
    capability_id INT REFERENCES capabilities_dim(capability_id),
    tier TEXT,
    usd_cost NUMERIC,
    PRIMARY KEY(ts, app_id, capability_id, tier)
);

-- Chargeback fact
CREATE TABLE IF NOT EXISTS chargeback_fact (
    month_start DATE,
    app_id INT REFERENCES applications_dim(app_id),
    h_code TEXT,
    sector TEXT,
    usd_amount NUMERIC,
    PRIMARY KEY(month_start, app_id)
);

-- Forecast fact
CREATE TABLE IF NOT EXISTS forecast_fact (
    month_start DATE,
    app_id INT REFERENCES applications_dim(app_id),
    capability_id INT REFERENCES capabilities_dim(capability_id),
    tier TEXT,
    projected_units NUMERIC,
    projected_cost NUMERIC,
    method TEXT,
    PRIMARY KEY(month_start, app_id, capability_id, tier)
);

-- ETL execution log for auditing
CREATE TABLE IF NOT EXISTS etl_execution_log (
    run_id SERIAL PRIMARY KEY,
    job_name TEXT,
    started_at TIMESTAMP DEFAULT now(),
    finished_at TIMESTAMP,
    status TEXT,
    rows_ingested INT,
    error_msg TEXT
);

-- Data lineage
CREATE TABLE IF NOT EXISTS data_lineage (
    lineage_id SERIAL PRIMARY KEY,
    run_id INT REFERENCES etl_execution_log(run_id),
    source_system TEXT,
    source_endpoint TEXT,
    target_table TEXT,
    target_pk JSONB
);

-- Mapping overrides
CREATE TABLE IF NOT EXISTS mapping_overrides (
    override_id SERIAL PRIMARY KEY,
    source TEXT,
    source_key TEXT,
    h_code_override TEXT,
    sector_override TEXT
);

-- Create schema
create schema if not exists appd;
set search_path=appd,public;

-- Applications dimension
create table applications_dim (
  app_id bigserial primary key,
  appd_application_id integer,
  appd_application_name text not null,
  sn_sys_id text,
  sn_service_name text,
  owner_primary text,
  owner_secondary text,
  sector text,
  h_code text,
  architecture text check (architecture in ('Monolith','Microservices')),
  tags jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Capabilities dimension
create table capabilities_dim (
  capability_id smallserial primary key,
  capability_code text unique not null,
  description text
);

-- Time dimension
create table time_dim (
  ts timestamptz primary key,
  y smallint,
  m smallint,
  d smallint,
  yyyy_mm text
);

-- License usage fact
create table license_usage_fact (
  ts timestamptz not null references time_dim(ts),
  app_id bigint references applications_dim(app_id),
  capability_id smallint references capabilities_dim(capability_id),
  tier text check (tier in ('PRO','PEAK')) default 'PRO',
  units numeric(18,6) not null,
  nodes integer,
  page_views bigint,
  synthetic_blocks integer,
  primary key (ts, app_id, capability_id, tier)
);

-- License cost fact
create table license_cost_fact (
  ts timestamptz not null references time_dim(ts),
  app_id bigint references applications_dim(app_id),
  capability_id smallint references capabilities_dim(capability_id),
  tier text,
  usd_cost numeric(18,6) not null,
  primary key (ts, app_id, capability_id, tier)
);

-- Chargeback fact
create table chargeback_fact (
  month_start date not null,
  app_id bigint references applications_dim(app_id),
  h_code text,
  sector text,
  usd_amount numeric(18,6) not null,
  primary key (month_start, app_id)
);

-- Forecast fact
create table forecast_fact (
  month_start date not null,
  app_id bigint references applications_dim(app_id),
  capability_id smallint,
  tier text,
  projected_units numeric(18,6),
  projected_cost numeric(18,6),
  method text,
  primary key (month_start, app_id, capability_id, tier, method)
);

-- Price configuration
create table price_config (
  capability_code text,
  tier text,
  usd_per_unit numeric(18,6),
  effective_from date,
  effective_to date,
  primary key (capability_code, tier, effective_from)
);

-- Mapping overrides
create table mapping_overrides (
  source text,
  source_key text,
  resolved_app_name text,
  h_code_override text,
  sector_override text,
  confidence numeric(5,2),
  created_by text,
  created_at timestamptz default now()
);

-- ETL execution log
create table etl_execution_log (
  run_id bigserial primary key,
  job_name text,
  started_at timestamptz,
  finished_at timestamptz,
  status text,
  rows_ingested int,
  note text
);

-- Data lineage
create table data_lineage (
  lineage_id bigserial primary key,
  run_id bigint references etl_execution_log(run_id),
  source_system text,
  source_endpoint text,
  source_record_id text,
  target_table text,
  target_pk jsonb,
  ts timestamptz default now()
);

-- Seed capabilities
insert into capabilities_dim (capability_code, description) values
('APM','Application Performance Monitoring'),
('MRUM','Mobile Real User Monitoring'),
('BRUM','Browser Real User Monitoring'),
('SYN','Synthetic Monitoring'),
('DB','Database Monitoring')
on conflict (capability_code) do nothing;

-- Seed time dimension for 2 years
with t as (
  select generate_series(date_trunc('day', now())::timestamptz,
                         (now() + interval '730 days')::date,
                         interval '1 day') as ts
)
insert into time_dim (ts, y, m, d, yyyy_mm)
select ts, extract(year from ts)::int, extract(month from ts)::int, extract(day from ts)::int,
       to_char(ts,'YYYY-MM')
from t
on conflict (ts) do nothing;

-- Placeholder pricing (replace <rate> with actual rate later)
insert into price_config (capability_code,tier,usd_per_unit,effective_from,effective_to) values
('APM','PRO',  0, '2025-01-01','2099-12-31'),
('APM','PEAK', 0, '2025-01-01','2099-12-31'),
('MRUM',null,  0, '2025-01-01','2099-12-31'),
('BRUM',null,  0, '2025-01-01','2099-12-31'),
('SYN', null,  0, '2025-01-01','2099-12-31'),
('DB',  null,  0, '2025-01-01','2099-12-31');

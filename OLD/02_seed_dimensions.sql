-- 02_seed_dimensions.sql
-- Seeds the dimension tables with initial mock data.

-- ===============================================
-- 1. applications_dim Seed Data
-- ===============================================
INSERT INTO applications_dim (application_name, current_architecture_type, h_code, deployment_env) VALUES
    ('Gatorade E-Commerce', 'Microservices', 'H101', 'PROD'),
    ('Pepsi Inventory Hub', 'Monolith', 'H202', 'PROD'),
    ('Quaker Oats Analytics', 'Data Lake', 'H303', 'DEV'),
    ('Frito-Lay SCM', 'Microservices', 'H404', 'TEST'),
    ('PepsiCo Internal HR Portal', 'Serverless', 'H505', 'PROD');

-- Ensure the SERIAL sequence starts after the inserted values
SELECT setval('applications_dim_application_key_seq', (SELECT MAX(application_key) FROM applications_dim));


-- ===============================================
-- 2. owners_dim Seed Data
-- ===============================================
INSERT INTO owners_dim (owner_name, sector) VALUES
    ('Americas Beverages', 'Beverages'),
    ('Europe & Sub-Saharan Africa', 'International'),
    ('North America Snacks', 'Foods');

-- Ensure the SERIAL sequence starts after the inserted values
SELECT setval('owners_dim_owner_key_seq', (SELECT MAX(owner_key) FROM owners_dim));


-- ===============================================
-- 3. capabilities_dim Seed Data
-- ===============================================
-- These represent the different types of AppDynamics licenses or capabilities being tracked
INSERT INTO capabilities_dim (capability_name, license_type) VALUES
    ('APM Peak License', 'Peak'),
    ('APM Pro License', 'Pro'),
    ('Server Monitoring', 'Infrastructure'),
    ('Database Monitoring', 'Infrastructure'),
    ('User Experience Monitoring', 'Subscription'),
    ('Business Journeys', 'Subscription');


-- ===============================================
-- 4. price_config Seed Data
-- ===============================================
-- Insert pricing by joining to capabilities_dim to get the correct foreign key (capability_key)
INSERT INTO price_config (capability_key, unit_price, effective_date)
VALUES
    -- Pricing for APM Licenses
    ((SELECT capability_key FROM capabilities_dim WHERE capability_name = 'APM Peak License'), 0.05, '2024-01-01'),
    ((SELECT capability_key FROM capabilities_dim WHERE capability_name = 'APM Pro License'), 0.01, '2024-01-01'),

    -- Pricing for Infrastructure Monitoring
    ((SELECT capability_key FROM capabilities_dim WHERE capability_name = 'Server Monitoring'), 0.03, '2024-01-01'),
    ((SELECT capability_key FROM capabilities_dim WHERE capability_name = 'Database Monitoring'), 0.02, '2024-01-01'),

    -- Pricing for Subscription-based services (use a placeholder price for chargeback)
    ((SELECT capability_key FROM capabilities_dim WHERE capability_name = 'User Experience Monitoring'), 0.005, '2024-01-01'),
    ((SELECT capability_key FROM capabilities_dim WHERE capability_name = 'Business Journeys'), 0.004, '2024-01-01');

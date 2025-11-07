-- ========================================
-- Seed Dimension Data
-- Database: cost_analytics_db
-- ========================================

-- This script populates the shared dimension tables with initial data
-- These are referenced by tool-specific tables (appd_*, servicenow_*)

-- ========================================
-- Shared Owners
-- ========================================

INSERT INTO shared_owners (owner_name, email, department, cost_center)
VALUES
    ('John Smith', 'john.smith@pepsico.com', 'IT Operations', 'CC-1001'),
    ('Jane Doe', 'jane.doe@pepsico.com', 'Application Development', 'CC-1002'),
    ('Mike Johnson', 'mike.johnson@pepsico.com', 'Data Engineering', 'CC-1003'),
    ('Sarah Williams', 'sarah.williams@pepsico.com', 'Cloud Infrastructure', 'CC-1004'),
    ('David Brown', 'david.brown@pepsico.com', 'Platform Engineering', 'CC-1005')
ON CONFLICT (owner_name) DO NOTHING;

-- ========================================
-- Shared Sectors
-- ========================================

INSERT INTO shared_sectors (sector_name, description)
VALUES
    ('Finance', 'Financial systems and reporting'),
    ('Supply Chain', 'Supply chain management and logistics'),
    ('Sales', 'Sales and customer management'),
    ('Marketing', 'Marketing and brand management'),
    ('IT', 'Information technology and infrastructure'),
    ('HR', 'Human resources and talent management'),
    ('Manufacturing', 'Production and manufacturing operations')
ON CONFLICT (sector_name) DO NOTHING;

-- ========================================
-- Shared Capabilities
-- ========================================

-- Get sector IDs for reference
DO $$
DECLARE
    finance_id INTEGER;
    supply_chain_id INTEGER;
    sales_id INTEGER;
    marketing_id INTEGER;
    it_id INTEGER;
BEGIN
    SELECT sector_id INTO finance_id FROM shared_sectors WHERE sector_name = 'Finance';
    SELECT sector_id INTO supply_chain_id FROM shared_sectors WHERE sector_name = 'Supply Chain';
    SELECT sector_id INTO sales_id FROM shared_sectors WHERE sector_name = 'Sales';
    SELECT sector_id INTO marketing_id FROM shared_sectors WHERE sector_name = 'Marketing';
    SELECT sector_id INTO it_id FROM shared_sectors WHERE sector_name = 'IT';

    -- Finance capabilities
    INSERT INTO shared_capabilities (capability_name, description, sector_id)
    VALUES
        ('General Ledger', 'Core accounting and financial reporting', finance_id),
        ('Accounts Payable', 'Vendor payment processing', finance_id),
        ('Accounts Receivable', 'Customer billing and collections', finance_id),
        ('Financial Planning', 'Budgeting and forecasting', finance_id)
    ON CONFLICT (capability_name) DO NOTHING;

    -- Supply Chain capabilities
    INSERT INTO shared_capabilities (capability_name, description, sector_id)
    VALUES
        ('Inventory Management', 'Warehouse and inventory control', supply_chain_id),
        ('Order Management', 'Order processing and fulfillment', supply_chain_id),
        ('Procurement', 'Purchasing and supplier management', supply_chain_id),
        ('Logistics', 'Transportation and distribution', supply_chain_id)
    ON CONFLICT (capability_name) DO NOTHING;

    -- Sales capabilities
    INSERT INTO shared_capabilities (capability_name, description, sector_id)
    VALUES
        ('Customer Relationship Management', 'CRM and customer data', sales_id),
        ('Sales Force Automation', 'Sales process automation', sales_id),
        ('Pricing', 'Pricing and promotions management', sales_id)
    ON CONFLICT (capability_name) DO NOTHING;

    -- Marketing capabilities
    INSERT INTO shared_capabilities (capability_name, description, sector_id)
    VALUES
        ('Digital Marketing', 'Online marketing and campaigns', marketing_id),
        ('Brand Management', 'Brand strategy and assets', marketing_id),
        ('Marketing Analytics', 'Campaign performance and ROI', marketing_id)
    ON CONFLICT (capability_name) DO NOTHING;

    -- IT capabilities
    INSERT INTO shared_capabilities (capability_name, description, sector_id)
    VALUES
        ('Infrastructure Services', 'Compute, storage, network', it_id),
        ('Application Services', 'Application hosting and support', it_id),
        ('Data Services', 'Data storage and analytics', it_id),
        ('Security Services', 'Cybersecurity and compliance', it_id)
    ON CONFLICT (capability_name) DO NOTHING;
END
$$;

-- ========================================
-- Verification
-- ========================================

DO $$
DECLARE
    owner_count INTEGER;
    sector_count INTEGER;
    capability_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO owner_count FROM shared_owners;
    SELECT COUNT(*) INTO sector_count FROM shared_sectors;
    SELECT COUNT(*) INTO capability_count FROM shared_capabilities;
    
    RAISE NOTICE 'Dimension data seeded:';
    RAISE NOTICE '  Owners: %', owner_count;
    RAISE NOTICE '  Sectors: %', sector_count;
    RAISE NOTICE '  Capabilities: %', capability_count;
END
$$;
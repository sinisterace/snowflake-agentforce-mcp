-- ============================================================================
-- Snowflake Managed MCP Server - Step 1: Create Database and Tables
-- ============================================================================
-- Creates the CIRRUSSOLAR database with sample customer energy data
-- Operational / IoT-style data that lives in Snowflake and is queried in place
-- by AI agents through MCP (no copy into the agent's platform)
-- ============================================================================

-- Create and use database
CREATE DATABASE IF NOT EXISTS CIRRUSSOLAR;
USE DATABASE CIRRUSSOLAR;
USE SCHEMA PUBLIC;

-- ============================================================================
-- Customer Energy Data Table
-- ============================================================================
-- Stores monthly energy production and consumption metrics from solar panels
-- In a real scenario, this would be populated by IoT sensors or monitoring systems

CREATE OR REPLACE TABLE CUSTOMER_ENERGY_DATA (
  customer_id VARCHAR(10) COMMENT 'Internal customer identifier (e.g., C001)',
  account_number VARCHAR(20) COMMENT 'Customer-facing account number (e.g., ACC-001)',
  month INT COMMENT 'Month (1-12)',
  year INT COMMENT 'Year (e.g., 2025)',
  energy_produced_kwh DECIMAL(10,2) COMMENT 'Total energy produced by solar panels (kWh)',
  energy_consumed_kwh DECIMAL(10,2) COMMENT 'Total energy consumed by household (kWh)',
  grid_export_kwh DECIMAL(10,2) COMMENT 'Excess energy exported to grid (kWh)',
  system_efficiency_pct DECIMAL(5,2) COMMENT 'System efficiency percentage'
);

-- ============================================================================
-- Sample Data: Customer ACC-001 (C001)
-- ============================================================================
-- 11 months of data with realistic solar production patterns
-- Note: Multiple readings in some months simulate data collection frequency

INSERT INTO CUSTOMER_ENERGY_DATA VALUES
-- February 2025
('C001', 'ACC-001', 2, 2025, 710.4, 650.2, 60.2, 91.5),

-- March 2025
('C001', 'ACC-001', 3, 2025, 840.6, 780.0, 60.6, 93.2),

-- April 2025
('C001', 'ACC-001', 4, 2025, 970.3, 890.5, 79.8, 94.1),

-- May 2025 (production increasing as summer approaches)
('C001', 'ACC-001', 5, 2025, 1090.5, 980.2, 110.3, 92.8),

-- July 2025 (peak summer production, multiple readings)
('C001', 'ACC-001', 7, 2025, 1420.3, 1200.0, 220.3, 95.5),
('C001', 'ACC-001', 7, 2025, 1250.3, 1100.0, 150.3, 94.0),

-- August 2025 (continued high production)
('C001', 'ACC-001', 8, 2025, 1390.6, 1250.8, 139.8, 93.7),

-- September 2025 (production declining, multiple readings)
('C001', 'ACC-001', 9, 2025, 1180.2, 1050.0, 130.2, 92.5),
('C001', 'ACC-001', 9, 2025, 1020.4, 920.0, 100.4, 91.8),

-- October 2025 (fall production)
('C001', 'ACC-001', 10, 2025, 770.2, 710.0, 60.2, 90.5),

-- November 2025 (winter production)
('C001', 'ACC-001', 11, 2025, 550.3, 520.0, 30.3, 89.2);

-- ============================================================================
-- Sample Data: Customer ACC-002 (C002)
-- ============================================================================
-- 3 months of data for testing multi-customer queries

INSERT INTO CUSTOMER_ENERGY_DATA VALUES
-- January 2025
('C002', 'ACC-002', 1, 2025, 920.5, 850.0, 70.5, 92.3),

-- February 2025
('C002', 'ACC-002', 2, 2025, 880.3, 820.0, 60.3, 91.8),

-- March 2025
('C002', 'ACC-002', 3, 2025, 1050.7, 980.0, 70.7, 93.5);

-- ============================================================================
-- Sample Data: Customer ACC-003 (C003)
-- ============================================================================
-- Additional customer for diversity

INSERT INTO CUSTOMER_ENERGY_DATA VALUES
('C003', 'ACC-003', 1, 2025, 1200.0, 1100.0, 100.0, 95.0),
('C003', 'ACC-003', 2, 2025, 1150.0, 1050.0, 100.0, 94.5),
('C003', 'ACC-003', 3, 2025, 1300.0, 1180.0, 120.0, 95.5);

-- ============================================================================
-- Verification
-- ============================================================================
-- Verify data was inserted correctly

SELECT
  customer_id,
  account_number,
  COUNT(*) as month_count,
  SUM(energy_produced_kwh) as total_energy_produced,
  AVG(system_efficiency_pct) as avg_efficiency
FROM CUSTOMER_ENERGY_DATA
GROUP BY customer_id, account_number
ORDER BY customer_id;

-- Expected output:
-- C001 (ACC-001): 11 readings (9 distinct months)
-- C002 (ACC-002): 3 readings
-- C003 (ACC-003): 3 readings

-- ============================================================================
-- Notes
-- ============================================================================
-- 1. Multiple readings in the same month simulate real-world data collection
--    where sensors report multiple times or corrections are made
-- 2. Production peaks in summer (July-August) and dips in winter (Nov-Feb)
-- 3. Grid export represents excess production after household consumption
-- 4. Efficiency percentages realistic for residential solar systems
-- ============================================================================

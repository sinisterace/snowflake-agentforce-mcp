-- ============================================================================
-- Snowflake Managed MCP Server - Step 2: Create Cortex Search Service
-- ============================================================================
-- Creates a Cortex Search Service (hybrid vector + keyword search with
-- semantic reranking) over the customer energy data table
-- ============================================================================

USE DATABASE CIRRUSSOLAR;
USE SCHEMA PUBLIC;

-- ============================================================================
-- Prerequisites Check
-- ============================================================================
-- IMPORTANT: Cortex Search embeds the search column with Snowflake-managed
-- embedding models (default: snowflake-arctic-embed-m-v1.5). Trial accounts
-- can't use Cortex embedding functions, so check availability first:
SELECT SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m', 'test') AS embedding_test;

-- If this fails with "not available for trial accounts":
-- 1. Go to Account → Billing in Snowsight
-- 2. Click "Upgrade Account"
-- 3. Add credit card to enable billing
-- 4. Wait 5 minutes for features to activate
-- 5. Re-run this script

-- ============================================================================
-- Create Cortex Search Service
-- ============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE ENERGY_DATA_SEARCH_SERVICE
  ON search_text
  ATTRIBUTES customer_id, account_number, month, year
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Customer energy readings, searchable by customer, account, and period'
AS (
  SELECT
    -- Single text column that gets embedded + keyword-indexed.
    -- Packing identifiers and the period into one string lets queries like
    -- "account ACC-001 energy in July 2025" match on every part.
    'Customer ' || customer_id
      || ' | Account ' || account_number
      || ' | ' || MONTHNAME(DATE_FROM_PARTS(year, month, 1)) || ' ' || year
      || ' | produced ' || energy_produced_kwh || ' kWh'
      || ', consumed ' || energy_consumed_kwh || ' kWh'
      || ', exported ' || grid_export_kwh || ' kWh'
      || ', efficiency ' || system_efficiency_pct || '%' AS search_text,
    customer_id,
    account_number,
    month,
    year,
    energy_produced_kwh,
    energy_consumed_kwh,
    grid_export_kwh,
    system_efficiency_pct
  FROM CIRRUSSOLAR.PUBLIC.CUSTOMER_ENERGY_DATA
);

-- ============================================================================
-- What This Does
-- ============================================================================
-- ON search_text
--   → Single-index services search exactly ONE text column (ON takes one column).
--     It is embedded (vector) and keyword-indexed, then results are reranked.
--   → To search several columns independently, use the multi-index form:
--       TEXT INDEXES customer_id, account_number
--       VECTOR INDEXES search_text (model='snowflake-arctic-embed-m-v1.5')
--
-- ATTRIBUTES customer_id, account_number, month, year
--   → Columns you can FILTER on at query time, e.g.
--       "filter": {"@and": [{"@eq": {"account_number": "ACC-001"}}, {"@eq": {"year": 2025}}]}
--   → Any column in the source query can be RETURNED (via "columns"), not only attributes
--
-- WAREHOUSE = COMPUTE_WH
--   → Runs the source query, builds the index, and performs refreshes
--   → Queries do NOT run on this warehouse; serving uses separate Cortex Search
--     compute billed per GB-month of indexed data (see Cost Considerations)
--   → Snowflake recommends a dedicated warehouse per service (MEDIUM or smaller)
--
-- TARGET_LAG = '1 hour'
--   → Index refreshes incrementally to stay within 1 hour of the source table
--   → Refreshes that find no changes cost nothing; lower lag = more refreshes
--
-- AS (SELECT ...)
--   → Defines which rows get indexed
--   → Can add WHERE clauses to filter (e.g., only last 12 months)

-- ============================================================================
-- Grant Permissions
-- ============================================================================
-- Querying requires USAGE on the database, schema, AND the service.
-- (ACCOUNTADMIN owns these already; for a least-privilege role see sql/05.)

GRANT USAGE ON CORTEX SEARCH SERVICE CIRRUSSOLAR.PUBLIC.ENERGY_DATA_SEARCH_SERVICE
  TO ROLE ACCOUNTADMIN;

GRANT USAGE ON WAREHOUSE COMPUTE_WH
  TO ROLE ACCOUNTADMIN;

-- ============================================================================
-- Verify Creation
-- ============================================================================
-- Check that the search service exists and is building

SHOW CORTEX SEARCH SERVICES IN SCHEMA CIRRUSSOLAR.PUBLIC;

-- Expected output:
-- name: ENERGY_DATA_SEARCH_SERVICE
-- database_name: CIRRUSSOLAR
-- schema_name: PUBLIC
-- created_on: [timestamp]

-- ============================================================================
-- IMPORTANT: Wait for Indexing to Complete
-- ============================================================================
-- The search service is created immediately, but the vector index takes
-- 2-5 minutes to build for ~20 rows. You cannot query it until indexing completes.
--
-- Check progress with SHOW / DESCRIBE (look at the indexing / serving state
-- columns), or simply wait 3-5 minutes before testing.
--
-- If you try to query too soon, you'll get:
-- "Cortex Search Service does not exist or access is not authorized"
--
-- This is misleading - it exists, it's just not ready yet.

-- ============================================================================
-- Test Query (run this after 5 minutes)
-- ============================================================================
-- SEARCH_PREVIEW is the SQL test harness for a service (the MCP server and
-- REST API query the same service with the same JSON shape).

-- Example: natural-language query
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CIRRUSSOLAR.PUBLIC.ENERGY_DATA_SEARCH_SERVICE',
    '{
       "query": "customer C001 energy production in summer",
       "columns": ["customer_id", "account_number", "month", "year", "energy_produced_kwh", "system_efficiency_pct"],
       "limit": 5
     }'
  )
)['results'] AS results;

-- Example: same query, filtered on an attribute
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CIRRUSSOLAR.PUBLIC.ENERGY_DATA_SEARCH_SERVICE',
    '{
       "query": "energy output",
       "columns": ["month", "year", "energy_produced_kwh"],
       "filter": {"@eq": {"account_number": "ACC-001"}},
       "limit": 12
     }'
  )
)['results'] AS results;

-- Expected: a JSON array of matching rows with the requested columns

-- ============================================================================
-- Troubleshooting
-- ============================================================================
-- Error: "EMBED_TEXT_768 is not available for trial accounts"
-- → Solution: Upgrade to Enterprise Edition with billing enabled
--
-- Error: "does not exist or access is not authorized"
-- → Solution: Wait 5 minutes for indexing to complete
--
-- Error: "Insufficient privileges to operate on CORTEX SEARCH SERVICE"
-- → Solution: Run the GRANT statements above
--
-- Error: "Warehouse COMPUTE_WH does not exist"
-- → Solution: Create warehouse or use a different name:
--    CREATE WAREHOUSE COMPUTE_WH WITH WAREHOUSE_SIZE='X-SMALL';

-- ============================================================================
-- Cost Considerations
-- ============================================================================
-- Cortex Search cost components:
-- - Serving compute: credits per GB-month of indexed data (source rows +
--   embeddings), charged while serving is resumed, even with zero queries.
--   Suspend when idle: ALTER CORTEX SEARCH SERVICE ... SUSPEND SERVING;
--   (or set AUTO_SUSPEND on the service)
-- - Embedding tokens: per token for each new/changed row in the ON column
-- - Warehouse: only for the source query, index build, and refreshes
-- - Storage: materialized source data + index at standard storage rates
--
-- Monitor with:
--   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
--   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_SERVING_USAGE_HISTORY
--
-- At demo scale (~20 rows) the total is a few dollars; suspend serving after.

-- ============================================================================

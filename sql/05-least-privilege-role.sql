-- ============================================================================
-- Snowflake Managed MCP Server - Step 5 (recommended): Least-Privilege Role
-- ============================================================================
-- Steps 1-4 use ACCOUNTADMIN to keep the demo short. This script replaces that
-- with a dedicated MCP_READER role that can do exactly one thing: call the MCP
-- server's tools. Then it issues a new PAT restricted to that role.
--
-- Run as ACCOUNTADMIN (or SECURITYADMIN + the object owner for the grants).
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ============================================================================
-- 1. Role
-- ============================================================================

CREATE ROLE IF NOT EXISTS MCP_READER
  COMMENT = 'Read-only access to the CIRRUSSOLAR MCP server tools';

-- ============================================================================
-- 2. Grants: the MCP server needs USAGE on the server itself AND on every
--    object a tool touches. Server access alone exposes nothing.
-- ============================================================================

GRANT USAGE ON DATABASE CIRRUSSOLAR                    TO ROLE MCP_READER;
GRANT USAGE ON SCHEMA   CIRRUSSOLAR.PUBLIC             TO ROLE MCP_READER;

-- Tool backend: Cortex Search (searches run with the service owner's rights,
-- so MCP_READER needs no SELECT on the underlying table)
GRANT USAGE ON CORTEX SEARCH SERVICE CIRRUSSOLAR.PUBLIC.ENERGY_DATA_SEARCH_SERVICE
  TO ROLE MCP_READER;

-- The MCP server
GRANT USAGE ON MCP SERVER CIRRUSSOLAR.PUBLIC.cirrus_solar_mcp_server
  TO ROLE MCP_READER;

-- Sessions need a default warehouse. It's also required if you later add
-- SYSTEM_EXECUTE_SQL / GENERIC / Cortex Analyst tools.
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE MCP_READER;

-- If you add a Cortex Analyst tool, also grant SELECT on its semantic view:
-- GRANT SELECT ON SEMANTIC VIEW CIRRUSSOLAR.PUBLIC.ENERGY_SEMANTIC_VIEW TO ROLE MCP_READER;
-- If you add a SYSTEM_EXECUTE_SQL tool, also grant the Cortex database role:
-- GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE MCP_READER;

-- ============================================================================
-- 3. Move the service user onto the role
-- ============================================================================

GRANT ROLE MCP_READER TO USER mcp_service_user;

ALTER USER mcp_service_user SET
  DEFAULT_ROLE = MCP_READER
  DEFAULT_WAREHOUSE = COMPUTE_WH;

-- ============================================================================
-- 4. Issue a PAT restricted to MCP_READER, then retire the ACCOUNTADMIN one
-- ============================================================================
-- ⚠️  The token secret is shown ONCE in this statement's output.

ALTER USER mcp_service_user
  ADD PROGRAMMATIC ACCESS TOKEN mcp_reader_token
  ROLE_RESTRICTION = 'MCP_READER'
  DAYS_TO_EXPIRY = 30
  COMMENT = 'Least-privilege PAT for MCP clients';

-- After updating every client with the new token:
-- ALTER USER mcp_service_user DROP PROGRAMMATIC ACCESS TOKEN cirrus_mcp_token;
-- REVOKE ROLE ACCOUNTADMIN FROM USER mcp_service_user;   -- if it was granted

-- ============================================================================
-- 5. Verify
-- ============================================================================

SHOW GRANTS TO ROLE MCP_READER;
SHOW PROGRAMMATIC ACCESS TOKENS FOR USER mcp_service_user;

-- Re-run the tools/list curl from sql/04 with the NEW token: you should still
-- see customer_energy_insights. If tools/list comes back empty, a per-tool
-- grant (step 2) is missing.

-- ============================================================================
-- Optional hardening
-- ============================================================================
-- - Lock the network policy (sql/03) to your client's egress IPs.
-- - Put masking / row access policies on CUSTOMER_ENERGY_DATA. Create the
--   search service with INHERIT_DATA_GOVERNANCE_POLICIES = TRUE so they flow
--   through to search results.
-- - Alert on unexpected use:
--     SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
--     WHERE user_name = 'MCP_SERVICE_USER' ORDER BY event_timestamp DESC;
-- ============================================================================

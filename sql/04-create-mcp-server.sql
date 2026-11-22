-- ============================================================================
-- Snowflake Managed MCP Server - Step 4: Create the MCP Server
-- ============================================================================
-- Creates the MCP server that exposes Cortex Search as an MCP tool
-- ============================================================================

USE DATABASE CIRRUSSOLAR;
USE SCHEMA PUBLIC;

-- ============================================================================
-- What is an MCP Server?
-- ============================================================================
-- An MCP server is a Snowflake-managed endpoint that:
-- 1. Implements the Model Context Protocol (MCP)
-- 2. Exposes Snowflake capabilities (Cortex Search, Analyst, Agents, SQL,
--    UDFs/procedures) as "tools"
-- 3. Handles tool discovery, input validation, and execution, enforcing
--    Snowflake RBAC on every call (the caller's role needs USAGE on the
--    server AND on each underlying object)
-- 4. Returns results in MCP-compliant JSON (tools capability only: no
--    resources, prompts, or sampling)
--
-- Think of it as an API gateway specifically designed for AI agents.

-- ============================================================================
-- Create MCP Server
-- ============================================================================

CREATE OR REPLACE MCP SERVER cirrus_solar_mcp_server
  FROM SPECIFICATION $$
  tools:
    - name: "customer_energy_insights"
      type: "CORTEX_SEARCH_SERVICE_QUERY"
      identifier: "CIRRUSSOLAR.PUBLIC.ENERGY_DATA_SEARCH_SERVICE"
      title: "Customer Energy Insights"
      description: "Search customer energy production and consumption data. Returns monthly energy produced (kWh), energy consumed (kWh), grid export (kWh), and system efficiency percentage. Use for questions about energy generation, usage, or system performance for specific customers or accounts."
  $$;

-- ============================================================================
-- Breaking Down the Specification
-- ============================================================================
-- FROM SPECIFICATION $$...$$
--   → The $$ delimiters are Snowflake's string literal syntax (like ''' in Python)
--   → Everything inside is YAML defining the MCP tools
--
-- tools:
--   → Array of tool definitions (can have multiple)
--
-- name: "customer_energy_insights"
--   → Tool identifier used by AI agents to call this tool
--   → Convention: lowercase_with_underscores
--   → Must be unique within the server
--
-- type: "CORTEX_SEARCH_SERVICE_QUERY"
--   → Tells Snowflake this tool wraps a Cortex Search Service
--   → Other types:
--     - CORTEX_ANALYST_MESSAGE  text-to-SQL over a semantic view
--     - CORTEX_AGENT_RUN        run a Cortex Agent (orchestrates its own tools)
--     - SYSTEM_EXECUTE_SQL      run SQL (read_only: true by default; needs a warehouse)
--     - GENERIC                 wrap a UDF or stored procedure
--   → Limits: 50 tools per server, 15-minute tools/call timeout
--
-- identifier: "CIRRUSSOLAR.PUBLIC.ENERGY_DATA_SEARCH_SERVICE"
--   → Fully qualified name of the Cortex Search Service
--   → Links this tool to the search service we created in step 2
--
-- title: "Customer Energy Insights"
--   → Human-readable name shown in UIs
--   → Keep it concise and descriptive
--
-- description: "Search customer energy..."
--   → CRITICAL for AI agent behavior
--   → The agent reads this to decide when to use the tool
--   → Be specific about:
--     - What data it searches
--     - What fields it returns
--     - What questions it can answer
--   → Vague descriptions = agent won't know when to call it

-- ============================================================================
-- Grant Permissions
-- ============================================================================
-- Allow ACCOUNTADMIN to use the MCP server.
-- NOTE: CREATE OR REPLACE MCP SERVER drops all grants on it, so keep the GRANT
-- statements in the same script and re-run them after every replace.

GRANT USAGE ON MCP SERVER CIRRUSSOLAR.PUBLIC.cirrus_solar_mcp_server
  TO ROLE ACCOUNTADMIN;

-- In production, use a least-privilege role instead: see sql/05-least-privilege-role.sql

-- ============================================================================
-- Verify Creation
-- ============================================================================

DESCRIBE MCP SERVER CIRRUSSOLAR.PUBLIC.cirrus_solar_mcp_server;

-- Expected output:
-- property: name, value: cirrus_solar_mcp_server
-- property: database_name, value: CIRRUSSOLAR
-- property: schema_name, value: PUBLIC
-- property: created_on, value: [timestamp]

-- ============================================================================
-- Get the MCP Endpoint URL
-- ============================================================================
-- The endpoint URL is automatically generated when you create the MCP server.
-- Format:
-- https://<org>-<account>.snowflakecomputing.com/api/v2/databases/<DB>/schemas/<SCHEMA>/mcp-servers/<SERVER_NAME>
--
-- Use the org-account form of your account URL, and replace any underscores
-- in the hostname with hyphens (MCP clients have trouble with underscores):

SELECT LOWER(REPLACE(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME(), '_', '-'))
  || '.snowflakecomputing.com' AS mcp_host;

-- Example output: myorg-myaccount.snowflakecomputing.com
--
-- Your endpoint URL will be:
-- https://myorg-myaccount.snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server
--
-- ⚠️  SAVE THIS URL - every MCP client needs it

-- ============================================================================
-- Test the MCP Server (Optional)
-- ============================================================================
-- You can test the server directly using curl or Postman
--
-- 1. Get tool list:
-- curl -X POST https://[ACCOUNT].snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server \
--   -H "Content-Type: application/json" \
--   -H "Accept: application/json, text/event-stream" \
--   -H "Authorization: Bearer [YOUR_PAT_TOKEN]" \
--   -H "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN" \
--   -d '{
--     "jsonrpc": "2.0",
--     "id": 1,
--     "method": "tools/list",
--     "params": {}
--   }'
--
-- Expected response:
-- {
--   "jsonrpc": "2.0",
--   "id": 1,
--   "result": {
--     "tools": [
--       {
--         "name": "customer_energy_insights",
--         "description": "Search customer energy...",
--         "inputSchema": {...}
--       }
--     ]
--   }
-- }

-- ============================================================================
-- Adding More Tools (Optional)
-- ============================================================================
-- You can add multiple tools to one MCP server
-- Example with multiple tools:

-- CREATE OR REPLACE MCP SERVER cirrus_solar_mcp_server
--   FROM SPECIFICATION $$
--   tools:
--     - name: "customer_energy_insights"
--       type: "CORTEX_SEARCH_SERVICE_QUERY"
--       identifier: "CIRRUSSOLAR.PUBLIC.ENERGY_DATA_SEARCH_SERVICE"
--       title: "Customer Energy Insights"
--       description: "Search customer energy production and consumption data..."
--
--     - name: "loan_payment_status"
--       type: "CORTEX_SEARCH_SERVICE_QUERY"
--       identifier: "CIRRUSSOLAR.PUBLIC.FINANCING_DATA_SEARCH_SERVICE"
--       title: "Loan Payment Status"
--       description: "Search customer loan balances and payment history..."
--
--     - name: "installation_warranty_info"
--       type: "CORTEX_SEARCH_SERVICE_QUERY"
--       identifier: "CIRRUSSOLAR.PUBLIC.INSTALLATION_DATA_SEARCH_SERVICE"
--       title: "Installation & Warranty Info"
--       description: "Search solar panel installation details and warranty dates..."
--   $$;

-- Each CORTEX_SEARCH_SERVICE_QUERY tool points at its own search service.
-- Mixing tool types on one server is common, e.g. Cortex Search for lookups
-- plus Cortex Analyst for aggregates:
--
--     - name: "energy_analytics"
--       type: "CORTEX_ANALYST_MESSAGE"
--       identifier: "CIRRUSSOLAR.PUBLIC.ENERGY_SEMANTIC_VIEW"
--       title: "Energy Analytics"
--       description: "Answer aggregate questions (totals, averages, trends) about customer energy data..."
--
-- (Cortex Analyst tools need SELECT on the semantic view for the calling role.)

-- ============================================================================
-- Updating the MCP Server
-- ============================================================================
-- There is no ALTER MCP SERVER: to add/remove tools or change descriptions,
-- run CREATE OR REPLACE with the full spec, then RE-RUN THE GRANTS (replacing
-- drops them). The endpoint URL doesn't change, so clients keep working once
-- grants are restored; most clients re-discover tools on reconnect (in
-- Agentforce, re-open "Manage Tools").

-- Example: Update tool description
-- CREATE OR REPLACE MCP SERVER cirrus_solar_mcp_server
--   FROM SPECIFICATION $$
--   tools:
--     - name: "customer_energy_insights"
--       type: "CORTEX_SEARCH_SERVICE_QUERY"
--       identifier: "CIRRUSSOLAR.PUBLIC.ENERGY_DATA_SEARCH_SERVICE"
--       title: "Customer Energy Insights"
--       description: "UPDATED DESCRIPTION with more detail about what this tool does..."
--   $$;

-- ============================================================================
-- Troubleshooting
-- ============================================================================
-- Error: "CORTEX_SEARCH_SERVICE does not exist"
-- → Solution: Run step 2 first to create the search service
--
-- Error: "Invalid YAML specification"
-- → Solution: Check indentation (YAML is whitespace-sensitive)
-- → Use 2 spaces for indentation, not tabs
--
-- Error: "Tool name contains invalid characters"
-- → Solution: Use only lowercase letters, numbers, and underscores
-- → No spaces, hyphens, or special characters

-- ============================================================================
-- Next Steps
-- ============================================================================
-- 1. Copy the endpoint URL (from the mcp_host query above)
-- 2. Copy the PAT token (from step 3), or set up OAuth (sql/06)
-- 3. Harden access with sql/05-least-privilege-role.sql
-- 4. Connect a client: see docs/CLIENTS.md (Claude Code, Cursor, curl,
--    Salesforce Agentforce, ...)

-- ============================================================================

-- ============================================================================
-- Snowflake Managed MCP Server - Step 3: Service User + PAT Authentication
-- ============================================================================
-- Creates a service user, authentication policy, network policy, and a
-- Programmatic Access Token (PAT) that headless MCP clients use to call the
-- Snowflake-managed MCP server
-- ============================================================================

USE DATABASE CIRRUSSOLAR;
USE SCHEMA PUBLIC;

-- ============================================================================
-- PAT vs OAuth
-- ============================================================================
-- The Snowflake-managed MCP server accepts:
--   1. Snowflake OAuth (recommended for interactive clients: Claude, ChatGPT,
--      Cursor, VS Code). Users sign in; access follows their own roles.
--      See sql/06-oauth-integration.sql.
--   2. External OAuth (Okta, Entra ID) bound at account/database/schema level.
--   3. Programmatic Access Token (PAT): a bearer token for headless /
--      server-to-server clients that can send headers but can't do an OAuth
--      dance (e.g. Salesforce Agentforce via Named Credentials, CI jobs,
--      custom agents).
--
-- This script sets up option 3.

-- ============================================================================
-- Step 1: Create Service User
-- ============================================================================
-- TYPE = SERVICE means this user cannot log in with password/MFA
-- It exists only for programmatic access

CREATE USER IF NOT EXISTS mcp_service_user
  DEFAULT_ROLE = ACCOUNTADMIN
  DEFAULT_WAREHOUSE = COMPUTE_WH
  TYPE = SERVICE
  COMMENT = 'Service account for headless MCP clients';

-- ============================================================================
-- Step 2: Create Authentication Policy
-- ============================================================================
-- This policy enables PAT generation for the user

CREATE OR REPLACE AUTHENTICATION POLICY mcp_pat_auth_policy
  AUTHENTICATION_METHODS = ('PROGRAMMATIC_ACCESS_TOKEN')
  PAT_POLICY = (
    DEFAULT_EXPIRY_IN_DAYS = 90,
    MAX_EXPIRY_IN_DAYS = 365
  )
  COMMENT = 'Auth policy allowing PAT generation for MCP integration';

-- DEFAULT_EXPIRY_IN_DAYS = 90
--   → PATs expire after 90 days, forcing token rotation
--   → Good security practice for long-lived tokens
--
-- MAX_EXPIRY_IN_DAYS = 365
--   → Users can manually extend to 1 year if needed
--   → For production, consider shorter values

-- ============================================================================
-- Step 3: Apply Auth Policy to User
-- ============================================================================

ALTER USER mcp_service_user
  SET AUTHENTICATION POLICY mcp_pat_auth_policy;

-- ============================================================================
-- Step 4: Create Network Policy
-- ============================================================================
-- PATs REQUIRE a network policy on the user
-- This policy allows access from any IP (suitable for demo/testing only)
--
-- For production, restrict to the egress IPs of whatever calls the MCP server
-- (your agent platform's published IP ranges, or your own NAT gateway).
-- Salesforce, for example, publishes its ranges here:
-- https://help.salesforce.com/s/articleView?id=000382398&type=1

CREATE OR REPLACE NETWORK POLICY mcp_network_policy
  ALLOWED_IP_LIST = ('0.0.0.0/0')
  COMMENT = 'Permissive network policy for MCP demo (allows all IPs)';

-- Production example (Salesforce egress ranges as the client):
-- CREATE OR REPLACE NETWORK POLICY mcp_network_policy
--   ALLOWED_IP_LIST = (
--     '13.108.0.0/14',    -- Salesforce NA
--     '136.146.0.0/15',   -- Salesforce NA
--     '182.50.76.0/22'    -- Salesforce APAC
--     -- Add more IPs from Salesforce documentation
--   )
--   COMMENT = 'Restricts MCP access to the client platform egress IPs';

-- ============================================================================
-- Step 5: Apply Network Policy to User
-- ============================================================================

ALTER USER mcp_service_user
  SET NETWORK_POLICY = mcp_network_policy;

-- ============================================================================
-- Step 6: Generate the PAT Token
-- ============================================================================
-- ⚠️  CRITICAL: This returns the token ONCE. Copy it immediately.
-- ⚠️  You cannot retrieve it again. If you lose it, you must create a new one.

ALTER USER mcp_service_user
  ADD PROGRAMMATIC ACCESS TOKEN cirrus_mcp_token
  ROLE_RESTRICTION = 'ACCOUNTADMIN'
  DAYS_TO_EXPIRY = 90
  COMMENT = 'PAT for MCP clients';

-- ROLE_RESTRICTION = 'ACCOUNTADMIN'
--   → Required for TYPE = SERVICE users; the role must already be granted
--   → The token can ONLY act as this role (secondary roles are ignored)
--   → ACCOUNTADMIN keeps the demo to four scripts. Don't ship this: run
--     sql/05-least-privilege-role.sql and use a token restricted to MCP_READER
--
-- DAYS_TO_EXPIRY = 90
--   → Token expires in 90 days
--   → You'll need to rotate it before then
--   → Set a calendar reminder to regenerate the token

-- ============================================================================
-- Expected Output
-- ============================================================================
-- The result set will contain a column named "ACCESS_TOKEN" with a value like:
--
-- eyJraWQiOiIzOTg4MDQwMzQzMTU4NzkwIiwiYWxnIjoiRVMyNTYifQ.eyJwIjoiMjM3NzA1...
--
-- This is a JWT (JSON Web Token). It contains:
-- - Header: Algorithm and key ID
-- - Payload: User ID, role, expiration timestamp
-- - Signature: Cryptographic signature to prevent tampering
--
-- ⚠️  COPY THIS VALUE NOW - It will not be shown again

-- ============================================================================
-- Verify Token Creation
-- ============================================================================
-- List all PATs for the user

SHOW PROGRAMMATIC ACCESS TOKENS FOR USER mcp_service_user;

-- Expected output:
-- name: cirrus_mcp_token
-- role_restriction: ACCOUNTADMIN
-- expiration_time: 2026-09-08 (90 days from now)
-- status: ACTIVE

-- ============================================================================
-- How to Use This Token
-- ============================================================================
-- Every MCP request carries these headers (in your MCP client config, or in
-- Salesforce Named Credentials for Agentforce):
--
--   Authorization: Bearer [PASTE_YOUR_TOKEN_HERE]
--   X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN
--   Accept: application/json, text/event-stream
--
-- The token-type header tells Snowflake the bearer is a PAT rather than an
-- OAuth token.

-- ============================================================================
-- Token Rotation (when it expires)
-- ============================================================================
-- To rotate the token in 90 days:

-- 1. Generate new token with different name:
-- ALTER USER mcp_service_user
--   ADD PROGRAMMATIC ACCESS TOKEN cirrus_mcp_token_v2
--   ROLE_RESTRICTION = 'ACCOUNTADMIN'
--   DAYS_TO_EXPIRY = 90;

-- 2. Update every MCP client (config headers / Named Credentials) with the new token

-- 3. Delete old token:
-- ALTER USER mcp_service_user
--   DROP PROGRAMMATIC ACCESS TOKEN cirrus_mcp_token;

-- ============================================================================
-- Security Best Practices
-- ============================================================================
-- ✅ DO:
-- - Use least-privilege roles (not ACCOUNTADMIN) in production
-- - Restrict the network policy to your MCP client's egress IPs
-- - Set calendar reminders for token rotation
-- - Store tokens in a secrets manager or the client's encrypted credential store
-- - Monitor token usage via Snowflake query history
--
-- ❌ DON'T:
-- - Hardcode tokens in code or config files
-- - Share tokens across multiple integrations
-- - Use tokens with unrestricted roles
-- - Let tokens expire without rotation plan
-- - Commit tokens to git repositories

-- ============================================================================
-- Troubleshooting
-- ============================================================================
-- Error: "Network policy is required for PAT"
-- → Solution: Ensure Step 4 and Step 5 completed successfully
--
-- Error: "Authentication policy does not allow PAT"
-- → Solution: Verify Step 2 and Step 3 completed successfully
--
-- Error: "Insufficient privileges to create authentication policy"
-- → Solution: You need ACCOUNTADMIN or a role with CREATE AUTHENTICATION POLICY privilege
--
-- Error: "Role restriction is required" / invalid role restriction
-- → Solution: Service users need ROLE_RESTRICTION, and the role must already be
--   granted to the user (GRANT ROLE ... TO USER mcp_service_user)

-- ============================================================================

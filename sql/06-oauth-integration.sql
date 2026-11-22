-- ============================================================================
-- Snowflake Managed MCP Server - Step 6 (optional): OAuth for Interactive Clients
-- ============================================================================
-- PATs suit headless clients. For people connecting from Claude (claude.ai /
-- Claude Desktop custom connectors), ChatGPT, Cursor, or VS Code, Snowflake
-- recommends Snowflake OAuth: each user signs in with their own Snowflake
-- identity, and tool access follows THEIR roles. There's no shared token.
--
-- Snowflake OAuth doesn't support dynamic client registration, so you create
-- one security integration per client type and paste its client ID (and
-- secret, for confidential clients) into the client.
--
-- Reference: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ============================================================================
-- A. Public client with PKCE (example: Claude custom connector)
-- ============================================================================

CREATE SECURITY INTEGRATION IF NOT EXISTS MCP_OAUTH_CLAUDE
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  OAUTH_CLIENT_TYPE = 'PUBLIC'
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'
  OAUTH_ENFORCE_PKCE = TRUE
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_USE_SECONDARY_ROLES = NONE
  ENABLED = TRUE
  COMMENT = 'OAuth for the Snowflake MCP server from Claude';

-- ============================================================================
-- B. Confidential client (example: Cursor / VS Code)
-- ============================================================================
-- Set OAUTH_REDIRECT_URI to the callback URL your client documents.

-- CREATE SECURITY INTEGRATION IF NOT EXISTS MCP_OAUTH_CURSOR
--   TYPE = OAUTH
--   OAUTH_CLIENT = CUSTOM
--   OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
--   OAUTH_REDIRECT_URI = '<client callback URL>'
--   OAUTH_ISSUE_REFRESH_TOKENS = TRUE
--   OAUTH_USE_SECONDARY_ROLES = NONE
--   ENABLED = TRUE;

-- ============================================================================
-- Client credentials
-- ============================================================================
-- Pass the integration name in UPPERCASE:

SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('MCP_OAUTH_CLAUDE');

-- Returns OAUTH_CLIENT_ID (and secrets for confidential clients). Enter them
-- in the client together with the MCP endpoint URL from sql/04.

-- ============================================================================
-- Which role do OAuth users get?
-- ============================================================================
-- - The default scope (session:role:all) uses the user's DEFAULT_ROLE.
-- - Snowflake OAuth blocks highly privileged roles (ACCOUNTADMIN, SECURITYADMIN,
--   ORGADMIN) by default. That's a good thing: grant users MCP_READER
--   (sql/05) or a similar role, and make it their default:
--
-- GRANT ROLE MCP_READER TO USER <person>;
-- ALTER USER <person> SET DEFAULT_ROLE = MCP_READER;
--
-- - If your account or users have a network policy, it must allow the client's
--   IPs (for SaaS clients like Claude, that's the provider's outbound IPs).
--   A blocked request can surface as a confusing "invalid_client" error.
-- ============================================================================

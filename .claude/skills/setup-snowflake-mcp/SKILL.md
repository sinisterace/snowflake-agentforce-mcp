---
name: setup-snowflake-mcp
description: Set up a Snowflake-managed MCP server backed by Cortex Search (database, sample data, search service, service user + PAT, MCP server, optional least-privilege role) and output the endpoint URL and credentials any MCP client needs (Claude Code, Cursor, Salesforce Agentforce, curl).
---

# Skill: setup-snowflake-mcp

Sets up a complete Snowflake-managed MCP server with a Cortex Search service, ready for any MCP client.

## What this skill does

1. Creates a Snowflake database with sample tables
2. Creates Cortex Search Services for natural language querying
3. Generates Programmatic Access Token (PAT) for authentication
4. Creates and configures the MCP server
5. Optionally hardens access with a least-privilege role (sql/05)
6. Returns the endpoint URL and credentials, plus connection snippets for MCP clients

## Prerequisites

- Snowflake Enterprise Edition account (paid billing enabled for Cortex features)
- `ACCOUNTADMIN` role access
- A running warehouse (default: `COMPUTE_WH`)

## Usage

```
/setup-snowflake-mcp
```

## What the agent should do

### Step 1: Check Snowflake connection

Use the `mcp__snowflake__test_connection` tool to verify connectivity.

If connection fails, ask the user to check their Snowflake MCP server configuration.

### Step 2: Verify Cortex availability

Execute this test query:

```sql
SELECT SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m', 'test');
```

If this fails with "not available for trial accounts", STOP and inform the user they need to:
- Upgrade to Enterprise Edition
- Enable billing (add credit card)
- Wait 5 minutes for Cortex features to activate

### Step 3: Create database and tables

Execute `sql/01-create-database-and-tables.sql` using the `mcp__snowflake__execute_query` tool.

This creates:
- Database: `CIRRUSSOLAR`
- Schema: `PUBLIC`
- Table: `CUSTOMER_ENERGY_DATA` with sample solar energy data

Verify with:
```sql
SELECT COUNT(*) FROM CIRRUSSOLAR.PUBLIC.CUSTOMER_ENERGY_DATA;
```

Expected: At least 10 rows

### Step 4: Create Cortex Search Service

Execute `sql/02-create-cortex-search-service.sql`.

This creates `ENERGY_DATA_SEARCH_SERVICE` which:
- Searches one combined `search_text` column (customer, account, period, readings) with hybrid vector + keyword search
- Lets clients filter on `customer_id`, `account_number`, `month`, `year` and return any source column
- Refreshes to a 1-hour target lag

**IMPORTANT:** This takes 2-5 minutes to build the vector index. Inform the user to wait.

Check status:
```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA CIRRUSSOLAR.PUBLIC;
```

### Step 5: Create PAT authentication

Execute `sql/03-create-pat-authentication.sql`.

This creates:
- Service user: `mcp_service_user`
- Auth policy enabling PATs
- Network policy (allows all IPs for demo)
- Programmatic Access Token

**CRITICAL:** The token is returned ONCE. Extract it from the result and save it.

Token format: `eyJraWQi...` (long JWT string)

Display to user:
```
✅ PAT Token Generated (save this immediately):
[TOKEN_VALUE]

Token expires in 90 days.
```

### Step 6: Create MCP Server

Execute `sql/04-create-mcp-server.sql`.

This creates the MCP server: `cirrus_solar_mcp_server` with tool `customer_energy_insights`.

### Step 7: Build endpoint URL

Get the org-account host (lowercase, underscores → hyphens):
```sql
SELECT LOWER(REPLACE(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME(), '_', '-'));
```

Build the endpoint URL:
```
https://[HOST].snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server
```

Then smoke-test it with the `tools/list` curl in `docs/CLIENTS.md` (include `Accept: application/json, text/event-stream`). Expect `customer_energy_insights`.

### Step 7b (recommended): Least-privilege role

Ask the user whether to run `sql/05-least-privilege-role.sql`. It creates `MCP_READER`, moves the service user onto it, and issues a new PAT restricted to that role (shown once). If they run it, use the new token in the summary.

### Step 8: Output summary

Display to user:

```
✅ Snowflake MCP Server Setup Complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 MCP CONNECTION VALUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MCP Endpoint URL:
https://[ACCOUNT].snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server

PAT Token:
[TOKEN_VALUE]

Headers every PAT-based client sends:
  Authorization: Bearer [TOKEN_VALUE]
  X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN
  Accept: application/json, text/event-stream

Claude Code:
  claude mcp add --transport http snowflake-cirrus [ENDPOINT_URL] \
    --header "Authorization: Bearer [TOKEN_VALUE]" \
    --header "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  SAVE THESE VALUES - The PAT token cannot be retrieved again.

📖 Next: connect a client (docs/CLIENTS.md). For Salesforce Agentforce, run /register-salesforce-mcp.
```

## Error handling

### Error: "EMBED_TEXT_768 is not available for trial accounts"

**Solution:**
1. Go to Snowflake account settings
2. Click "Upgrade Account"
3. Add credit card to enable billing
4. Wait 5 minutes
5. Re-run this skill

### Error: "MCP SERVER already exists"

**Solution:**
Drop and recreate:
```sql
DROP MCP SERVER IF EXISTS CIRRUSSOLAR.PUBLIC.cirrus_solar_mcp_server;
```
Then re-run Step 6.

### Error: "Network policy required for PAT"

**Solution:**
The script creates a permissive network policy. If this fails, the user's account may have network restrictions. They need to create a policy manually.

## Files used

- `sql/01-create-database-and-tables.sql`
- `sql/02-create-cortex-search-service.sql`
- `sql/03-create-pat-authentication.sql`
- `sql/04-create-mcp-server.sql`
- `sql/05-least-privilege-role.sql` (optional, recommended)

## Success criteria

- ✅ Database and table exist with sample data
- ✅ Cortex Search Service is ACTIVE
- ✅ PAT token generated and displayed
- ✅ MCP server created with `customer_energy_insights` tool
- ✅ Endpoint URL provided to user
- ✅ User has the endpoint URL and credentials needed to connect an MCP client

# Troubleshooting

Errors grouped by where they happen: Snowflake setup, calling the MCP server, and specific clients.

## Snowflake setup

### "EMBED_TEXT_768 is not available for trial accounts"
Cortex Search needs a paid account.
1. In Snowsight, go to **Admin → Billing** (or **Account → Billing**).
2. Click **Upgrade Account** and add a payment method.
3. Wait about 5 minutes for Cortex features to activate, then re-run `sql/02-create-cortex-search-service.sql`.

### Cortex Search create fails on the `ON` clause
The single-index form takes **one** text column (`ON search_text`). To index several columns independently, use `TEXT INDEXES ... VECTOR INDEXES ...` instead. `sql/02` builds one combined `search_text` column for this reason.

### "Cortex Search Service does not exist or access is not authorized"
- **Just created?** The index takes a few minutes to build. Check `SHOW CORTEX SEARCH SERVICES IN SCHEMA CIRRUSSOLAR.PUBLIC;` and retry.
- **Still failing?** The role needs USAGE on the database, the schema, **and** the service. See the grants in `sql/02` and `sql/05`.

### "Warehouse COMPUTE_WH does not exist"
Create it, or change the warehouse name in the scripts:
```sql
CREATE WAREHOUSE COMPUTE_WH WITH WAREHOUSE_SIZE = 'X-SMALL' AUTO_SUSPEND = 60;
```

### PAT creation errors
| Error | Fix |
|---|---|
| Syntax error near `EXPIRATION_TIME_IN_DAYS` | The parameter is `DAYS_TO_EXPIRY = <n>` |
| Role restriction required or invalid | Service users must set `ROLE_RESTRICTION`, and the role must already be **granted** to the user |
| "Network policy is required for PAT" | Create the network policy and apply it to the user (`sql/03`, steps 4–5) |
| "Authentication policy does not allow PAT" | Apply `mcp_pat_auth_policy` to the user (`sql/03`, steps 2–3) |
| Can't create an authentication policy | Use ACCOUNTADMIN, or a role with `CREATE AUTHENTICATION POLICY` |

### "MCP SERVER already exists"
Use `CREATE OR REPLACE`, or drop it first, then **re-run the grants**:
```sql
DROP MCP SERVER IF EXISTS CIRRUSSOLAR.PUBLIC.cirrus_solar_mcp_server;
```

## Calling the MCP server

### `tools/list` returns no tools, or tools are missing
The role is missing a per-tool grant. USAGE on the MCP server alone exposes nothing. The role also needs USAGE on the database, schema, and search service (or SELECT on a semantic view, USAGE on an agent or UDF, and so on). Check with `SHOW GRANTS TO ROLE MCP_READER;`.

### Everything broke after changing the MCP server
`CREATE OR REPLACE MCP SERVER` **drops all grants** on it. Re-run the `GRANT USAGE ON MCP SERVER ...` statements (`sql/04` and `sql/05`).

### 401 / 403 / `invalid_client`
- **Expired or revoked token.** Run `SHOW PROGRAMMATIC ACCESS TOKENS FOR USER mcp_service_user;`, then create a new token and update the client.
- **Network policy blocking the caller.** Add the client's egress IPs. The rejection can show up as `invalid_client`.
- **Wrong role.** The PAT acts only as its `ROLE_RESTRICTION` role, and secondary roles are ignored. Grant the needed privileges to that role.
- **OAuth user on an admin role.** Snowflake OAuth blocks ACCOUNTADMIN by default. Give the user a non-admin default role such as `MCP_READER`.

### 406 / 415, or empty responses
Send both `Content-Type: application/json` and `Accept: application/json, text/event-stream`. Responses may stream as SSE.

### Client can't connect, but curl works
Check the hostname. Use the org-account form (`myorg-myaccount.snowflakecomputing.com`) and replace underscores with hyphens. Some clients fail on underscores in hostnames.

### Verify outside any client
```bash
curl -X POST "https://<org>-<account>.snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer <PAT>" \
  -H "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```
Get the host from `SELECT LOWER(REPLACE(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME(), '_', '-'));`.

### The agent answers without calling the tool
Make the tool `description` in the `CREATE MCP SERVER` spec more specific: say what it searches, which fields it returns, and which questions it answers. Recreate the server, then re-run the grants.

## Client: Salesforce Agentforce

### "We couldn't connect to the MCP server" (30-second timeout)
You registered the Snowflake URL directly with **No Authentication**. Snowflake rejects calls without the PAT headers. Use the stand-in workaround in [clients/agentforce.md](clients/agentforce.md):
1. Register any reachable, unauthenticated MCP server as a stand-in.
2. Edit the generated Named Credential so it points at Snowflake, and add the two PAT headers.
3. Only then open **Manage Tools**.

### "We couldn't save the tools due to an internal error"
Tools were managed before the Named Credential was edited, or the URL was swapped after tools were saved.
1. Delete the MCP server. If that's blocked, see the next error.
2. Register it again, and edit the Named Credential **before** you manage tools.

### "We couldn't delete the server because it is still in use"
An agent action still references the server.
1. Go to **Setup → Agentforce Asset Library → Actions**.
2. Delete the actions that use this MCP server.
3. Delete the MCP server.

### The agent answers but doesn't use Snowflake data
- Check that `customer_energy_insights` is added to the agent and listed under **Agentforce Asset Library → Actions**.
- Make sure the agent's instructions tell it to use the action for energy, consumption, and efficiency questions.
- Open the preview trace. You should see the tool call and an output evaluation of **GROUNDED**.

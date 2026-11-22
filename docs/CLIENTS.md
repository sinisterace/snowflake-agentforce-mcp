# Connecting MCP clients

The Snowflake-managed MCP server is a standard remote MCP endpoint (Streamable HTTP, MCP revision 2025-11-25, tools capability). Any client that speaks remote MCP can use it. What differs between clients is **how they authenticate**:

| Client | Auth | Guide |
|---|---|---|
| curl / MCP Inspector | PAT headers | [below](#curl-smoke-test) |
| Claude Code | PAT headers | [below](#claude-code) |
| Cursor | PAT headers, or OAuth (`sql/06`) | [below](#cursor) |
| Claude (claude.ai / Desktop custom connector), ChatGPT | Snowflake OAuth (`sql/06`) | [below](#oauth-clients-claude-chatgpt) |
| Salesforce Agentforce | PAT through Named Credentials (workaround) | [clients/agentforce.md](clients/agentforce.md) |

You'll need:
- **Endpoint:** `https://<org>-<account>.snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server`. Use the org-account host, with underscores replaced by hyphens. `sql/04` prints it.
- **PAT** (from `sql/03`, or the least-privilege token from `sql/05`) for header-based clients.

All PAT-based requests send:

```
Authorization: Bearer <PAT>
X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN
Accept: application/json, text/event-stream
```

---

## curl smoke test

Do this first, before you configure any client.

```bash
export SNOWFLAKE_MCP_URL="https://<org>-<account>.snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server"
export SNOWFLAKE_PAT="<token>"

# List tools
curl -s -X POST "$SNOWFLAKE_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $SNOWFLAKE_PAT" \
  -H "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

# Call the search tool
curl -s -X POST "$SNOWFLAKE_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $SNOWFLAKE_PAT" \
  -H "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"customer_energy_insights","arguments":{"query":"account ACC-001 energy output","columns":["month","year","energy_produced_kwh"],"limit":12}}}'
```

If `tools/list` comes back empty, the calling role is missing a per-tool grant. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

To browse the tools interactively, the MCP Inspector (`npx @modelcontextprotocol/inspector`) works too. Choose the Streamable HTTP transport and add the same headers.

---

## Claude Code

```bash
claude mcp add --transport http snowflake-cirrus "$SNOWFLAKE_MCP_URL" \
  --header "Authorization: Bearer $SNOWFLAKE_PAT" \
  --header "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN"
```

Then ask, for example: *"Using snowflake-cirrus, what was account ACC-001's energy output by month?"* Check the connection with `claude mcp list`, or with `/mcp` inside a session.

---

## Cursor

Add the server to `~/.cursor/mcp.json` (or `.cursor/mcp.json` in a project):

```json
{
  "mcpServers": {
    "snowflake-cirrus": {
      "url": "https://<org>-<account>.snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server",
      "headers": {
        "Authorization": "Bearer <PAT>",
        "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN"
      }
    }
  }
}
```

For per-user sign-in instead of a shared token, create a confidential OAuth integration (`sql/06`, option B) and configure Cursor with its client ID and secret.

---

## OAuth clients (Claude, ChatGPT)

Hosted assistants connect through a sign-in flow rather than static headers:

1. Run `sql/06-oauth-integration.sql`. It creates a public PKCE integration with Claude's callback URL as an example.
2. Get the client ID with `SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('MCP_OAUTH_CLAUDE');`.
3. Add a custom connector in the client, using the MCP endpoint URL and that client ID.
4. Each user signs in with their own Snowflake account. Tools run as that user's **default role**. Snowflake OAuth blocks ACCOUNTADMIN by default, so give users `MCP_READER` (`sql/05`).

---

## Salesforce Agentforce

Agentforce's MCP client offers only *No Authentication* or *OAuth 2.0 Client Credentials*, so it can't send Snowflake's PAT headers natively. The workaround is to register a stand-in server, then edit the Named Credential Salesforce generates so it points at Snowflake and injects the headers.

The full walkthrough, plus the `/register-salesforce-mcp` skill, is in [clients/agentforce.md](clients/agentforce.md).

---

## Writing a good tool description

Every client decides *when* to call a tool from its `description` in the `CREATE MCP SERVER` spec. That description matters more than any client setting. Say what data the tool searches, which fields come back, and which questions it answers. Recreate the server (and re-run grants) if you change it. See `sql/04`.

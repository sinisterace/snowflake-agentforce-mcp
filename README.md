# Snowflake Managed MCP Server with Cortex Search

**Expose governed Snowflake data to any AI agent with SQL alone. No middleware, no ETL, no copies.**

This repo builds an end-to-end reference on Snowflake: a Cortex Search service over operational data, published as a tool on a **Snowflake-managed MCP server**, secured with a service user, PAT or OAuth, network policies, and a least-privilege role. Any MCP client can then query it in natural language: Claude, Cursor, ChatGPT, Salesforce Agentforce, or your own agents.

The sample dataset is a fictional residential solar company, *Cirrus Solar* (monthly production, consumption, grid export, and efficiency per customer). Swap in your own table and the pattern stays the same.

---

## Architecture

```
MCP clients ── Claude · Cursor · ChatGPT · Agentforce · custom agents
      │  tools/list · tools/call  (Streamable HTTP)
      │  OAuth (interactive) or PAT (headless)
      ▼
┌──────────────────────────── Snowflake ────────────────────────────┐
│ Network policy  →  MCP SERVER  →  CORTEX SEARCH SERVICE  →  TABLE │
│                    (managed)      (hybrid vector+keyword)          │
│                   RBAC on every hop · masking/row policies apply   │
└────────────────────────────────────────────────────────────────────┘
```

**What gets built:**

| # | Script | Snowflake objects |
|---|---|---|
| 1 | [`01-create-database-and-tables.sql`](sql/01-create-database-and-tables.sql) | `CIRRUSSOLAR` database, `CUSTOMER_ENERGY_DATA` table and sample rows |
| 2 | [`02-create-cortex-search-service.sql`](sql/02-create-cortex-search-service.sql) | `ENERGY_DATA_SEARCH_SERVICE`: hybrid search over a combined text column, filterable attributes, 1-hour target lag |
| 3 | [`03-create-pat-authentication.sql`](sql/03-create-pat-authentication.sql) | `TYPE = SERVICE` user, PAT-only authentication policy, network policy, role-restricted PAT |
| 4 | [`04-create-mcp-server.sql`](sql/04-create-mcp-server.sql) | `cirrus_solar_mcp_server` exposing the `customer_energy_insights` tool |
| 5 | [`05-least-privilege-role.sql`](sql/05-least-privilege-role.sql) *(recommended)* | `MCP_READER` role with only the per-object grants the tool needs, plus a new 30-day PAT |
| 6 | [`06-oauth-integration.sql`](sql/06-oauth-integration.sql) *(optional)* | Snowflake OAuth security integration for interactive clients (Claude, Cursor) |

---

## Quick start

### Prerequisites
- A Snowflake account with Cortex Search available. Trial accounts can't use Cortex embeddings.
- `ACCOUNTADMIN`, or equivalent rights to create users, policies, and integrations.
- A warehouse. The scripts use `COMPUTE_WH`.

### 1. Run the SQL
Run `sql/01` through `sql/04` in order in a Snowsight worksheet, then `sql/05` to replace the demo's ACCOUNTADMIN token with a least-privilege one.
- Wait a few minutes after `02` for the index to build.
- The PAT from `03` (and from `05`) is shown **once**, so copy it immediately.
- `04` prints your MCP host. The endpoint is:
  ```
  https://<org>-<account>.snowflakecomputing.com/api/v2/databases/CIRRUSSOLAR/schemas/PUBLIC/mcp-servers/cirrus_solar_mcp_server
  ```

### 2. Smoke test
```bash
curl -s -X POST "$SNOWFLAKE_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $SNOWFLAKE_PAT" \
  -H "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```
You should see `customer_energy_insights`.

### 3. Connect a client
For example, Claude Code:
```bash
claude mcp add --transport http snowflake-cirrus "$SNOWFLAKE_MCP_URL" \
  --header "Authorization: Bearer $SNOWFLAKE_PAT" \
  --header "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN"
```
[`docs/CLIENTS.md`](docs/CLIENTS.md) covers Cursor, OAuth clients (Claude, ChatGPT), and [Salesforce Agentforce](docs/clients/agentforce.md).

**Try asking:**
- "What was the energy output for account ACC-001?" returns its monthly production readings (11 readings across 9 months).
- "Show me the energy production for customer C002" returns 3 monthly readings.
- "How efficient is the system for customer C003?" returns efficiency percentages.

### Or let a coding agent do it
This repo ships Claude Code skills in `.claude/skills/`:
- **`/setup-snowflake-mcp`** runs the SQL, checks each step, and outputs the endpoint, token, and client snippets. It expects a Snowflake MCP or SQL connection in your agent.
- **`/register-salesforce-mcp`** walks through the Agentforce registration.

---

## Snowflake design notes

**Cortex Search, not raw SQL.** Agents rarely know your schema or exact identifiers. Cortex Search combines vector and keyword retrieval with reranking, so "account ACC-001", "customer C001", and "July 2025 output" all land on the right rows. A single-index service searches **one** text column, so `sql/02` builds a `search_text` column from the identifiers, period, and readings, and keeps `customer_id`, `account_number`, `month`, and `year` as filterable `ATTRIBUTES`.

**Add Cortex Analyst for aggregates.** Search retrieves rows. It doesn't compute "total kWh in Q3 across all customers". Add a `CORTEX_ANALYST_MESSAGE` tool over a semantic view on the same MCP server for that (example in `sql/04`). Other tool types are `CORTEX_AGENT_RUN`, `SYSTEM_EXECUTE_SQL` (read-only by default), and `GENERIC` (UDFs and procedures).

**RBAC is per object.** USAGE on the MCP server exposes nothing by itself. The caller's role needs USAGE on the database, schema, and search service, and any tool it can't use is hidden from `tools/list`. Also note that `CREATE OR REPLACE MCP SERVER` drops grants, so keep them in the same script.

**Pick auth per client.**
- *OAuth* gives interactive users their own identity and roles. Admin roles are blocked by default.
- *PATs* are for headless clients: a `TYPE = SERVICE` user, a PAT-only authentication policy, a network policy locked to the client's IPs, `ROLE_RESTRICTION` to a single read-only role, and short `DAYS_TO_EXPIRY`.

**Know the cost model.**
- *Serving compute:* billed per GB-month of indexed data while serving is resumed, even with no queries. Run `ALTER CORTEX SEARCH SERVICE ... SUSPEND SERVING` when idle.
- *Embedding tokens:* billed for new or changed rows only.
- *Warehouse:* runs only the source query, index build, and refreshes. Queries don't use it.
- *Monitoring:* `ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY` and `CORTEX_SEARCH_SERVING_USAGE_HISTORY`.

More detail, including the threat model, performance, and monitoring queries, is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Documentation

| Doc | Covers |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, request walkthrough, auth and RBAC, security, cost, performance, monitoring |
| [CLIENTS.md](docs/CLIENTS.md) | Connecting curl, Claude Code, Cursor, OAuth clients |
| [clients/agentforce.md](docs/clients/agentforce.md) | Salesforce Agentforce through the Named Credentials header workaround |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Setup, auth, RBAC, and client errors |

**Related:** [cirrus-solar-mcp-server](https://github.com/sinisterace/cirrus-solar-mcp-server) is the *custom* alternative. It's a self-hosted Node MCP server that wraps Cortex Analyst (text-to-SQL) over the same dataset.

---

## Security notes

- Steps 1–4 use ACCOUNTADMIN for brevity. Run `sql/05` before anyone else touches this.
- The demo network policy allows all IPs. Lock it to your client's egress IPs.
- Never commit tokens. Keep them in a secrets manager or the client's encrypted credential store, and rotate them before `DAYS_TO_EXPIRY`.

## License

[MIT](LICENSE)

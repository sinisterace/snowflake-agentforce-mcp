# Architecture: Snowflake-managed MCP over Cortex Search

How the Snowflake pieces fit together, why each one is there, and what to watch for in cost, security, and performance.

---

## The big picture

**Goal:** let any AI agent query governed Snowflake data in natural language, in place, with no ETL, no data copies, and no custom middleware.

```
AI agent / MCP client  (Claude, Cursor, ChatGPT, Agentforce, custom agents)
    │  MCP over HTTPS: tools/list, tools/call
    │  auth: Snowflake OAuth or PAT
    ▼
┌──────────────────────────── Snowflake account ────────────────────────────┐
│  Network policy        (IP allowlist for the caller)                       │
│        ▼                                                                   │
│  MCP SERVER object     (cirrus_solar_mcp_server, managed endpoint)         │
│        ▼  RBAC: USAGE on the server AND on each tool's object              │
│  CORTEX SEARCH SERVICE (ENERGY_DATA_SEARCH_SERVICE, hybrid search)         │
│        ▼  indexed from a source query, refreshed to TARGET_LAG             │
│  TABLE                 (CUSTOMER_ENERGY_DATA, masking/row policies apply)  │
└────────────────────────────────────────────────────────────────────────────┘
```

Everything inside the box is a Snowflake object, created with SQL and governed by Snowflake RBAC. Nothing is deployed outside Snowflake.

---

## Components

### 1. Model Context Protocol (MCP)

- An open standard for connecting AI agents to tools and data: JSON-RPC 2.0 over Streamable HTTP.
- **Servers** expose *tools*, each with a name, a description, and an input schema. **Clients** (agents) discover them with `tools/list` and invoke them with `tools/call`.
- The tool *description* is what an agent reasons over when deciding whether to call a tool, so it's part of the interface, not just documentation.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "customer_energy_insights",
    "arguments": {
      "query": "customer ACC-001 energy January 2025",
      "columns": ["energy_produced_kwh"],
      "limit": 12
    }
  }
}
```

### 2. Snowflake-managed MCP server

- **Creating it:** run `CREATE MCP SERVER ... FROM SPECIFICATION $$<yaml>$$`. There's no `ALTER`, so changes mean `CREATE OR REPLACE`, which **drops grants**. Keep grants in the same script.
- **Endpoint:** `https://<org>-<account>.snowflakecomputing.com/api/v2/databases/<db>/schemas/<schema>/mcp-servers/<name>`. Use hyphens, not underscores, in the host.
- **Protocol support:** MCP revision 2025-11-25, with lifecycle, ping, tools, and progress notifications. No resources, prompts, or sampling.
- **Tool types:**

| Type | Backed by | Use for |
|---|---|---|
| `CORTEX_SEARCH_SERVICE_QUERY` | Cortex Search service | Finding relevant rows or documents (this repo) |
| `CORTEX_ANALYST_MESSAGE` | Semantic view | Text-to-SQL for aggregates, trends, joins |
| `CORTEX_AGENT_RUN` | Cortex Agent | Delegating a multi-step task to an agent that runs inside Snowflake |
| `SYSTEM_EXECUTE_SQL` | Warehouse | Running SQL (`read_only: true` by default) |
| `GENERIC` | UDF or stored procedure | Custom logic you've already written in Snowflake |

- **Limits:** 50 tools per server, a 15-minute `tools/call` timeout, and 250 KB response truncation for SQL and generic tools.

**Managed vs. custom MCP server**

| | Managed (this repo) | Custom ([cirrus-solar-mcp-server](https://github.com/sinisterace/cirrus-solar-mcp-server)) |
|---|---|---|
| Infrastructure | None | You host it |
| Auth | Snowflake OAuth / External OAuth / PAT | Whatever you build |
| Governance | Native RBAC, policies, audit | You re-implement it, or pass a service identity through |
| Reach | Snowflake capabilities only | Can call any API or combine several sources |

### 3. Cortex Search service

Cortex Search is Snowflake's managed retrieval engine. It combines **vector and keyword search with semantic reranking**, built from a SQL source query.

```sql
CREATE CORTEX SEARCH SERVICE ENERGY_DATA_SEARCH_SERVICE
  ON search_text                                -- the ONE text column to search
  ATTRIBUTES customer_id, account_number, month, year   -- filterable columns
  WAREHOUSE = COMPUTE_WH                        -- builds and refreshes the index
  TARGET_LAG = '1 hour'                         -- freshness target
AS (SELECT <search_text expression>, <columns to return> FROM CUSTOMER_ENERGY_DATA);
```

Design choices in `sql/02`:
- **One search column.** The single-index form takes exactly one `ON` column, so the source query builds a `search_text` string from the identifiers, the period, and the readings. Matches then work on any part: "account ACC-001", "C001", "July 2025".
- **Attributes are for filtering.** Clients can narrow results exactly, for example `{"@eq": {"account_number": "ACC-001"}}`. Any column in the source query can be *returned*.
- **Multi-index is the next step.** When columns need independent lexical or semantic indexes, use `TEXT INDEXES ... VECTOR INDEXES ...`.
- **Governance carries through.** Masking and row access policies on the source table can apply to results (`INHERIT_DATA_GOVERNANCE_POLICIES`).

**Lifecycle**
1. **Build:** the warehouse runs the source query, Snowflake embeds the search column (default model `snowflake-arctic-embed-m-v1.5`), and the index is built. That takes minutes for small tables.
2. **Refresh:** incremental, to stay within `TARGET_LAG`. Only new or changed rows are re-embedded, and refreshes that find no changes cost nothing.
3. **Serve:** queries run on dedicated Cortex Search serving compute, **not** on your warehouse.

**What it isn't for:** aggregations, joins, or computed answers ("total kWh for all customers in Q3"). Add a `CORTEX_ANALYST_MESSAGE` tool over a semantic view for those. Both tools can live on the same MCP server.

### 4. Authentication and authorization

| Method | Best for | Identity |
|---|---|---|
| **Snowflake OAuth** (`sql/06`) | Interactive clients: Claude, ChatGPT, Cursor, VS Code | Each end user, with their own default role |
| **External OAuth** (Okta, Entra ID) | Enterprises with a central IdP | Each end user, through the IdP |
| **PAT** (`sql/03`, `sql/05`) | Headless or server-to-server clients that can only send headers | A `TYPE = SERVICE` user, restricted to one role |

How the PAT setup in this repo works:
- **Service user.** `TYPE = SERVICE` means no password or MFA login. It exists only for programmatic access.
- **Authentication policy.** It allows only PATs, with default and maximum expiry limits.
- **Network policy.** Required for PATs. Lock it to the client's egress IPs.
- **The token.** `ROLE_RESTRICTION` pins it to a single role (required for service users), and `DAYS_TO_EXPIRY` forces rotation.

**Authorization is per object.** USAGE on the MCP server alone exposes nothing. The calling role also needs USAGE on the database, schema, and search service (or SELECT on a semantic view, USAGE on an agent or UDF, and so on). A tool the role can't use is silently left out of `tools/list`. `sql/05` builds that minimal `MCP_READER` role.

---

## Request walkthrough

**User asks the agent:** "What was the energy output for account ACC-001?"

1. **Agent reasoning.** The agent matches the question against the tool descriptions and picks `customer_energy_insights`.
2. **Tool call.** It sends `tools/call` with `{"query": "account ACC-001 energy output", "columns": ["month","year","energy_produced_kwh"], "limit": 12}`.
3. **Edge checks.** Snowflake checks the network policy and validates the OAuth token or PAT. The session takes the restricted role (`MCP_READER`).
4. **RBAC.** The role has USAGE on the MCP server and on `ENERGY_DATA_SEARCH_SERVICE`, so the call proceeds.
5. **Search.** Cortex Search embeds the query, runs hybrid retrieval and reranking over the index, and applies any filter and the requested columns.
6. **Response.** The MCP server returns the rows as MCP content:
   ```json
   {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"[{\"month\":2,\"year\":2025,\"energy_produced_kwh\":710.4}, ...]"}]}}
   ```
7. **Answer.** The agent formats the rows for the user: *"February: 710.4 kWh, March: 840.6 kWh, ..."*

---

## Security

### Trust boundaries

| Boundary | Control |
|---|---|
| Client → Snowflake | TLS, network policy, OAuth or PAT |
| Token → role | `ROLE_RESTRICTION` (PAT) or default role (OAuth). Admin roles are blocked for OAuth by default |
| Role → tools | Per-object grants. Tools the role can't use are hidden from `tools/list` |
| Search → data | The search service runs with owner's rights over a defined source query. Masking and row access policies can be inherited |

### Threat model

| Threat | Mitigation | Residual risk |
|---|---|---|
| Stolen PAT | Network policy to known IPs, single read-only role, short `DAYS_TO_EXPIRY`, `LOGIN_HISTORY` alerting | Medium until it expires or is revoked |
| Over-broad access | `MCP_READER` with USAGE on only the needed objects. The source query exposes only intended columns | Low |
| Data exfiltration through the agent | Limit columns in the source query, use row access policies, and audit tool usage | Medium (the agent can read whatever the role allows) |
| Prompt injection | Search tools only retrieve. Avoid `SYSTEM_EXECUTE_SQL` with `read_only: false` | Low for search-only servers |
| Runaway cost | Suspend serving when idle, use a modest `TARGET_LAG` and a dedicated small warehouse, and monitor usage views | Low |

---

## Cost model

| Component | Billed for | Lever |
|---|---|---|
| Serving compute | GB-month of indexed data (rows + embeddings), whenever serving is resumed | `ALTER CORTEX SEARCH SERVICE ... SUSPEND SERVING`, `AUTO_SUSPEND` |
| Embedding tokens | Tokens in the search column for new or changed rows | Keep `search_text` focused, and avoid churning rows |
| Warehouse | Source query, index build, refreshes (no-change refreshes are free) | Dedicated XS–M warehouse, longer `TARGET_LAG` |
| Storage | Materialized source and index | Narrow source query |

At demo scale (~20 rows) the total is a few dollars. Suspend serving afterwards.

---

## Performance

- **`tools/list`** is metadata only, typically well under a second.
- **`tools/call`** (search) typically takes 0.5–2s, depending on index size, `limit`, and the columns returned. It doesn't depend on warehouse state, because serving runs on separate compute.
- **Freshness** is bounded by `TARGET_LAG`. Lower it for time-sensitive data, at the cost of more frequent refreshes.
- **Response size:** keep `columns` and `limit` tight. Agents do better with 5–20 focused rows than with hundreds.

---

## Monitoring

```sql
-- Cortex Search credits per service, per day, split by consumption type
-- (serving vs. embedding tokens)
SELECT usage_date, service_name, consumption_type, model_name, tokens, credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
WHERE service_name = 'ENERGY_DATA_SEARCH_SERVICE'
ORDER BY usage_date DESC;

-- Hourly serving credits (non-zero whenever serving is resumed)
SELECT start_time, end_time, service_name, credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_SERVING_USAGE_HISTORY
WHERE service_name = 'ENERGY_DATA_SEARCH_SERVICE'
ORDER BY start_time DESC;

-- Who is authenticating as the MCP service user, and from where
SELECT event_timestamp, client_ip, first_authentication_factor, is_success, error_message
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE user_name = 'MCP_SERVICE_USER'
ORDER BY event_timestamp DESC
LIMIT 100;

-- Queries issued by the service user (for example, from SQL or Analyst tools)
SELECT start_time, role_name, warehouse_name, total_elapsed_time, query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE user_name = 'MCP_SERVICE_USER'
ORDER BY start_time DESC
LIMIT 100;
```

Account Usage views lag by up to a few hours. Client-side traces (for example, Agentforce interaction traces or Claude Code's `/mcp` view) show the tool calls themselves.

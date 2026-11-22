# Client guide: Salesforce Agentforce

This connects a Salesforce Agentforce agent to the Snowflake-managed MCP server, so the agent can answer questions from live Snowflake data without copying it into Salesforce.

**Before you start:** finish the Snowflake setup (`sql/01`–`04`, ideally `05` too) and confirm the [curl smoke test](../CLIENTS.md#curl-smoke-test) works. You also need System Administrator access in an org with Agentforce enabled.

## Why it needs a workaround

| | Supports |
|---|---|
| **Agentforce MCP client** | No Authentication, or OAuth 2.0 Client Credentials |
| **Snowflake MCP server** | Snowflake OAuth (interactive), External OAuth, or PAT bearer headers |

The two have no auth method in common. Agentforce does create a **Named Credential** for each MCP server it registers, though, and Named Credentials can send custom headers. So the PAT can be injected there:

1. Register a stand-in MCP server that needs no auth. This creates the Named Credential.
2. Point that Named Credential at Snowflake and add the PAT headers.
3. Only then discover and save the tools.

At runtime, every tool call goes Agentforce → Named Credential (adds headers) → Snowflake, which validates the PAT, checks RBAC, and runs Cortex Search.

## Steps

### 1. Register a stand-in server

- Go to **Setup → Agentforce Registry → Register MCP Server**.
- **Name:** `snowflakeCirrus`
- **URL:** `https://cirrus-solar-mcp-server.onrender.com/mcp` (temporary). Any reachable MCP server that needs no auth will do, including your own deployment of the companion [cirrus-solar-mcp-server](https://github.com/sinisterace/cirrus-solar-mcp-server).
- **Auth:** No Authentication
- Click **Register**.

### 2. Point the Named Credential at Snowflake

- Go to **Setup → Named Credentials → `snowflakeCirrus` → Edit**.
- Set the **URL** to your Snowflake MCP endpoint (`sql/04` prints it).
- Add two custom headers:

| Name | Value |
|---|---|
| `Authorization` | `Bearer <YOUR_PAT>` |
| `X-Snowflake-Authorization-Token-Type` | `PROGRAMMATIC_ACCESS_TOKEN` |

- Click **Save**.

### 3. Manage tools

Do this only after step 2.

- Go to **Agentforce Registry → MCP Servers → `snowflakeCirrus` → Manage Tools**.
- Select `customer_energy_insights` and click **Save**.

### 4. Verify

Go to **Setup → Agentforce Asset Library → Actions** and confirm `customer_energy_insights` is listed.

### 5. Build an agent

1. In Agent Builder, create a new agent named `Cirrus Solar Support`.
2. Add the action `customer_energy_insights`.
3. Add instructions:
   ```
   You are a customer support agent for Cirrus Solar.
   When customers ask about energy production, consumption, or system efficiency,
   use the customer_energy_insights action to search for their records.
   ```
4. Test it with: *"What was the energy output for account ACC-001?"*

You should get monthly kWh values from Snowflake, and the preview trace should show the tool call with an output evaluation of **GROUNDED**.

> Prefer automation? In Claude Code, run the [`/register-salesforce-mcp`](../../.claude/skills/register-salesforce-mcp/SKILL.md) skill. It walks through the same steps.

## Production notes

- **Restrict the Snowflake network policy** (`sql/03`) to Salesforce's published egress IP ranges.
- **Use the `MCP_READER` token** from `sql/05`, not the ACCOUNTADMIN demo token.
- **Rotate the PAT** before it expires: create a new one, update the `Authorization` header on the Named Credential, then drop the old token.
- If you recreate the MCP server in Snowflake, **re-run its grants**, then reopen **Manage Tools** in Salesforce.

## Alternatives on the Salesforce side

| Approach | Good for | Trade-offs |
|---|---|---|
| **Snowflake MCP** (this repo) | Live data, no sync, reusable by every MCP client | Header workaround, per-query Snowflake cost, ~0.5–2s per call |
| **Custom MCP server** ([cirrus-solar-mcp-server](https://github.com/sinisterace/cirrus-solar-mcp-server)) | Full control over auth and logic, combining several sources | Infrastructure to host and secure |
| **Zero-copy into Salesforce Data Cloud** | Native Salesforce features (segments, reports, grounding) | Data Cloud licensing and setup; Salesforce-only |
| **ETL into Salesforce objects** | Lowest latency, standard reports | Stale data, duplicated storage, a pipeline to maintain |

Troubleshooting for Agentforce-specific errors is in [TROUBLESHOOTING.md](../TROUBLESHOOTING.md#client-salesforce-agentforce).

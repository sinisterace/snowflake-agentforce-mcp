---
name: register-salesforce-mcp
description: Register a Snowflake MCP server in Salesforce Agentforce using the Named Credentials workaround (Snowflake PAT auth vs. Salesforce OAuth), then expose its tools to an agent.
---

# Skill: register-salesforce-mcp

Guides the user through registering a Snowflake MCP server in Salesforce Agentforce using the Named Credentials workaround.

## What this skill does

Provides step-by-step instructions for registering Snowflake MCP in Salesforce when the auth methods don't align (Snowflake uses PAT, Salesforce expects OAuth).

## Prerequisites

- Snowflake MCP server already created (run `/setup-snowflake-mcp` first)
- MCP endpoint URL and PAT token from Snowflake setup
- Salesforce org with Agentforce enabled
- User has System Administrator access in Salesforce

## Usage

```
/register-salesforce-mcp
```

## What the agent should do

### Step 1: Explain the auth mismatch problem

Display to user:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  AUTH MISMATCH PROBLEM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Snowflake MCP requires: PAT (bearer token in headers)
Salesforce supports: No Auth OR OAuth 2.0 Client Credentials

These don't align. We'll use a workaround:

1. Register a no-auth stand-in server
2. Edit Named Credentials to inject PAT headers
3. Swap URL to point to Snowflake
4. Manage tools to discover real Snowflake tools

This creates the Named Credential object we need to inject authentication.
```

### Step 2: Provide stand-in server URL

Check if the user has a stand-in server. If not, provide this public no-auth MCP server:

```
Stand-in Server URL (temporary):
https://cirrus-solar-mcp-server.onrender.com/mcp

This server returns dummy tools with the same names as your Snowflake tools.
It exists only to create the Named Credential object.
```

### Step 3: Guide Salesforce registration

Display step-by-step instructions:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 SALESFORCE REGISTRATION STEPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

STEP 1: Register Stand-In Server
---------------------------------
1. In Salesforce Setup, search: "Agentforce Registry"
2. Click: MCP Servers → Register MCP Server
3. Fill in:
   - Server Name: snowflakeCirrus
   - Server URL: https://cirrus-solar-mcp-server.onrender.com/mcp
   - Authentication: No Authentication
4. Click: Register
5. Wait for success message

⚠️  DO NOT CLICK "Manage Tools" YET!

STEP 2: Edit Named Credentials (THE CRITICAL STEP)
---------------------------------------------------
1. In Setup, search: "Named Credentials"
2. Find and click: snowflakeCirrus
3. Click: Edit
4. Change URL to your Snowflake endpoint:
   [PASTE YOUR SNOWFLAKE URL HERE]
5. Scroll to "Custom Headers"
6. Click "Add Custom Header" (twice)
7. Add Header 1:
   Name: Authorization
   Value: Bearer [PASTE YOUR PAT TOKEN HERE]
8. Add Header 2:
   Name: X-Snowflake-Authorization-Token-Type
   Value: PROGRAMMATIC_ACCESS_TOKEN
9. Click: Save

STEP 3: Manage Tools (NOW it points to Snowflake)
--------------------------------------------------
1. Back in Agentforce Registry → MCP Servers
2. Click: snowflakeCirrus
3. Click: Manage Tools
4. You should see: customer_energy_insights
5. Check the box to select it
6. Click: Allow and Continue → Save
7. Wait for success message

STEP 4: Verify in Asset Library
--------------------------------
1. Setup → Agentforce Asset Library → Actions
2. Confirm you see: customer_energy_insights

✅ If you see it, registration is complete!
```

### Step 4: Provide test queries

Display:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧪 TEST YOUR INTEGRATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create an Agentforce agent and add the customer_energy_insights action.

Test queries:
1. "What was the energy output for account ACC-001?"
2. "Show me the energy production for customer C002"

Expected result: Agent returns monthly kWh values from Snowflake.

Check the trace to verify:
- Tool call to customer_energy_insights
- MCP RPC steps
- Output Evaluation: GROUNDED (means real data, not hallucinated)
```

### Step 5: Ask if they need help

```
Did the registration succeed?

If you encountered errors, see docs/TROUBLESHOOTING.md
(or the "Common errors" section below).
```

## Common errors and guidance

### Error: "We couldn't connect to the MCP server" (30-second timeout)

**Cause:** User tried to register Snowflake URL directly with No Auth.

**Solution:** Must use the stand-in workaround. Start over at Step 1.

### Error: "We couldn't save the tools due to an internal error"

**Cause:** User managed tools BEFORE editing Named Credentials, or swapped URL after tools were saved.

**Solution:**
1. Delete the MCP server (may need to delete blocking actions first)
2. Start over with fresh registration
3. Make sure to edit Named Credentials BEFORE managing tools

### Error: "We couldn't delete the server because it is still in use"

**Cause:** An agent action references this MCP server.

**Solution:**
1. Setup → Agentforce Asset Library → Actions
2. Find actions with this MCP server name
3. Delete those actions
4. Then delete the MCP server

## Success criteria

- ✅ Named Credential `snowflakeCirrus` exists and points to Snowflake endpoint
- ✅ PAT headers configured in Named Credentials
- ✅ Tool `customer_energy_insights` appears in Agentforce Asset Library
- ✅ Test query in agent preview returns real Snowflake data
- ✅ Trace shows "GROUNDED" output evaluation

## Files referenced

- `docs/clients/agentforce.md` - The full Agentforce walkthrough and why the workaround is needed
- `docs/TROUBLESHOOTING.md` - Common errors and solutions

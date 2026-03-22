# Jira MCP (Cursor)

If the Jira MCP shows **“The MCP server errored”**, check:

1. **Use the npm server** — `~/.cursor/mcp.json` should run `mcp-jira-cloud`, not a missing local `package/build`.
2. **Environment variable names** — `mcp-jira-cloud` expects:
   - `JIRA_BASE_URL` — e.g. `https://YOURSITE.atlassian.net`
   - `JIRA_EMAIL` — your Atlassian account email
   - `JIRA_API_TOKEN` — from [Atlassian API tokens](https://id.atlassian.com/manage-profile/security/api-tokens)

Wrong names (`JIRA_URL`, `JIRA_API_MAIL`, `JIRA_API_KEY`) will fail authentication.

3. **Restart Cursor** after changing `mcp.json`.

Optional: point MCP at `scripts/run-jira-mcp.sh` (runs `npx -y mcp-jira-cloud@4`); keep the same `env` block in `mcp.json`.

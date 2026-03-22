#!/usr/bin/env bash
# Runs the official CocoaPods-style Jira MCP (npm: mcp-jira-cloud).
# Configure Cursor ~/.cursor/mcp.json with command "npx", args ["-y","mcp-jira-cloud@4"],
# and env: JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN (see Atlassian API tokens).
# This script is optional; you can point MCP directly at npx as above.
exec npx -y mcp-jira-cloud@4 "$@"

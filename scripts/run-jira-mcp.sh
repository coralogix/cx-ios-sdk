#!/usr/bin/env bash
# Run patched Jira MCP (uses /rest/api/3/search/jql)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../package" && exec node build/index.js

---
description: Implement a Jira ticket — fetch details, branch, plan, then wait for review.
argument-hint: <jira-ticket-url-or-key>
---

You are implementing a Jira ticket end-to-end on a new branch, **stopping before commit/push** so the user can review.

## Input

The user invoked `/implement` with: `$ARGUMENTS`

This is either a full Jira URL (e.g. `https://coralogix.atlassian.net/browse/CX-40205`) or a bare ticket key (e.g. `CX-40205`). Extract the ticket key with a regex like `[A-Z]+-\d+`. If you cannot find a key, stop and ask the user for one.

## Steps

Follow these in order. Do not skip ahead.

### 1. Pre-flight checks

Run these in parallel via Bash:

- `git status --porcelain` — working tree must be clean. If not, stop and ask the user how to proceed (stash, commit, or abort).
- `git rev-parse --abbrev-ref HEAD` — note the current branch.
- `git fetch origin` (optional but preferred) so the new branch is cut from up-to-date `master`/`main`.

If the working tree is dirty, **stop** and surface the dirty files to the user.

### 2. Fetch the ticket

Use the Atlassian MCP to pull the ticket. The relevant tools (load schemas via ToolSearch first):

- `mcp__claude_ai_Atlassian__getAccessibleAtlassianResources` — get the `cloudId` if you don't already know it.
- `mcp__claude_ai_Atlassian__getJiraIssue` — fetch the issue by key.

From the issue, capture:
- **Summary** (title)
- **Description** / acceptance criteria
- **Issue type** (Bug, Story, Task, Sub-task) — informs the commit prefix: `fix(` for bugs, `feat(` for everything else, unless project conventions say otherwise
- **Status** — if it's already `Done` / `Closed`, warn the user before proceeding
- **Linked issues / parent** — note them if present, they may carry context

If the Atlassian MCP returns an auth error, tell the user to run the `authenticate` tool and stop.

### 3. Propose a plan

Reply to the user with:

1. **Ticket summary** (one line: key + title + status + issue type)
2. **What I understand needs to change** (2–4 bullets, derived from description/AC)
3. **Files I expect to touch** (best guess from a quick repo scan — grep for key terms from the ticket)
4. **Proposed branch name**: `feat/CX-XXXXX-short-slug` (or `fix/...` for bugs). Keep the slug under ~5 words, lowercase, hyphenated. Derive it from the ticket summary.
5. **Open questions** if anything in the ticket is ambiguous

**Then stop and wait for the user's go-ahead.** Do not create the branch or write code yet.

### 4. After user approval

Once the user approves (or adjusts the plan):

1. Create and switch to the branch: `git checkout -b feat/CX-XXXXX-short-slug` (cut from `master` — verify with `git rev-parse master` first if unsure).
2. Implement the change. Follow repo conventions (see `CLAUDE.md` in the working directory). Run the project's test/build commands as you go.
3. **Do not commit. Do not push. Do not open a PR.**
4. When implementation is complete, summarise:
   - Branch name
   - Files changed (one-line list)
   - How you verified it (tests run, build status)
   - Anything you deferred or want a second look at
5. Tell the user: *"Ready for your review. Let me know if you want me to commit / push / open a PR, or adjust anything."*

## Guardrails

- Honour all rules in the working directory's `CLAUDE.md` (e.g. for cx-ios-sdk: no `fatalError`, attribute keys in `Keys.swift`, mirror demo-app changes, etc.).
- If the ticket scope balloons mid-implementation, stop and check in rather than silently expanding.
- Never `--no-verify`, never force-push, never amend. New commits only — and only when the user asks.
- If a test fails, diagnose the root cause; don't disable the test to make it pass.

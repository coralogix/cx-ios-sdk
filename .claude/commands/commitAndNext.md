---
description: Commit the current applied fix and advance to the next /fix-issues finding.
---

You're in the middle of a `/fix-issues` review-fix loop. The current fix has been applied and verified; the user has just approved it.

Do exactly this, in order:

1. **Stage and commit** only the files that changed for the current fix. Use a HEREDOC for the commit message. Follow this repo's commit-message convention (the prior commit message style on this branch — typically `TICKET type(scope): subject` with a short body explaining *why*, ending in the `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer).

2. **Show the next unresolved finding** from the most recent code review in this conversation, following the original `/fix-issues` protocol:
   - Show the current code (with file path + line range).
   - Explain the proposed fix and *why* it's the right call (not just what to type).
   - Apply the fix with Edit/Write.
   - Run the relevant linter/analyzer (and tests if behavior changed) to confirm clean.
   - Stop and wait for the user's review. Do NOT commit. Do NOT proceed to the finding after this one.

3. If there are no more findings left, say so plainly and summarize the branch state (commit count ahead of `master`, push status). Don't invent work.

Stay terse — no preamble like "Sure, I'll do that." Just do it.

Summarize what changed between two version tags, formatted for a Slack post.

Tags in this repo are bare semver (e.g., `2.6.2`, `2.6.3`) — no `v` prefix.

1. Resolve the `<from>` and `<to>` tags from `$ARGUMENTS`:
   - Two args: use them as `<from> <to>` in that order.
   - One arg: treat it as `<to>`; pick `<from>` as the next-lower tag from `git tag --sort=-v:refname | grep -A1 -x <to> | tail -1`.
   - No args: use the two newest tags from `git tag --sort=-v:refname | head -2`.
   - If a tag doesn't exist, stop and tell the user — don't guess.

2. Gather material to summarize from:
   - `git log <from>..<to> --no-merges` (commit subjects + bodies — the bodies often explain the "why").
   - PR titles/descriptions for any `(#NNN)` references via `gh pr view <NN>`.
   - `git diff --stat <from>..<to>` to sanity-check scope.

3. Write **high-level, user-facing summaries** — not commit titles, not PR lists. The audience is non-engineers on Slack. Rules:
   - One short sentence per item. No code identifiers, no file paths, no PR numbers, no ticket IDs, no author handles, no "@" mentions.
   - Lead with the user-visible effect ("Vietnamese text is now masked on iOS 17+") not the implementation ("fixed BCP-47 tag in TextScanner").
   - Collapse multiple commits that ship the same feature into one bullet.
   - Drop pure refactors, test-only changes, dead-code removals, doc tweaks, and CI changes unless they affect users.
   - If a fix references a customer-visible bug (scroll lag, crash, masking miss), say so plainly.

4. Output format (plain text, Slack-friendly, no markdown headings beyond what's shown):

   ```
   *iOS SDK <to>* (was <from>)

   *✨ New*
   • <one-sentence summary>
   • ...

   *🐛 Fixes*
   • <one-sentence summary>
   • ...
   ```

   Omit the New or Fixes section if it would be empty. If there's truly nothing user-visible, say so instead of padding.

5. Print the block to the chat for the user to copy. Do not post anywhere, do not create a GitHub release.

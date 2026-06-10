---
description: Review the changed code for reuse/simplification/efficiency cleanups and apply the fixes. Quality only — does not hunt for correctness bugs (use /code-review for that).
argument-hint: [pr:N | branch | file]
---

You are doing a quality-only pass on the current diff. The goal is **applied** cleanups, not bug discovery — for correctness review, the user wants `/code-review` instead.

## Phase 0 — Scope the diff

Same as `/code-review`:
- `pr:N` → `gh pr diff N` + `gh pr view N --json headRefName,baseRefName` → read files via `git show origin/<headRefName>:<path>`
- branch name → `git diff <base>...<branch>`
- file path → `git diff HEAD -- <path>`
- nothing → `git diff $(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')...HEAD`

If the diff is empty, also check `git diff HEAD` for uncommitted changes.

## Phase 1 — Find quality issues only

Run angles via the Agent tool in parallel. **Skip bug-hunting angles** (line-by-line correctness, removed-behavior audit). Run only:

**Angle A — Reuse**: Flag new code that re-implements something the codebase already has. Name the existing helper. The fix is to call the helper.

**Angle B — Simplification**: Flag unnecessary complexity added by the diff: redundant state, copy-paste blocks, deep nesting that `guard` would flatten, dead code, intermediate variables used once.

**Angle C — Efficiency**: Flag wasted work added by the diff: redundant computation, repeated I/O, blocking work on hot paths, unnecessary allocations in tight loops.

**Angle D — Altitude / Single Responsibility**: Flag functions that do "and/or" things — they should be split. Flag inline logic that belongs in an extracted helper. Flag parameters that have grown beyond 2-3 and should be a struct.

**Angle E — Project coding standards** (read `.claude/rules/CODING_STANDARDS.md`): Flag style/structure violations. Focus on the *quality* rules, not the safety ones:
- Pattern-following: same problem solved differently from existing pattern → switch to the established pattern
- Flat models when subtypes carry identical data → collapse the hierarchy
- Comments that say *what* (redundant with the code) instead of *why* (intent / trade-offs)
- Force-unwrap (`!`) on values that are guaranteed-non-nil → switch to non-optional types (this is a quality cleanup, not a safety bug)

## Phase 2 — No verification, just apply

For each candidate from Phase 1:
1. Show the current code (file + line range)
2. Explain the cleanup in one sentence
3. Apply the fix with `Edit`
4. Move to the next

If multiple candidates touch the same file, batch them in one `Edit` per file when possible.

## Phase 3 — Verify nothing broke

After all fixes are applied:
```bash
xcodebuild test -scheme Coralogix-Package -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | grep -E "^Test Suite|Executed [0-9]+ tests|failed|error:" | tail -10
```

Use the affected test target where possible (e.g. `-only-testing:CoralogixRumTests/<ClassName>`) for speed.

If any test fails, **stop**. Show the failure to the user. Don't try to "fix" the test — the cleanup might have changed something subtler than expected.

## Output

```
## Cleanups applied

1. ✅ <file>:<line> — <one-line summary>
2. ✅ <file>:<line> — <one-line summary>
…

## Tests
N/N passing across <suite list>. No regressions.
```

If you found nothing worth applying, say so plainly: `## No cleanups — diff is already clean.`

Don't commit. Wait for the user's review.

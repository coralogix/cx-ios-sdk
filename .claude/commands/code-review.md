---
description: Review the current diff for correctness bugs and reuse/simplification/efficiency cleanups. Pass --comment to post findings as inline PR comments, or --fix to apply the findings to the working tree after the review.
argument-hint: [low|medium|high] [pr:N | branch | file] [--comment] [--fix]
---

You are an expert software engineer performing a rigorous code review on the iOS RUM SDK.

Arguments may include:
- An effort level: `low`, `medium`, `high` (default: `high`)
- A target: a PR number like `pr:215`, a branch name, a file path, or nothing (review current branch vs base)
- `--comment`: post findings as inline GitHub PR comments
- `--fix`: apply findings as edits to the working tree

## Phase 0 — Gather the diff

Determine the diff scope from the argument:
- `pr:N` → run `gh pr diff N` and `gh pr view N --json headRefOid,headRefName,baseRefName`. Then run `git fetch origin <headRefName>` so the PR branch is available locally for file reads. Store the remote ref as `origin/<headRefName>`.
- branch name → `git diff <base>...<branch>`
- file path → `git diff HEAD -- <path>`
- nothing → detect base branch via `git remote show origin | grep 'HEAD branch'`, then `git diff <base>...HEAD`

If the diff is empty, also check `git diff HEAD` for uncommitted changes.

**Critical — pass the correct ref to all agents:** After Phase 0, all finder and verifier agents must read files from the PR branch, not the local working tree. Pass the ref (`origin/<headRefName>` for PRs, or the branch name otherwise) to each agent and instruct them to read files with `git show <ref>:<path>` rather than direct file reads. Include this instruction verbatim in every agent prompt: "Read files using `git show origin/<headRefName>:<path>` — do NOT use the Read tool or cat directly, as the local working tree is on a different branch."

## Phase 1 — Find candidates (run as parallel agents, up to 6 candidates each)

Run these angles via the Agent tool in parallel:

**Angle A — Line-by-line diff scan**: Read every hunk. For each changed line ask: what input, state, timing, or platform makes this wrong? Look for inverted conditions, off-by-one, nil deref via force-unwrap, wrong-variable copy-paste, swallowed errors, missing validation.

**Angle B — Removed-behavior audit**: For every deleted or replaced line, name the invariant it enforced. Search the new code for where that invariant is re-established. If you can't find it, that's a candidate.

**Angle C — Cross-file tracer**: For each changed function, grep for its callers and check whether the change breaks any call site. Check callees too.

**Angle D — Reuse**: Flag new code that re-implements something the codebase already has. Name the existing helper.

**Angle E — Simplification**: Flag unnecessary complexity added by the diff: redundant state, copy-paste, deep nesting, dead code.

**Angle F — Efficiency**: Flag wasted work: redundant computation, repeated I/O, blocking work added to hot paths.

**Angle G — Project coding standards** (read `.claude/rules/CODING_STANDARDS.md` at the repo root before running this angle): Flag any violation of the project-specific standards documented there. Key patterns to check on iOS:
- Extension functions on a Swift model placed in a separate file instead of co-located with the model
- Side-channel methods added on a conformer to bypass a `protocol` contract instead of extending the protocol
- A `protocol` / sealed-enum / class hierarchy where all subtypes carry structurally identical fields — should be a flat struct
- Test assertions that are absence/negative-based (`XCTAssertNil(payload["field_never_written"])`) rather than asserting a concrete positive value
- Shared mutable state read inside a closure or `DispatchQueue`-dispatched block via nullable access (`?.`) with a silent bail-out (`?? return`) where the assignment lifecycle of that state is not guaranteed
- Force-unwrap (`!`), force-cast (`as!`), force-try (`try!`), `fatalError(…)`, `precondition(…)`, `assert(…)` anywhere in SDK code — must use `guard` + `Log.e` instead

**Angle H — iOS SDK invariants** (read `AGENTS.md` section 4 at the repo root): Flag any violation of the iOS-specific SDK invariants documented there. Key patterns to check:
- New attribute-shaped string literals (`setAttribute(key: "…")`, `result["snake_case_key"] = …`, `keychain.*From*(service: …, key: "…")`) that don't go through `Keys.swift`
- New fields at the `cx_rum` top level without a parallel mirror into `instrumentation_data.otelSpan.attributes` via `AttrKey` in `InstrumentationData.swift`
- New shared mutable state (`var`) without `NSLock` / serial-queue / barrier protection
- Use of APIs newer than iOS 13.0 without `#available` guards
- Asymmetric changes to `Example/DemoAppSwift` (UIKit) vs `Example/DemoAppSwiftUI` (SwiftUI)
- Swizzling changes without `tearDown` restoration in the corresponding test target

Each candidate needs: `file`, `line`, `summary` (one sentence), `failure_scenario` (concrete inputs/state → wrong output/crash, or concrete maintenance cost).

## Phase 2 — Verify (recall-biased)

Dedup near-duplicates. For each remaining candidate, run one verifier agent: give it the diff + relevant file content (read via `git show origin/<headRefName>:<path>`) + the candidate. It returns **CONFIRMED / PLAUSIBLE / REFUTED**.

Each verifier agent prompt must include:
1. The full relevant diff hunk
2. The full file content fetched via `git show origin/<headRefName>:<path>` (not local file reads)
3. The candidate to verify

- **PLAUSIBLE by default** for concurrency races, nil on rare-but-reachable paths, off-by-one, retry storms, silent failures, iOS-13-availability gaps.
- **REFUTED** only when factually wrong (quote the line), provably impossible (show the invariant), or already handled in this diff.

Keep CONFIRMED and PLAUSIBLE. Drop REFUTED.

## Output

Return at most 10 findings ranked most-severe first:

```json
[
  {
    "file": "path/to/file.swift",
    "line": 123,
    "summary": "one-sentence bug statement",
    "failure_scenario": "concrete scenario"
  }
]
```

If nothing survives verification, return `[]`.

## Posting to GitHub (--comment)

If `--comment` was passed and the target is a GitHub PR:

1. Get the PR head SHA: `gh pr view <N> --json headRefOid -q .headRefOid`
2. Get the repo slug: `gh repo view --json nameWithOwner -q .nameWithOwner`
3. For each finding, post an inline comment with:
   ```bash
   gh api repos/{owner}/{repo}/pulls/{N}/comments \
     --method POST \
     -f body="**Issue:** <summary>\n\n<failure_scenario>" \
     -f commit_id="<head_sha>" \
     -f path="<file>" \
     -F line=<line> \
     -f side="RIGHT"
   ```
4. After all comments are posted, print a summary of how many were posted and the PR URL.

If a line number falls outside the diff for a given file (e.g. the finding is on an unchanged line), fall back to posting a top-level PR comment via:
```bash
gh pr comment <N> -b "..."
```

If the target is not a PR, print findings to the terminal and note that `--comment` was ignored.

## Applying fixes (--fix)

If `--fix` was passed, after producing the findings list, apply each fix as a direct edit to the file. Only apply when the fix is unambiguous and safe. Skip findings where the correct fix is unclear. After applying, run `xcodebuild test -scheme Coralogix-Package -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:CoralogixRumTests` (or the affected test target) to confirm nothing broke.

---
description: Switch to the repo's main branch, pull, and delete the just-merged local branch.
---

You're cleaning up after a PR was merged on the remote. The local branch the user is on was the head of that PR and is no longer needed locally.

Do exactly this, in order, in the current working directory:

1. **Capture the current branch name** with `git rev-parse --abbrev-ref HEAD`. Store it as `MERGED_BRANCH`.

2. **Refuse to run** if `MERGED_BRANCH` is `master`, `main`, or `develop`. Print a short error and stop — there's nothing to clean up.

3. **Detect the main branch.** Try `master` first; if it doesn't exist locally (`git show-ref --verify --quiet refs/heads/master`), use `main`. Store as `MAIN`.

4. **Check for uncommitted changes** with `git status --porcelain`. If non-empty, stop and tell the user — don't switch branches over dirty state.

5. **Switch and pull**: `git checkout $MAIN && git pull --ff-only`. If pull is not fast-forward, stop and report — don't try to merge or rebase.

6. **Delete the branch**: try `git branch -d $MERGED_BRANCH` first. If it fails with "not fully merged" (typical after a squash merge), retry with `git branch -D $MERGED_BRANCH` and note in your reply that it was force-deleted because the squash-merged SHA differs.

7. **Report**: one line — `Cleaned up <branch> → on <main> @ <short-sha>`.

Stay terse. No preamble. If any step fails for an unexpected reason, stop and show the user the error rather than improvising.

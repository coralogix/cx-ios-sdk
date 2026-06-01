# Code Review Instructions

  ## Versioning (CRITICAL - Check First)

  **When reviewing PRs that modify `package.json`, `version.ts`, or `CHANGELOG.md`:**

  1. Extract the version bump (e.g., 3.9.0 → 4.0.0)
  2. Check all commit messages in the PR for change types:
  - `feat!:` or `BREAKING CHANGE:` → requires **MAJOR** bump (X.0.0)
  - `feat:` → requires **MINOR** bump (x.Y.0)
  - `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:`, `update:` → requires **PATCH** bump (x.y.Z)

  3. **FLAG AS ERROR if:**
  - Major version bump without `feat!:` or `BREAKING CHANGE:` in commits
  - Minor version bump without any `feat:` commits
  - Version not bumped but changes warrant it

  > **Example violation:** PR has `feat: add user tracking` but bumps 2.0.0 → 3.0.0.
  > This is WRONG — should be 2.1.0. Flag immediately.

  **Conventional Commits:** `feat:`, `feat!:`, `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:`, `update:`

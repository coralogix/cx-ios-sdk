# Code Review Instructions

## Versioning (CRITICAL - Check First)

**When reviewing PRs that modify `*.podspec`, `Info.plist`, `Package.swift`, or `CHANGELOG.md`:**

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

## Principles

- **Follow SOLID principles** — Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, and Dependency Inversion.

- **Write clean, modular, and testable code**
  - Keep functions small, focused, and doing one thing — no "and/or" in names
  - Max 2–3 parameters; use options objects for more
  - No boolean flags — split into separate functions or use named options
  - No magic numbers/strings — extract literals into named constants
  - Avoid deep nesting; use guard clauses and early returns
  - Positive conditionals — no double negatives; extract complex predicates
  - Minimize side effects; prefer pure functions
  - Comment *why*, not *what* — intent and trade-offs only

## Review Checklist

- [ ] SemVer bump matches change type
- [ ] No runtime exceptions — property access is guarded
- [ ] No framework interference
- [ ] No performance regressions
- [ ] No forbidden imports in utility/core files
- [ ] SDK errors fail silently, never crash host app
- [ ] OTel spans are always ended
- [ ] Tests included for new features/bug fixes

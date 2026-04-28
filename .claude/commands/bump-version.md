Bump the SDK version using the existing script.

1. Run: `./version_bump.sh $ARGUMENTS`
   - Valid arguments: `patch`, `minor`, `major`
   - If no argument was given, ask the user which one before running.
2. Show the resulting `git diff` so the user can verify all files were updated.
3. Do NOT commit. Wait for the user to confirm before doing anything else.

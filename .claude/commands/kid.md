Review a PR / feature branch, learn what it actually changes, then explain **the problem and the solution like you're talking to a curious 4th-grader** (about 9 years old — smart, but knows zero programming words).

This is NOT a bug hunt. Your only job is to understand the change and make it click for someone with no coding background. If they want bugs, that's `/pr-review`.

## Step 1 — Find the change

Work out what to explain, in this order:

1. If `$ARGUMENTS` is a PR number or URL → `gh pr view <n> --json title,body,files` and `gh pr diff <n>`. Add `--repo <owner/repo>` if the argument names a different repo.
2. Else if `$ARGUMENTS` is a branch name → diff it against the default branch.
3. Else use the current branch: find the default branch (`git remote show origin` → HEAD branch, usually `master` or `main`), then `git diff <default>...HEAD` — stat first, then the full diff of the real source files. Skip lock files, generated files, `*.html` changelogs, and vendored dirs.

Read the actual changed code — and the ticket or PR description if there is one — so you genuinely understand it. Never guess from the filenames.

## Step 2 — Understand it (silently, for yourself)

Figure out, in your own head:
- What was wrong or missing before? → **the problem**
- What does this change actually do? → **the solution**
- Why is that better?

Keep this reasoning to yourself. The output must be simple — do the hard thinking here so the explanation can be easy.

## Step 3 — Explain it like they're 9

Rules:
- Short sentences. Everyday words.
- **No jargon.** Banned words include: API, null, thread, async, serialize, schema, cache, payload, refactor, race condition, session, sprint. If you must name a thing, describe *what it does* instead ("the little helper that writes down what happened").
- Use **one** real-world analogy — toys, a lunchbox, LEGO, a treehouse, a school backpack — and stick with it the whole way through. The analogy must actually match what the code does; don't stretch it.
- Warm and a little fun, but accurate.
- Keep the whole thing readable in under a minute.

Output exactly these sections:

**🧩 What we were trying to do** — one sentence: the goal.

**🐛 The problem** — what was going wrong, told through the analogy. 2–4 short sentences.

**🛠️ What we changed to fix it** — the solution, same analogy. 2–4 short sentences.

**✅ Why it's better now** — one or two sentences.

**🔎 Grown-up summary** — a single sentence a developer would recognize. This is the *only* place you're allowed a technical term or two, so the reader can connect the kid version back to the real change.

#!/usr/bin/env python3
"""Guard the READMEs that publish to coralogix.com/docs.

A nightly job in `coralogix/documentation` mirrors the files listed in SYNCED and
publishes them as customer-facing pages, so editing one is a documentation change.
`.claude/skills/rum-readme-authoring/SKILL.md` is the authoring guide.

Two modes, one path list:

  lint   Check the synced READMEs against the mechanical rules in that skill.
         Run by CI on every pull request. Also runnable by hand.

  hook   Claude Code PreToolUse gate: refuse an edit to a synced README until the
         rum-readme-authoring skill has been loaded in this session. Reads the hook
         payload on stdin; exit 2 blocks the tool call and hands stderr back to the
         agent as an instruction.

The prose rules in the skill (second person, no "please", no Latin abbreviations,
sentence-case headings) are not checked here - they need judgement, and a regex
that approximates them costs more in false positives than it catches. Review and
the skill's own checklist cover those.
"""

import json
import os
import re
import sys

# The files `coralogix/documentation` mirrors from this repo, per its
# `external_repos.json`. Keep in step with that file: a path that drifts here
# silently stops being checked, and one that drifts there silently stops syncing.
SYNCED = [
    "README.md",
    "SessionReplay/Sources/Docs/README.md",
]

SKILL = "rum-readme-authoring"

ENTITY = re.compile(r"&(?:amp|lt|gt|quot|apos|nbsp|#\d+|#x[0-9a-fA-F]+);")
FENCE = re.compile(r"^\s{0,3}(```|~~~)")
RULE = re.compile(r"^\s{0,3}(?:-\s*-\s*-[-\s]*|\*\s*\*\s*\*[*\s]*|_\s*_\s*_[_\s]*)$")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
# ponytail: matches the plain `> **Note:**` form only. An emphasised variant
# (`> _**Note:**_`) slips through; widen if one ever ships.
CALLOUT = re.compile(r"^>\s*\*\*(note|tip|important|warning|caution)\b", re.I)
SPLIT_OPEN = re.compile(r"<!--\s*split\b(.*?)-->")
SPLIT_CLOSE = re.compile(r"<!--\s*/\s*split\s*-->")
WRITEISH = re.compile(r">>?\s|\bsed\b[^|]*\s-i|\bperl\b[^|]*\s-i|\btee\b|\bmv\b|\bcp\b|\bpatch\b|\btruncate\b")


def lint_text(text):
    """Return a list of (line_number, message)."""
    out = []
    fenced = False
    open_split = None  # (line number, path attribute)

    for n, line in enumerate(text.splitlines(), 1):
        if FENCE.match(line):
            fenced = not fenced

        # Entities are wrong everywhere, code fences included: `&amp;&amp;` reaches
        # the published page verbatim and the command it is part of does not run.
        for m in ENTITY.finditer(line):
            out.append((n, f"HTML entity `{m.group(0)}` - write the character itself"))

        for m in SPLIT_CLOSE.finditer(line):
            if open_split is None:
                out.append((n, "`<!-- /split -->` with no open `<!-- split ... -->`"))
            else:
                open_split = None

        for m in SPLIT_OPEN.finditer(line):
            attrs = m.group(1)
            if open_split is not None:
                out.append((n, f"nested split marker - the one opened on line {open_split[0]} is still open"))
            title = attrs.find("title=")
            p = attrs.find("path=")
            if title < 0 or p < 0:
                out.append((n, "split marker needs both `title=\"...\"` and `path=\"...\"`"))
            elif p < title:
                # The sync's parser reads attributes in any order, but the code that
                # strips the block out of the parent page matches `title="..." path="..."`
                # literally. Reversed, the section publishes as its own page *and* stays
                # duplicated on the README page.
                out.append((n, "split marker has `path` before `title` - reverse them, or the section is published twice"))
            pm = re.search(r'path="([^"]*)"', attrs)
            if pm and not pm.group(1).endswith(".md"):
                out.append((n, f"split `path=\"{pm.group(1)}\"` should end in `.md`"))
            open_split = (n, pm.group(1) if pm else "?")

        if fenced:
            continue

        if RULE.match(line):
            out.append((n, "decorative horizontal rule - it publishes as a stray divider; headings already separate sections"))

        if CALLOUT.match(line):
            word = CALLOUT.match(line).group(1).upper()
            out.append((n, f"bolded callout renders as a plain blockquote - use `> [!{word}]`"))

        h = HEADING.match(line)
        if h and h.group(2).endswith("."):
            out.append((n, "heading ends in a period - headings are sentence case, no trailing period, not a sentence"))

    if open_split is not None:
        out.append((open_split[0], f"split marker for `{open_split[1]}` is never closed with `<!-- /split -->`"))

    return out


def lint(root):
    failures = 0
    for rel in SYNCED:
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            print(f"{rel}: missing - the docs sync expects this path; update SYNCED here and `external_repos.json` in coralogix/documentation together")
            failures += 1
            continue
        with open(full, encoding="utf-8") as fh:
            problems = lint_text(fh.read())
        for n, msg in problems:
            print(f"{rel}:{n}: {msg}")
        failures += len(problems)
        if not problems:
            print(f"{rel}: ok")

    if failures:
        print(
            f"\n{failures} problem(s). These READMEs publish to coralogix.com/docs - see "
            f".claude/skills/{SKILL}/SKILL.md for the rules and the checks a linter cannot make."
        )
        return 1
    return 0


def hook():
    payload = json.load(sys.stdin)
    tool = payload.get("tool_name", "")
    args = payload.get("tool_input") or {}

    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        target = str(args.get("file_path", "") or args.get("notebook_path", ""))
        root = payload.get("cwd") or os.getcwd()
        try:
            rel = os.path.relpath(os.path.realpath(target), os.path.realpath(root))
        except ValueError:  # different drive on Windows
            rel = target
        # Exact, not endswith: in a repo whose synced file is the root README, an
        # endswith match would gate every other README in the tree too.
        hits = [p for p in SYNCED if rel.replace(os.sep, "/") == p]
    elif tool == "Bash":
        # ponytail: substring match, and only for commands that look like writes -
        # blocking `cat README.md` is how a hook gets deleted. `cd libs && sed -i
        # README.md`, or a write from inside a language runtime, gets past it. The
        # lint job checks the result either way.
        command = str(args.get("command", ""))
        hits = [p for p in SYNCED if p in command] if WRITEISH.search(command) else []
    else:
        return 0

    if not hits:
        return 0

    transcript = payload.get("transcript_path", "")
    if transcript and os.path.isfile(transcript):
        with open(transcript, encoding="utf-8", errors="ignore") as fh:
            body = fh.read()
        # The Skill tool call, or the user typing the slash command. Matching the
        # bare name would pass on the session's skill listing alone.
        if re.search(r'"skill"\s*:\s*"%s"' % re.escape(SKILL), body) or f"/{SKILL}" in body:
            return 0

    sys.stderr.write(
        f"Blocked: {hits[0]} is mirrored to coralogix.com/docs by the nightly docs sync, "
        f"so editing it is a documentation change, not a repo-file change.\n\n"
        f"Load the {SKILL} skill first, then make this edit again. It covers the accuracy "
        f"checks against the SDK source, the split-marker mechanics and the house style the "
        f"docs site expects - none of which is checked downstream.\n\n"
        f"`python3 .github/scripts/synced-readme.py lint` checks the mechanical rules; CI runs "
        f"the same check on the pull request.\n"
    )
    return 2


BAD = """# Title

<!-- split path="a/b.md" title="Reversed" -->
## Section one.

Run `cd /etc &amp;&amp; wget`.

---

> **Note:** bolded callouts render as plain blockquotes.

```yaml
---
this: is a code fence, not a rule
```
"""

GOOD = """# Title

<!-- split title="Fine" path="a/b.md" -->
## Section one

Run `cd /etc && wget`.

> [!NOTE]
> A real callout.
<!-- /split -->
"""


def selftest():
    """Prove the rules actually fire - a broken regex otherwise looks like a clean file."""
    problems = [m for _, m in lint_text(BAD)]
    found = " | ".join(problems)
    for expected in ("path` before `title", "period", "entity", "horizontal rule", "[!NOTE]", "never closed"):
        assert expected in found, f"rule missed {expected!r}: {found}"
    # exactly one - the `---` inside the yaml fence is not a rule
    hrs = [m for m in problems if "horizontal rule" in m]
    assert len(hrs) == 1, f"fenced `---` flagged: {found}"
    assert not lint_text(GOOD), lint_text(GOOD)
    print("selftest ok")
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "lint"
    if mode == "hook":
        sys.exit(hook())
    if mode == "selftest":
        sys.exit(selftest())
    if mode == "lint":
        sys.exit(lint(os.environ.get("GITHUB_WORKSPACE") or os.getcwd()))
    sys.exit(f"usage: {sys.argv[0]} [lint|hook|selftest]")

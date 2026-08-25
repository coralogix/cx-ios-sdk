#!/usr/bin/env python3
"""Guard the READMEs that publish to coralogix.com/docs.

A nightly job in `coralogix/documentation` mirrors the files listed in SYNCED and
publishes them as customer-facing pages, so editing one is a documentation change.
`.claude/skills/rum-readme-authoring/SKILL.md` is the authoring guide.

Three modes, one path list:

  lint      Check the synced READMEs against the mechanical rules in that skill.
            Run by CI on every pull request. Also runnable by hand.

  hook      Claude Code PreToolUse gate: refuse an edit to a synced README until the
            rum-readme-authoring skill has been loaded in this session. Reads the hook
            payload on stdin; exit 2 blocks the tool call and hands stderr back to the
            agent as an instruction.

  selftest  Assert both of the above still behave. Run by CI before `lint`, so a
            rule that has stopped firing fails the build instead of reporting clean.

The prose rules in the skill (second person, no "please", no Latin abbreviations,
sentence-case headings) are not checked here - they need judgement, and a regex
that approximates them costs more in false positives than it catches. Review and
the skill's own checklist cover those.
"""

import io
import json
import html.entities
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

EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")

# Candidates; a named one counts only if `html.entities` knows it. Matching every
# `&word;` would flag ordinary prose like `R&D; and other teams`, and a shortlist
# would miss `&mdash;` and `&copy;`, which reach the page as literally as `&amp;`.
# The semicolon is optional because HTML still decodes the legacy names without
# it - `&copy` renders as a symbol - but only when what follows is not `=` or
# another alphanumeric, which is what keeps `?a=1&copy=2` a query string.
ENTITY = re.compile(r"&(?:([A-Za-z][A-Za-z0-9]*)(;?)|(#\d+|#[xX][0-9A-Fa-f]+);)")
FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
THEMATIC = re.compile(r"^\s{0,3}(?:(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,})$")
SETEXT = re.compile(r"^\s{0,3}(=+|-+)\s*$")
# `## Heading. ##` renders as "Heading." - the closing run is syntax, so it has
# to come off before the trailing-period check.
ATX = re.compile(r"^\s{0,3}#{1,6}\s+(.*?)(?:\s+#+)?\s*$")
# The plain bolded form only. An emphasis-wrapped variant (`> _**Note:**_`) is
# deliberately not matched yet: the one instance in these repos sits in
# coralogix-browser-sdk, and rewording it is a documentation change rather than
# a tooling one. Add `[_*]{0,2}` before `\*\*` once that line is fixed.
CALLOUT = re.compile(r"^\s{0,3}>\s*\*\*(note|tip|important|warning|caution)\b", re.I)
SPLIT_OPEN = re.compile(r"<!--\s*split\b(.*?)-->")
SPLIT_CLOSE = re.compile(r"<!--\s*/\s*split\s*-->")
ATTR = re.compile(r'\b([A-Za-z_][\w-]*)\s*=\s*"([^"]*)"')

# Commands that could write to a path, as opposed to read one. Blocking `cat
# README.md` is how a hook ends up deleted, so reads are left alone. A write from
# inside a language runtime, or one that reaches the file after a `cd`, gets past
# this; the lint job checks the result either way.
WRITEISH = re.compile(
    r">>?|\btee\b|\bmv\b|\bcp\b|\brm\b|\btouch\b|\bpatch\b|\btruncate\b|\binstall\b"
    r"|\bsed\b[^|]*\s-i|\bperl\b[^|]*\s-i|\bgit\s+(?:restore|checkout|apply)\b"
    r"|\bdd\b|\bpython[0-9.]*\b[^|]*\s-c|\bnode\b[^|]*\s-e"
)

# The path as a whole argument. A bare `p in command` would match `docs/README.md`
# in a repo whose synced file is the root `README.md`.
# A nested path may legitimately be preceded by a directory prefix, as in an
# absolute path. A bare `README.md` may not, or every other README in the tree
# would be gated with it.
IN_COMMAND = {
    p: re.compile(
        r"(?<![\w.-])(?:\./)?%s(?![\w.\-/])" % re.escape(p) if "/" in p
        else r"(?<![\w.\-/])(?:\./)?%s(?![\w.\-/])" % re.escape(p)
    )
    for p in SYNCED
}

def _split_problems(n, attrs, opened):
    """Check one `<!-- split ... -->` marker. Returns (problems, path or None)."""
    out = []
    found = {name: (i, value) for i, (name, value) in enumerate(ATTR.findall(attrs))}

    if opened is not None:
        out.append((n, f"nested split marker - the one opened on line {opened[0]} is still open"))

    for name in ("title", "path"):
        if name in found:
            continue
        # `path=configuration/options.md` looks present to a substring check but
        # carries no value the sync can read.
        if re.search(r"\b%s\s*=" % name, attrs):
            out.append((n, f"split marker `{name}` has no quoted value - write `{name}=\"...\"`"))
        else:
            out.append((n, f"split marker needs `{name}=\"...\"`"))

    if "title" in found and "path" in found and found["path"][0] < found["title"][0]:
        # The sync's parser reads attributes in any order, but the code that strips
        # the block out of the parent page matches `title="..." path="..."` literally.
        # Reversed, the section publishes as its own page *and* stays duplicated on
        # the README page.
        out.append((n, "split marker has `path` before `title` - reverse them, or the section is published twice"))

    path = found["path"][1] if "path" in found else None
    if path is not None:
        if not path.endswith(".md"):
            out.append((n, f"split `path=\"{path}\"` should end in `.md`"))
        if path.startswith("/") or os.path.isabs(path):
            out.append((n, f"split `path=\"{path}\"` must be relative to the README"))
        elif ".." in path.split("/"):
            out.append((n, f"split `path=\"{path}\"` must not escape the README's directory"))

    return out, path


# A setext underline only applies to a paragraph. After a heading, list item,
# blockquote or table row, a `---` is a thematic break and has to be reported.
NOT_PARAGRAPH = re.compile(r"^\s{0,3}(?:#{1,6}\s|[-*+]\s|\d+[.)]\s|>|\||<!--|\[[^\]]*\]:)")


INDENTED_CODE = re.compile(r"^(?: {4,}|\t)")


def _is_paragraph(line):
    if not line or not line.strip():
        return False
    if INDENTED_CODE.match(line):
        return False   # an indented code block, so a following `---` is a rule
    return not NOT_PARAGRAPH.match(line) and not THEMATIC.match(line)


def lint_text(text):
    """Return a list of (line_number, message)."""
    out = []
    fence = None       # the delimiter run that opened the current code block
    opened = None      # (line number, path) of the split marker still open
    previous = None    # preceding paragraph line, for setext headings

    for n, line in enumerate(text.splitlines(), 1):
        # Entities are wrong everywhere, code fences included: `&amp;&amp;` reaches
        # the published page verbatim and the command it is part of does not run.
        for m in ENTITY.finditer(line):
            name, semicolon = m.group(1), m.group(2)
            if name:
                if semicolon:
                    if (name + ";") not in html.entities.html5:
                        continue
                else:
                    following = line[m.end():m.end() + 1]
                    if name not in html.entities.html5 or following == "=" or following.isalnum():
                        continue
            out.append((n, f"HTML entity `{m.group(0)}` - write the character itself"))

        opener = FENCE.match(line)
        if opener:
            marker = opener.group(1)
            if fence is None:
                fence = (n, marker)
            elif marker[0] == fence[1][0] and len(marker) >= len(fence[1]):
                fence = None
            previous = None
            continue

        if fence is not None:
            # Inside a code block. A README that documents how to write a split
            # marker shows one in a fence; it is an example, not a marker.
            previous = None
            continue

        for _ in SPLIT_CLOSE.finditer(line):
            if opened is None:
                out.append((n, "`<!-- /split -->` with no open `<!-- split ... -->`"))
            else:
                opened = None

        for m in SPLIT_OPEN.finditer(line):
            problems, path = _split_problems(n, m.group(1), opened)
            out.extend(problems)
            opened = (n, path or "?")

        heading = None
        if SETEXT.match(line) and _is_paragraph(previous):
            heading = previous.strip()          # `---` under text is an H2, not a rule
        elif THEMATIC.match(line):
            out.append((n, "decorative horizontal rule - it publishes as a stray divider; headings already separate sections"))
        else:
            atx = ATX.match(line)
            if atx:
                heading = atx.group(1)

        if heading and heading.endswith("."):
            out.append((n, "heading ends in a period - headings are sentence case, no trailing period, not a sentence"))

        callout = CALLOUT.match(line)
        if callout:
            out.append((n, f"bolded callout renders as a plain blockquote - use `> [!{callout.group(1).upper()}]`"))

        previous = line

    if fence is not None:
        out.append((fence[0], "code fence is never closed - everything after it is skipped by this linter"))
    if opened is not None:
        out.append((opened[0], f"split marker for `{opened[1]}` is never closed with `<!-- /split -->`"))

    return sorted(out)


def lint(root):
    failures = 0
    for rel in SYNCED:
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            print(f"{rel}: missing - the docs sync expects this path; update SYNCED here and `external_repos.json` in coralogix/documentation together")
            failures += 1
            continue
        try:
            with open(full, encoding="utf-8") as fh:
                problems = lint_text(fh.read())
        except (OSError, UnicodeDecodeError) as err:
            print(f"{rel}: unreadable - {err}")
            failures += 1
            continue
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


def _blocks(record):
    """The content blocks of one transcript record, whatever nesting it uses."""
    if not isinstance(record, dict):
        return []
    content = record.get("message", record).get("content") if isinstance(record.get("message", record), dict) else None
    return [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []


def skill_loaded(transcript):
    """Did this session actually load the skill?

    Read structurally, not as a substring sweep: the literal `"skill":
    "rum-readme-authoring"` appears in this repo's own review comments and in the
    script you are reading, so any transcript that quoted one of them would
    otherwise authorize an edit.

    The Skill tool call is the only signal accepted. Typing `/rum-readme-authoring`
    converges on the same call, so there is no second, looser path to maintain.
    """
    if not isinstance(transcript, str) or not transcript or not os.path.isfile(transcript):
        return False

    called = set()
    errored = set()

    with open(transcript, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue  # a partial write, not proof of anything

            for block in _blocks(record):
                kind = block.get("type")
                if kind == "tool_use" and block.get("name") == "Skill":
                    args = block.get("input")
                    if isinstance(args, dict) and args.get("skill") == SKILL:
                        called.add(block.get("id"))
                elif kind == "tool_result" and block.get("is_error") is True:
                    errored.add(block.get("tool_use_id"))

    # A Skill call whose result came back an error loaded nothing. An absent
    # result is not held against it - the call may simply have no recorded result
    # in this transcript shape.
    return bool(called - errored)


def targets(payload):
    """Which synced READMEs this tool call would write to."""
    tool = payload.get("tool_name")
    args = payload.get("tool_input")
    if not isinstance(args, dict):
        return []

    if tool in EDIT_TOOLS:
        target = args.get("file_path") or args.get("notebook_path")
        if not isinstance(target, str) or not target:
            return []
        root = payload.get("cwd")
        if not isinstance(root, str) or not root:
            root = os.getcwd()
        try:
            if not os.path.isabs(target):
                target = os.path.join(root, target)
            rel = os.path.relpath(os.path.realpath(target), os.path.realpath(root))
        except (OSError, ValueError):
            rel = target
        # Exact, not endswith: in a repo whose synced file is the root README, an
        # endswith match would gate every other README in the tree too.
        return [p for p in SYNCED if rel.replace(os.sep, "/") == p]

    if tool == "Bash":
        command = args.get("command")
        if not isinstance(command, str) or not WRITEISH.search(command):
            return []
        return [p for p in SYNCED if IN_COMMAND[p].search(command)]

    return []


def gate(payload):
    """Exit code for one PreToolUse payload: 0 allows the tool call, 2 blocks it."""
    if not isinstance(payload, dict):
        return 0

    try:
        hits = targets(payload)
    except Exception:
        # Nothing identified this as a synced README, so there is nothing to
        # protect, and blocking every edit in the repo would be worse.
        return 0

    if not hits:
        return 0

    # Past this point the target *is* a synced README, so anything unexpected
    # blocks rather than allows: an unreadable transcript is not proof that the
    # skill was loaded.
    try:
        if skill_loaded(payload.get("transcript_path")):
            return 0
    except Exception:
        pass

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


def hook():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        # A payload this malformed names no tool and no path, so there is no edit
        # to block. Claude Code writes it, not the agent being gated.
        return 0
    return gate(payload)


BAD = """# Title

<!-- split path="a/b.md" title="Reversed" -->
## Section one.

Run `cd /etc &amp;&amp; wget` and mind the &mdash; and &#0000065; too.

## Closing hashes still render a period. ##

## A rule after a heading is still a rule

---

A semicolonless &copy still renders as a symbol.

    indented code, not a paragraph
---

---

> **Note:** bolded callouts render as plain blockquotes.

```yaml
---
this: is a code fence, not a rule
```

<!-- split path=unquoted.md -->
"""

GOOD = """# Title

Setext heading
--------------

[A linked heading](https://coralogix.com/docs) still underlines
----------------------------------------------------------------

<!-- split title="Fine" path="a/b.md" -->
## Section one

Run `cd /etc && wget`. R&D; and AT&T; are prose, not entities, and
<https://example.com/x?a=1&copy=2&reg=3> is a query string.

> [!NOTE]
> A real callout.
<!-- /split -->

An example of the syntax, which is not a real marker:

```markdown
<!-- split title="Example" path="features/x.md" -->
## Example
<!-- /split -->
```
"""


def _payload(tmp, **kw):
    base = {"cwd": "/repo", "transcript_path": tmp}
    base.update(kw)
    return base


def selftest():
    """Prove both gates still fire - a rule that stopped matching looks like a clean file."""
    if not __debug__:
        raise SystemExit("selftest asserts; do not run it under python -O")

    problems = [m for _, m in lint_text(BAD)]
    found = " | ".join(problems)
    for expected in (
        "path` before `title", "period", "&amp;", "&mdash;", "&#0000065;", "`&copy`",
        "horizontal rule", "[!NOTE]", "never closed", "no quoted value",
    ):
        assert expected in found, f"rule missed {expected!r}: {found}"
    # Both the plain and the closed-ATX heading, not just the plain one.
    assert len([m for m in problems if "period" in m]) == 2, f"closing-hash heading missed: {found}"
    # Exactly one: the `---` inside the yaml fence is not a rule.
    hrs = [m for m in problems if "horizontal rule" in m]
    # Two: the standalone rule and the one after a heading. Not the `---` in the
    # yaml fence, and not the setext underline in GOOD.
    # Three: the standalone rule, the one after a heading, and the one after an
    # indented code line. Not the `---` in the yaml fence, and not the setext
    # underlines in GOOD.
    assert len(hrs) == 3, f"expected 3 horizontal rules, got {len(hrs)}: {found}"
    assert not lint_text(GOOD), lint_text(GOOD)

    import tempfile

    synced = SYNCED[0]
    with tempfile.TemporaryDirectory() as d:
        def transcript(name, *records):
            path = os.path.join(d, name)
            with open(path, "w") as fh:
                for record in records:
                    fh.write(json.dumps(record) + "\n")
            return path

        call = {"type": "tool_use", "id": "toolu_1", "name": "Skill", "input": {"skill": SKILL}}

        # The skill listing and the skill's own file path, but no invocation.
        bare = transcript(
            "bare.jsonl",
            {"type": "user", "message": {"content": [
                {"type": "text", "text": f"see .claude/skills/{SKILL}/SKILL.md"}]}},
        )
        loaded = transcript("loaded.jsonl", {"type": "assistant", "message": {"content": [call]}})
        # Someone quoting the matcher itself - a review comment, or this script.
        quoted = transcript(
            "quoted.jsonl",
            {"type": "user", "message": {"content": [
                {"type": "text", "text": 'the gate looks for "skill": "%s" in the transcript' % SKILL}]}},
        )
        # A Skill call that came back an error loaded nothing.
        errored = transcript(
            "errored.jsonl",
            {"type": "assistant", "message": {"content": [call]}},
            {"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "toolu_1", "is_error": True}]}},
        )
        slash = transcript(
            "slash.jsonl",
            {"type": "user", "message": {"content": [
                {"type": "text", "text": f"please run /{SKILL} for me"}]}},
        )
        truncated = transcript("truncated.jsonl", {"type": "assistant", "message": {"content": [call]}})
        with open(truncated, "a") as fh:
            fh.write('{"type":"assistant","message":{"conte\n')
        gone = os.path.join(d, "does-not-exist.jsonl")

        edit = {"tool_name": "Edit", "tool_input": {"file_path": "/repo/" + synced}}
        relative = {"tool_name": "Edit", "tool_input": {"file_path": synced}}
        other = {"tool_name": "Edit", "tool_input": {"file_path": "/repo/docs/README.md"}}
        write = {"tool_name": "Bash", "tool_input": {"command": "printf x >%s" % synced}}
        read = {"tool_name": "Bash", "tool_input": {"command": "cat %s" % synced}}

        cases = [
            (2, _payload(bare, **edit), "synced edit without the skill"),
            (2, _payload(bare, **relative), "a file_path relative to the session cwd"),
            (2, _payload(bare, tool_name="Write", tool_input={"file_path": "/repo/" + synced}), "Write"),
            (2, _payload(bare, tool_name="MultiEdit", tool_input={"file_path": "/repo/" + synced}), "MultiEdit"),
            (2, _payload(bare, tool_name="NotebookEdit", tool_input={"notebook_path": "/repo/" + synced}), "NotebookEdit"),
            (0, _payload(bare, tool_name="Read", tool_input={"file_path": "/repo/" + synced}), "a tool that only reads"),
            (2, _payload(bare, tool_name="Bash", tool_input={"command": "git restore " + synced}), "git restore"),
            (0, _payload(bare, tool_name="Bash", tool_input={"command": "rm docs/" + os.path.basename(synced)}), "a different README of the same name"),
            (2, _payload(bare, tool_name="Bash", tool_input={"command": "python3 -c \"open('%s','w')\"" % synced}), "a write from inside an interpreter"),
            (0, _payload(loaded, **edit), "synced edit with the skill loaded"),
            (0, _payload(bare, **other), "a README the sync does not mirror"),
            (2, _payload(bare, **write), "shell write without the skill"),
            (0, _payload(bare, **read), "shell read"),
            (2, _payload(slash, **edit), "asking for the skill without the call landing"),
            (2, _payload(quoted, **edit), "the matcher quoted in ordinary text"),
            (2, _payload(errored, **edit), "a Skill call that came back an error"),
            (0, _payload(truncated, **edit), "a half-written trailing line"),
            (2, _payload(gone, **edit), "unreadable transcript fails closed"),
            (2, _payload(None, **edit), "missing transcript fails closed"),
            (0, None, "a payload that is not an object"),
            (0, {"tool_name": "Edit", "tool_input": None}, "tool_input of the wrong type"),
            (0, {"tool_name": "Edit", "tool_input": {"file_path": ["/repo/" + synced]}}, "file_path of the wrong type"),
            (0, {}, "an empty payload"),
        ]
        if "/" in synced:
            # A nested path can carry a directory prefix; a bare README.md cannot.
            cases.append((2, _payload(bare, tool_name="Bash",
                                      tool_input={"command": "sed -i '' s/a/b/ /repo/" + synced}),
                          "an absolute path to a nested synced file"))

        for expected, payload, why in cases:
            captured, sys.stderr = sys.stderr, io.StringIO()
            try:
                got = gate(payload)
            finally:
                sys.stderr = captured
            assert got == expected, f"gate returned {got}, expected {expected}: {why}"

        # The two entry points CI and the hook actually call, not just their internals.
        root = os.path.join(d, "repo")
        pages = [os.path.join(root, rel) for rel in SYNCED]   # every one: lint checks them all
        for page in pages:
            os.makedirs(os.path.dirname(page), exist_ok=True)
            with open(page, "w") as fh:
                fh.write(GOOD)
        captured, sys.stdout = sys.stdout, io.StringIO()
        try:
            clean = lint(root)
            with open(pages[0], "w") as fh:
                fh.write(BAD)
            dirty = lint(root)
        finally:
            sys.stdout = captured
        assert clean == 0, "lint() failed a clean README"
        assert dirty == 1, "lint() passed a README full of violations"

        stdin, sys.stdin = sys.stdin, io.StringIO(json.dumps(_payload(bare, **edit)))
        captured, sys.stderr = sys.stderr, io.StringIO()
        try:
            blocked = hook()
        finally:
            sys.stdin, sys.stderr = stdin, captured
        assert blocked == 2, "hook() did not block a synced edit"

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

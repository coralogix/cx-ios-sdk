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
import posixpath
import re
import string
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

# CommonMark's limits, named so the regexes below and the checks that compare
# against them cannot drift apart: up to three spaces of indentation still
# belongs to the current block, a fourth starts an indented code block; headings
# go to six levels; an ordered list marker takes up to nine digits.
MAX_BLOCK_INDENT = 3
MAX_HEADING_LEVEL = 6
MAX_LIST_NUMBER_DIGITS = 9

# Exit statuses. These are two external contracts, not ours to choose: 0 and
# non-zero decide whether the CI job passes, and 2 is the one PreToolUse status
# that refuses a tool call - Claude Code treats every other non-zero value as a
# non-blocking error and lets the edit through.
EXIT_OK = 0
EXIT_VIOLATIONS = 1
EXIT_REFUSE = 2

# Candidates; a named one counts only if `html.entities` knows it. Matching every
# `&word;` would flag ordinary prose like `R&D; and other teams`, and a shortlist
# would miss `&mdash;` and `&copy;`, which reach the page as literally as `&amp;`.
# The semicolon is optional because HTML still decodes the legacy names without
# it - `&copy` renders as a symbol - but only when what follows is not `=` or
# another alphanumeric, which is what keeps `?a=1&copy=2` a query string.
ENTITY = re.compile(r"&(?:([A-Za-z][A-Za-z0-9]*)|#\d+|#[xX][0-9A-Fa-f]+)(;?)")
# A fence may be indented up to three spaces past the column its container
# starts at - so a fence inside a list item carries the list's continuation
# indent, while a four-space run at the root is an indented code block and not a
# fence at all. `_container_indent()` computes that column.
FENCE = re.compile(r"^( *)(`{3,}|~{3,})(.*)$")
LIST_ITEM = re.compile(r"^ *(?:[-*+]|\d{1,%d}[.)]) +" % MAX_LIST_NUMBER_DIGITS)


def _containers(line, open_columns):
    """The stack of content columns for the list items this line sits inside.

    A list item opens one at the end of its marker and padding - `10. ` starts at
    four, not at one. Leaving a nested item returns to the outer one rather than
    to the margin, which is why this is a stack and not a single column.
    """
    if not line.strip():
        return open_columns
    indent = len(line) - len(line.lstrip(" "))
    if indent > MAX_BLOCK_INDENT and not open_columns:
        return open_columns   # indented code at the root opens no container
    columns = [c for c in open_columns if c <= indent]
    item = LIST_ITEM.match(line)
    if item:
        columns.append(item.end())
    return columns
THEMATIC = re.compile(r"^ {0,%d}(?:(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,})$" % MAX_BLOCK_INDENT)
SETEXT = re.compile(r"^ {0,%d}(=+|-+)\s*$" % MAX_BLOCK_INDENT)
# `## Heading. ##` renders as "Heading." - the closing run is syntax, so it has
# to come off before the trailing-period check.
ATX = re.compile(r"^ {0,%d}#{1,%d}\s+(.*?)(?:\s+#+)?\s*$" % (MAX_BLOCK_INDENT, MAX_HEADING_LEVEL))
# Any bolded label, however it is emphasised and at whatever quote depth:
# `> **Note:**`, `> _**Note:**_`, `> **_Note:_**`, `> > __Warning:__`. All of
# them render as a plain blockquote rather than as the alert the docs site
# styles. Applied to the line with its quote prefix removed, so the depth does
# not matter, but only when there was a prefix - a bolded label in ordinary
# prose is not a callout.
CALLOUT = re.compile(r"^[_*]{0,2}(?:\*\*|__)[_*]{0,2}(note|tip|important|warning|caution)\b", re.I)
# A fence can sit inside a blockquote. The prefix comes off for fence tracking
# only - the callout rule is *about* blockquotes, so it keeps the original line.
QUOTE_PREFIX = re.compile(r"^(?: {0,%d}>\s?)+" % MAX_BLOCK_INDENT)

# One pattern for both, so markers are handled in the order they appear rather
# than every close before every open - a section opened and closed on one line is
# valid and was being reported as a close without an open.
SPLIT_MARKER = re.compile(r"<!--\s*(/)?\s*split\b(.*?)-->")
ATTR = re.compile(r'\b([A-Za-z_][\w-]*)\s*=\s*"([^"]*)"')
# A code span closes on a backtick run of the same length as the one that opened
# it, so `` `a` `` keeps its inner backticks rather than ending early.
CODE_SPAN = re.compile(r"(`+)(?:(?!\1)[\s\S])*?\1")

# Commands that could write to a path, as opposed to read one. Blocking `cat
# README.md` is how a hook ends up deleted, so reads are left alone. A write from
# inside a language runtime, or one that reaches the file after a `cd`, gets past
# this; the lint job checks the result either way.
WRITEISH = re.compile(
    r">>?|\btee\b|\bmv\b|\bcp\b|\brm\b|\btouch\b|\bpatch\b|\btruncate\b|\binstall\b"
    r"|\bsed\b[^|]*\s-\w*i\b|\bperl\b[^|]*\s-\w*i\b"
    r"|\bsed\b[^|]*\s--in-place|\bperl\b[^|]*\s--in-place"
    r"|\bgit\s+(?:restore|checkout|apply)\b|\bapply_patch\b"
    r"|\bdd\b|\bln\b|\bpython[0-9.]*\b[^|]*\s-c|\bnode\b[^|]*\s-e"
)

# Path-shaped operands of a shell command, so one naming the synced file under
# another name - a hardlink, a copy of the path - can be checked against the
# filesystem the way the edit branch does.
OPERAND = re.compile(r"[A-Za-z0-9_.~/-]{2,}")
MAX_OPERANDS = 40

# The path as a whole argument. A bare `p in command` would match `docs/README.md`
# in a repo whose synced file is the root `README.md`.
def _argument(path, before):
    return re.compile(before + r"(?:\./)?" + re.escape(path) + r"(?![\w.\-/])")


def _argument_anywhere(path):
    """Matches the path even with a directory in front of it.

    A nested synced path may legitimately carry one, as an absolute path does.
    """
    return _argument(path, r"(?<![\w.-])")


def _argument_at_root(path):
    """Matches the path only as written, with nothing in front of it.

    A bare `README.md` may not carry a prefix, or every other README in the tree
    would be gated along with it.
    """
    return _argument(path, r"(?<![\w.\-/])")


IN_COMMAND = {p: (_argument_anywhere(p) if "/" in p else _argument_at_root(p)) for p in SYNCED}
IN_COMMAND_ANY_CASE = {
    p: re.compile(IN_COMMAND[p].pattern, re.I) for p in SYNCED
}

# Asking the filesystem whether two paths are one file settles case-insensitive
# checkouts, symlinks and hardlinks in a single check, without a table of
# spellings to keep in step.
def _same_file(a, b):
    try:
        return os.path.samefile(a, b)
    except OSError:
        return False

def _split_problems(n, attrs, opened):
    """Check one `<!-- split ... -->` marker. Returns (problems, path or None)."""
    out = []
    pairs = ATTR.findall(attrs)
    found = {name: (i, value) for i, (name, value) in enumerate(pairs)}
    names = [name for name, _ in pairs]
    for name in sorted(set(names)):
        if names.count(name) > 1:
            out.append((n, f"split marker repeats `{name}` - the sync reads only one of them"))

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
NOT_PARAGRAPH = re.compile(r"^ {0,%d}(?:#{1,%d}\s|[-*+]\s|\d+[.)]\s|>|\||<!--|\[[^\]]*\]:)"
                           % (MAX_BLOCK_INDENT, MAX_HEADING_LEVEL))


# What HTML5 refuses to decode a semicolonless name in front of. Ascii only:
# `&copyé` does decode, so `str.isalnum()` would have let it through.
ASCII_AFTER = frozenset("=" + string.ascii_letters + string.digits)

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
    published = set()  # paths already claimed, so a duplicate is caught
    previous = None    # (line, depth, container) of the preceding line
    open_columns = []  # content columns of the list items currently open
    container = 0      # the innermost of them

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
                    if name not in html.entities.html5 or following in ASCII_AFTER:
                        continue
            out.append((n, f"HTML entity `{m.group(0)}` - write the character itself"))

        dequoted = QUOTE_PREFIX.sub("", line)
        depth = line[:len(line) - len(dequoted)].count(">")
        if fence is not None and fence[2] > 0 and depth < fence[2]:
            # A fence inside a blockquote ends when the blockquote does, so the
            # line that leaves the quote is ordinary content again.
            fence = None

        opener = FENCE.match(dequoted)
        if opener and len(opener.group(1)) > container + MAX_BLOCK_INDENT:
            # Indented past what its container allows, so this is code, not a
            # fence: four spaces at the root is an indented code block.
            opener = None
        if opener and opener.group(2)[0] == "`" and "`" in opener.group(3):
            # A backtick fence's info string may not contain a backtick.
            opener = None
        if opener:
            marker, trailing = opener.group(2), opener.group(3)
            if fence is None:
                fence = (n, marker, depth)
            elif (marker[0] == fence[1][0] and len(marker) >= len(fence[1])
                  and not trailing.strip() and depth == fence[2]):
                # A closing fence takes no info string, so ```not-a-closer inside
                # a block is content rather than the end of it. It also has to be
                # at the quote depth that opened the block, or an unquoted ``` in
                # the prose below would close a fence opened inside a blockquote.
                fence = None
            previous = None
            continue

        if fence is not None:
            # Inside a code block. A README that documents how to write a split
            # marker shows one in a fence; it is an example, not a marker.
            previous = None
            continue

        open_columns = _containers(dequoted, open_columns)
        container = open_columns[-1] if open_columns else 0
        # Rules apply relative to the container: a divider nested two lists deep is
        # still a divider, and indentation past the container is code. On the list
        # item's own line the marker comes off too, so `- ## Heading` is a heading.
        item = LIST_ITEM.match(dequoted)
        if item:
            body = dequoted[item.end():]
        elif not dequoted[:container].strip():
            body = dequoted[container:]
        else:
            body = dequoted
        # A blockquote can open inside a list item, so the depth has to be taken
        # again once the marker is off: `- > **Note:**` is a callout.
        inner = QUOTE_PREFIX.sub("", body)
        depth += body[:len(body) - len(inner)].count(">")
        body = inner
        relative_indent = len(body) - len(body.lstrip(" "))

        # A marker shown inside a code span, or inside an indented code block, is
        # an example of the syntax rather than a section transition.
        scannable = "" if relative_indent > MAX_BLOCK_INDENT else CODE_SPAN.sub(" ", body)
        for m in SPLIT_MARKER.finditer(scannable):
            if m.group(1):
                if opened is None:
                    out.append((n, "`<!-- /split -->` with no open `<!-- split ... -->`"))
                else:
                    opened = None
                continue
            problems, path = _split_problems(n, m.group(2), opened)
            out.extend(problems)
            if path:
                path = posixpath.normpath(path)
                if path in published:
                    out.append((n, f"split `path=\"{path}\"` is already used - two sections cannot publish to one page"))
                published.add(path)
            opened = (n, path or "?")

        heading = None
        if SETEXT.match(body) and previous and previous[1:] == (depth, container) \
                and _is_paragraph(previous[0]):
            heading = previous[0].strip()       # `---` under text is an H2, not a rule
        elif THEMATIC.match(body):
            out.append((n, "decorative horizontal rule - it publishes as a stray divider; headings already separate sections"))
        else:
            atx = ATX.match(body)
            if atx:
                heading = atx.group(1)

        if heading and heading.endswith("."):
            out.append((n, "heading ends in a period - headings are sentence case, no trailing period, not a sentence"))

        callout = CALLOUT.match(body.lstrip()) if depth else None
        if callout:
            out.append((n, f"bolded callout renders as a plain blockquote - use `> [!{callout.group(1).upper()}]`"))

        previous = (body, depth, container)

    if fence is not None:
        out.append((fence[0], "code fence is never closed - everything after it is skipped by this linter"))
    if opened is not None:
        out.append((opened[0], f"split marker for `{opened[1]}` is never closed with `<!-- /split -->`"))

    return sorted(out)


def lint(root):
    failures = 0
    inside = os.path.realpath(root) + os.sep
    for rel in SYNCED:
        full = os.path.join(root, rel)
        if not os.path.realpath(full).startswith(inside):
            # A symlink pointing out of the checkout would have this job reading
            # and reporting on a file that is not part of the repository.
            print(f"{rel}: resolves outside the repository - refusing to read it")
            failures += 1
            continue
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
        return EXIT_VIOLATIONS
    return EXIT_OK


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
    error_by_tool_use_id = {}

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
                    call_id = block.get("id")
                    if isinstance(args, dict) and args.get("skill") == SKILL and isinstance(call_id, str) and call_id:
                        called.add(call_id)
                elif kind == "tool_result":
                    result_id = block.get("tool_use_id")
                    if isinstance(result_id, str) and result_id:
                        error_by_tool_use_id[result_id] = block.get("is_error")

    # The call has to have come back, and not as an error. A later tool call can
    # only happen after the Skill result reached the model, so by the time this
    # hook runs a genuine invocation always has its result recorded.
    # A call counts only if its result came back and does not report failure:
    # `is_error` false, or absent from a result that is present. No result at all,
    # `is_error` true, or any value this does not recognise, all fail closed.
    return any(
        call_id in error_by_tool_use_id and error_by_tool_use_id[call_id] in (None, False)
        and isinstance(error_by_tool_use_id[call_id], (bool, type(None)))
        for call_id in called
    )


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
        if not os.path.isabs(target):
            target = os.path.join(root, target)
        candidates = set()
        try:
            # Where it resolves to, so a symlink *at* the synced path is caught,
            # and the path as written, so a symlink *of* it still is.
            candidates.add(os.path.relpath(os.path.realpath(target), os.path.realpath(root)))
            candidates.add(os.path.relpath(os.path.normpath(target), os.path.normpath(root)))
        except (OSError, ValueError):
            candidates.add(target)
        candidates = {c.replace(os.sep, "/") for c in candidates}
        # Exact, not endswith: in a repo whose synced file is the root README, an
        # endswith match would gate every other README in the tree too.
        hits = [p for p in SYNCED if p in candidates]
        if hits:
            return hits
        # Nothing matched by name. It may still *be* one of them under another
        # spelling, another case, or a link, which only the filesystem knows.
        return [p for p in SYNCED if _same_file(target, os.path.join(root, p))]

    if tool == "Bash":
        command = args.get("command")
        if not isinstance(command, str) or not WRITEISH.search(command):
            return []
        command = command.replace("\\", "/")   # a Windows-style path names the same file
        root = payload.get("cwd")
        if not isinstance(root, str):
            root = ""
        hits = []
        for p in SYNCED:
            if IN_COMMAND[p].search(command):
                hits.append(p)
                continue
            if not root:
                continue
            # An absolute path is unambiguous once the session cwd is known, so
            # `/repo/README.md` matches where a bare prefix could not.
            if _argument_at_root(os.path.join(root, p)).search(command):
                hits.append(p)
                continue
            # A different spelling of the same file - `readme.md` on a folding
            # checkout - counts only if the filesystem says it is that file. On a
            # case-sensitive one it is a different file and is left alone.
            spelled = IN_COMMAND_ANY_CASE[p].search(command)
            if spelled:
                named = spelled.group(0)
                named = named if os.path.isabs(named) else os.path.join(root, named)
                if _same_file(named, os.path.join(root, p)):
                    hits.append(p)

        if root and len(hits) < len(SYNCED):
            # Nothing matched by name. An operand may still *be* one of the synced
            # files under another name, which only the filesystem can say.
            for token in OPERAND.findall(command)[:MAX_OPERANDS]:
                candidate = token if os.path.isabs(token) else os.path.join(root, token)
                for p in SYNCED:
                    if p not in hits and _same_file(candidate, os.path.join(root, p)):
                        hits.append(p)
        return hits

    return []


def gate(payload):
    """Exit code for one PreToolUse payload: 0 allows the tool call, 2 blocks it."""
    if not isinstance(payload, dict):
        return EXIT_OK

    try:
        hits = targets(payload)
    except Exception as err:
        # The analysis fell over, which is not the same as "this is not a synced
        # README" - but it names no path either, so blocking would take every edit
        # in the repository with it. Allow, and say so rather than failing silently.
        # The type only: an exception's repr can carry local paths and payload
        # fragments, and this text goes straight into the agent's context.
        sys.stderr.write(
            f"synced-readme hook could not identify this tool call's target "
            f"({type(err).__name__}); allowing it. If it touches a synced README, "
            f"load the {SKILL} skill first.\n"
        )
        return EXIT_OK

    if not hits:
        return EXIT_OK

    # Past this point the target *is* a synced README, so anything unexpected
    # blocks rather than allows: an unreadable transcript is not proof that the
    # skill was loaded.
    unreadable = ""
    try:
        if skill_loaded(payload.get("transcript_path")):
            return EXIT_OK
    except Exception as err:
        # Blocking either way, but an analysis that fell over is a different
        # situation from a session that simply never loaded the skill, and the
        # agent cannot act on the second message if it is really the first.
        unreadable = (
            f"\nThe session transcript could not be read ({type(err).__name__}), so whether "
            f"the skill was loaded could not be determined. This edit is refused either way.\n"
        )

    sys.stderr.write(
        f"Blocked: {hits[0]} is mirrored to coralogix.com/docs by the nightly docs sync, "
        f"so editing it is a documentation change, not a repo-file change.\n\n"
        f"Load the {SKILL} skill first, then make this edit again. It covers the accuracy "
        f"checks against the SDK source, the split-marker mechanics and the house style the "
        f"docs site expects - none of which is checked downstream.\n\n"
        f"`python3 .github/scripts/synced-readme.py lint` checks the mechanical rules; CI runs "
        f"the same check on the pull request.\n"
        + unreadable
    )
    return EXIT_REFUSE


def hook():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        # A payload this malformed names no tool and no path, so there is no edit
        # to block. Claude Code writes it, not the agent being gated.
        return EXIT_OK
    return gate(payload)


BAD = """# Title

<!-- split path="a/b.md" title="Reversed" -->
## Section one.

Run `cd /etc &amp;&amp; wget` and mind the &mdash; and &#0000065; too.

## Closing hashes still render a period. ##

## A rule after a heading is still a rule

---

A semicolonless &copy still renders as a symbol, as do &#65 and &copyé.

    indented code, not a paragraph
---

---

> **Note:** bolded callouts render as plain blockquotes.

> _**Warning:**_ so do the emphasis-wrapped ones.

```yaml
---
this: is a code fence, not a rule
```not-a-closing-fence
---
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

def _payload(transcript, **kw):
    payload = {"cwd": "/repo", "transcript_path": transcript}
    payload.update(kw)
    return payload


def _transcripts(directory):
    """The transcript shapes the gate has to tell apart."""
    call = {"type": "tool_use", "id": "toolu_1", "name": "Skill", "input": {"skill": SKILL}}

    def write(name, *records):
        path = os.path.join(directory, name)
        with open(path, "w") as fh:
            for record in records:
                fh.write(json.dumps(record) + "\n")
        return path

    def said(text):
        return {"type": "user", "message": {"content": [{"type": "text", "text": text}]}}

    shapes = {
        # The skill listing and the skill's own file path, but no invocation.
        "bare": write("bare.jsonl", said(f"see .claude/skills/{SKILL}/SKILL.md")),
        "loaded": write(
            "loaded.jsonl",
            {"type": "assistant", "message": {"content": [call]}},
            {"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "toolu_1"}]}},
        ),
        # Recorded but never came back, so nothing was loaded from it.
        "pending": write("pending.jsonl", {"type": "assistant", "message": {"content": [call]}}),
        # Someone quoting the matcher itself - a review comment, or this script.
        "quoted": write("quoted.jsonl", said('the gate looks for "skill": "%s"' % SKILL)),
        "asked": write("asked.jsonl", said(f"please run /{SKILL} for me")),
        # A Skill call that came back an error loaded nothing.
        "errored": write(
            "errored.jsonl",
            {"type": "assistant", "message": {"content": [call]}},
            {"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "toolu_1", "is_error": True}]}},
        ),
        "truncated": write(
            "truncated.jsonl",
            {"type": "assistant", "message": {"content": [call]}},
            {"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "toolu_1"}]}},
        ),
        "gone": os.path.join(directory, "does-not-exist.jsonl"),
    }
    with open(shapes["truncated"], "a") as fh:
        fh.write('{"type":"assistant","message":{"conte\n')
    return shapes


def _check_rules():
    """Every rule still fires, and none of them fires on clean content."""
    problems = [m for _, m in lint_text(BAD)]
    found = " | ".join(problems)
    for expected in (
        "path` before `title", "period", "&amp;", "&mdash;", "&#0000065;", "&#65", "`&copy`",
        "horizontal rule", "[!NOTE]", "[!WARNING]", "never closed", "no quoted value",
    ):
        assert expected in found, f"rule missed {expected!r}: {found}"
    # Three: the standalone rule, the one after a heading, and the one after an
    # indented code line. Neither `---` inside the yaml fence counts - the second
    # one sits after a ```-with-a-suffix, which does not close the block - and
    # the setext underlines in GOOD do not either.
    hrs = [m for m in problems if "horizontal rule" in m]
    assert len(hrs) == 3, f"expected 3 horizontal rules, got {len(hrs)}: {found}"
    # Both the plain and the closed-ATX heading, not just the plain one.
    assert len([m for m in problems if "period" in m]) == 2, f"closing-hash heading missed: {found}"
    assert not lint_text(GOOD), lint_text(GOOD)

    # The containment rules, each on its own line, so removing either branch
    # fails here rather than hiding behind the other diagnostics in BAD.
    for marker, expected in (
        ('<!-- split title="a" path="/absolute.md" -->', "must be relative"),
        ('<!-- split title="a" path="../escape.md" -->', "must not escape"),
        ('<!-- split title="a" path="fine.txt" -->', "should end in `.md`"),
    ):
        reported = " | ".join(m for _, m in lint_text(marker))
        assert expected in reported, f"{marker} -> {reported}"

    # A fenced block inside a blockquote is quoted code, not prose to grade. An
    # entity is still reported in there - the skill bans those inside fences too -
    # so the case to check is a rule that only applies to prose.
    quoted = lint_text('> ```markdown\n> **Note:** an example callout\n> ```\n')
    assert not quoted, f"blockquoted fence linted as prose: {quoted}"
    unquoted = lint_text('> **Note:** a real callout\n')
    assert unquoted, "the callout rule stopped firing outside a fence"
    for spelling in ("> _**Tip:**_ x", "> __Important:__ x", "> *__Caution:__* x"):
        assert lint_text(spelling + "\n"), f"callout spelling missed: {spelling}"
    # A real alert, and a blockquote with a label that has no alert equivalent,
    # both have to stay clean.
    assert not lint_text("> [!NOTE]\n> body\n"), "a real alert was reported"
    assert not lint_text("> **Limitation:** this one has no alert form\n"), "a custom label was reported"
    for prefix, delimiter in (("> ", "~~~"), ("> > ", "```")):
        block = f"{prefix}{delimiter}markdown\n{prefix}**Note:** an example\n{prefix}{delimiter}\n"
        quoted = lint_text(block)
        assert not quoted, f"{prefix}{delimiter} linted as prose: {quoted}"
    # Two sections cannot publish to one page, and an open and its close may share
    # a line.
    duplicate = lint_text(
        '<!-- split title="a" path="features/x.md" -->\n## A\n<!-- /split -->\n'
        '<!-- split title="b" path="features/x.md" -->\n## B\n<!-- /split -->\n'
    )
    assert any("already used" in m for _, m in duplicate), f"duplicate path not reported: {duplicate}"
    inline = lint_text('<!-- split title="a" path="features/x.md" --> body <!-- /split -->\n')
    assert not inline, f"an open and close on one line reported: {inline}"

    # A fence indented under a list item is still a fence.
    listed = lint_text('- item\n\n  ```markdown\n  **Note:** an example\n  ```\n')
    assert not listed, f"list-nested fence linted as prose: {listed}"

    # Four spaces at the root is an indented code block, not a fence, so it must
    # not swallow the rest of the file.
    indented = lint_text('    ```\n\n> **Note:** still reported\n')
    assert len(indented) == 1 and "[!NOTE]" in indented[0][1], f"indented run opened a fence: {indented}"

    # A backtick fence's info string may not contain a backtick.
    infostring = lint_text('```js `x`\n> **Note:** still reported\n```\n')
    assert any("[!NOTE]" in m for _, m in infostring), f"backtick info string opened a fence: {infostring}"

    # Every emphasis arrangement, at any quote depth.
    for spelling in ("> **_Note:_** x", "> __*Warning:*__ x", "> > **Warning:** x", "> > _**Tip:**_ x"):
        assert lint_text(spelling + "\n"), f"callout spelling missed: {spelling}"
    assert not lint_text("**Note:** not a blockquote, so not a callout\n"), "flagged a bolded label in prose"

    # Rules have to see through the quote and the list prefix.
    quoted_rule = lint_text("> text\n>\n> ---\n")
    assert any("horizontal rule" in m for _, m in quoted_rule), f"quoted rule missed: {quoted_rule}"
    quoted_heading = lint_text("> A quoted heading.\n> ---\n")
    assert any("period" in m for _, m in quoted_heading), f"quoted setext heading missed: {quoted_heading}"
    assert lint_text(">    **Note:** spaced away from the marker\n"), "spacing after `>` hid a callout"

    # The limits the regexes are built from, at their boundaries.
    assert lint_text("#" * MAX_HEADING_LEVEL + " Heading.\n"), "deepest heading level missed"
    assert not lint_text("#" * (MAX_HEADING_LEVEL + 1) + " Not a heading.\n"), "over-deep heading treated as one"
    assert not lint_text(" " * (MAX_BLOCK_INDENT + 1) + "---\n"), "indented code reported as a rule"
    assert lint_text(" " * MAX_BLOCK_INDENT + "---\n"), "an indented-but-valid rule was missed"
    wide = "9" * MAX_LIST_NUMBER_DIGITS
    assert not lint_text(f"{wide}. item\n\n" + " " * (len(wide) + 2) + "```md\n**Note:** x\n```\n"), \
        "a fence under the widest list marker was misread"

    # A blockquote opened inside a list item is still a blockquote.
    assert lint_text("- > **Note:** text\n"), "list-nested callout missed"

    # A `---` that has left its container is a rule, not a setext underline.
    for text in ("> quoted paragraph\n---\n", "- item\n---\n"):
        left = lint_text(text)
        assert any("horizontal rule" in m for _, m in left), f"container exit misread as setext: {text!r} -> {left}"

    # Leaving a nested list returns to the outer item, not to the margin.
    nested = lint_text("- a\n\n  - b\n\n  ---\n")
    assert any("horizontal rule" in m for _, m in nested), f"outer container lost: {nested}"

    # A heading or a rule on the list item's own line is still one.
    assert any("period" in m for _, m in lint_text("- ## Inline heading.\n")), "list-marker heading missed"

    # A code span keeps inner backticks, so the marker inside it stays an example.
    spanned = lint_text('Use `` `<!-- split title="x" path="y.md" -->` `` inline.\n')
    assert not spanned, f"code span closed early: {spanned}"

    # A marker's own width counts toward the container column.
    assert not lint_text("10. item\n\n    ```markdown\n    **Note:** x\n    ```\n"), \
        "an ordered-list fence was read as indented code"

    # Two spellings of one destination are still one destination.
    dotted = lint_text(
        '<!-- split title="a" path="features/x.md" -->\n## A\n<!-- /split -->\n'
        '<!-- split title="b" path="features/./x.md" -->\n## B\n<!-- /split -->\n'
    )
    assert any("already used" in m for _, m in dotted), f"dot-segment duplicate missed: {dotted}"

    # A quoted fence suppresses the example inside it, ends with the blockquote,
    # and leaves the callout after it reportable.
    boundary = lint_text('> ```markdown\n> **Note:** an example\n\n> **Note:** a real one\n')
    assert len(boundary) == 1 and "[!NOTE]" in boundary[0][1], f"quote/fence boundary: {boundary}"
    assert boundary[0][0] == 4, f"reported the wrong line: {boundary}"


def _check_gate(shapes):
    """Every registered tool, every synced path, and payloads that are not payloads."""
    cases = [
        (EXIT_OK, None, "a payload that is not an object"),
        (EXIT_OK, {}, "an empty payload"),
        (EXIT_OK, {"tool_name": "Edit", "tool_input": None}, "tool_input of the wrong type"),
    ]

    for synced in SYNCED:
        absolute = {"file_path": "/repo/" + synced}
        cases += [
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Edit", tool_input=absolute), f"{synced}: edit without the skill"),
            (EXIT_OK, _payload(shapes["loaded"], tool_name="Edit", tool_input=absolute), f"{synced}: edit with the skill loaded"),
            (EXIT_REFUSE, _payload(shapes["quoted"], tool_name="Edit", tool_input=absolute), f"{synced}: the matcher quoted in ordinary text"),
            (EXIT_REFUSE, _payload(shapes["asked"], tool_name="Edit", tool_input=absolute), f"{synced}: asking for the skill, no call"),
            (EXIT_REFUSE, _payload(shapes["errored"], tool_name="Edit", tool_input=absolute), f"{synced}: a Skill call that errored"),
            (EXIT_REFUSE, _payload(shapes["pending"], tool_name="Edit", tool_input=absolute), f"{synced}: a Skill call with no result"),
            (EXIT_OK, _payload(shapes["truncated"], tool_name="Edit", tool_input=absolute), f"{synced}: a half-written trailing line"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "sed --in-place s/a/b/ " + synced}), f"{synced}: sed --in-place"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "sed -i '' s/a/b/ /repo/" + synced}), f"{synced}: an absolute path"),
            (EXIT_OK, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "sed -i '' s/a/b/ /repo/docs/" + os.path.basename(synced)}), f"{synced}: an absolute path to a different README"),
            (EXIT_REFUSE, _payload(shapes["gone"], tool_name="Edit", tool_input=absolute), f"{synced}: unreadable transcript fails closed"),
            (EXIT_REFUSE, _payload(None, tool_name="Edit", tool_input=absolute), f"{synced}: missing transcript fails closed"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Edit", tool_input={"file_path": synced}), f"{synced}: relative to the session cwd"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Write", tool_input=absolute), f"{synced}: Write"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="MultiEdit", tool_input=absolute), f"{synced}: MultiEdit"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="NotebookEdit", tool_input={"notebook_path": "/repo/" + synced}), f"{synced}: NotebookEdit"),
            (EXIT_OK, _payload(shapes["bare"], tool_name="Read", tool_input=absolute), f"{synced}: a tool that only reads"),
            (EXIT_OK, _payload(shapes["bare"], tool_name="Edit", tool_input={"file_path": ["/repo/" + synced]}), f"{synced}: file_path of the wrong type"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "printf x >%s" % synced}), f"{synced}: shell write"),
            (EXIT_OK, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "cat %s" % synced}), f"{synced}: shell read"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "git restore " + synced}), f"{synced}: git restore"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "ln -sf replacement " + synced}), f"{synced}: ln over the synced file"),
            (EXIT_REFUSE, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "python3 -c \"open('%s','w')\"" % synced}), f"{synced}: interpreter write"),
            (EXIT_OK, _payload(shapes["bare"], tool_name="Bash", tool_input={"command": "rm docs/" + os.path.basename(synced)}), f"{synced}: a different README of the same name"),
        ]
    # The documented limit, asserted so a regex change cannot alter it unnoticed:
    # a write that reaches the file after a `cd` is not seen. CI lints the result.
    directory = os.path.dirname(SYNCED[0])
    if directory:
        cases.append((EXIT_OK, _payload(shapes["bare"], tool_name="Bash", tool_input={
            "command": f"cd {directory} && sed -i '' s/a/b/ {os.path.basename(SYNCED[0])}"}),
            "a write reached through cd - a known limit, not an intended allow"))

    for expected, payload, why in cases:
        captured, sys.stderr = sys.stderr, io.StringIO()
        try:
            got = gate(payload)
        finally:
            sys.stderr = captured
        assert got == expected, f"gate returned {got}, expected {expected}: {why}"


def _check_entry_points(directory, transcript):
    """`lint` and `hook` themselves, not only the functions underneath them."""
    root = os.path.join(directory, "repo")
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
    assert clean == EXIT_OK, "lint() failed a clean README"
    assert dirty == EXIT_VIOLATIONS, "lint() passed a README full of violations"

    # Case folding is only correct where the filesystem folds too. On macOS the
    # lowercase spelling opens the synced file and has to be gated; on a
    # case-sensitive filesystem it is a different file and must not be.
    variant = os.path.join(root, os.path.dirname(SYNCED[0]), os.path.basename(SYNCED[0]).lower())
    folds = os.path.exists(variant) and _same_file(variant, pages[0])
    err, sys.stderr = sys.stderr, io.StringIO()
    try:
        got = gate(_payload(transcript, cwd=root, tool_name="Edit", tool_input={"file_path": variant}))
    finally:
        sys.stderr = err
    expected = EXIT_REFUSE if folds else EXIT_OK
    assert got == expected, f"case-variant path returned {got}, expected {expected} (filesystem folds: {folds})"

    # A hardlink is the synced file under another name, and only the filesystem
    # knows it. A shell command naming a case variant needs the same proof.
    alias = os.path.join(root, "README-alias.md")
    try:
        os.link(pages[0], alias)
    except OSError:
        alias = None
    if alias:
        for tool, args in (
            ("Edit", {"file_path": alias}),
            ("Bash", {"command": "printf x >" + alias}),
        ):
            err, sys.stderr = sys.stderr, io.StringIO()
            try:
                linked = gate(_payload(transcript, cwd=root, tool_name=tool, tool_input=args))
            finally:
                sys.stderr = err
            assert linked == EXIT_REFUSE, f"a hardlink to the synced README was not gated via {tool}"

    err, sys.stderr = sys.stderr, io.StringIO()
    try:
        shell_variant = gate(_payload(transcript, cwd=root, tool_name="Bash",
                                      tool_input={"command": "rm " + os.path.relpath(variant, root)}))
    finally:
        sys.stderr = err
    assert shell_variant == (EXIT_REFUSE if folds else EXIT_OK), (
        f"case-variant shell write returned {shell_variant} (filesystem folds: {folds})")

    _check_registration()

    payload = _payload(transcript, tool_name="Edit", tool_input={"file_path": "/repo/" + SYNCED[0]})
    stdin, sys.stdin = sys.stdin, io.StringIO(json.dumps(payload))
    captured, sys.stderr = sys.stderr, io.StringIO()
    try:
        blocked = hook()
    finally:
        sys.stdin, sys.stderr = stdin, captured
    assert blocked == EXIT_REFUSE, "hook() did not block a synced edit"

    _check_stdin(os.path.dirname(root), payload)
    _check_cli(root, payload)


def _check_registration():
    """The hook is only enforced if `.claude/settings.json` still calls it."""
    here = os.path.abspath(__file__)
    settings_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(here))),
                                 ".claude", "settings.json")
    with open(settings_path, encoding="utf-8") as fh:
        settings = json.load(fh)

    entries = settings.get("hooks", {}).get("PreToolUse", [])
    ours = [
        entry for entry in entries
        if any(os.path.basename(here) in h.get("command", "") and h.get("command", "").endswith("hook")
               for h in entry.get("hooks", []))
    ]
    assert ours, f"{settings_path} no longer runs this script as a PreToolUse hook"
    # The matcher is a regex Claude Code matches against the tool name, so a
    # substring test would accept `NotEdit|NotWrite` and reject nothing.
    matcher = re.compile(ours[0].get("matcher", ""))
    for tool in EDIT_TOOLS + ("Bash",):
        assert matcher.fullmatch(tool), f"the PreToolUse matcher does not match {tool}: {matcher.pattern!r}"
    for unrelated in ("Read", "Grep", "WebFetch"):
        assert not matcher.fullmatch(unrelated), (
            f"the PreToolUse matcher also matches {unrelated}: {matcher.pattern!r}")


def _check_stdin(directory, blocking_payload):
    """`hook()`'s own boundary: what it does with what arrives on stdin."""
    for text, expected, why in (
        ("", EXIT_OK, "empty stdin"),
        ("not json at all", EXIT_OK, "stdin that is not JSON"),
        ("[]", EXIT_OK, "a payload that is not an object"),
        (json.dumps(blocking_payload), EXIT_REFUSE, "a synced edit without the skill"),
    ):
        stdin, sys.stdin = sys.stdin, io.StringIO(text)
        captured, sys.stderr = sys.stderr, io.StringIO()
        try:
            got, noise = hook(), sys.stderr.getvalue()
        finally:
            sys.stdin, sys.stderr = stdin, captured
        assert got == expected, f"hook() returned {got}, expected {expected}: {why}"
        if expected == EXIT_OK:
            assert not noise, f"hook() complained about {why}: {noise!r}"

    # A transcript that cannot be read once the target is known to be synced has
    # to block, not fall through. A directory raises on open.
    unreadable = os.path.join(directory, "unreadable-transcript")
    os.makedirs(unreadable, exist_ok=True)
    payload = dict(blocking_payload, transcript_path=unreadable)
    captured, sys.stderr = sys.stderr, io.StringIO()
    try:
        blocked = gate(payload)
    finally:
        sys.stderr = captured
    assert blocked == EXIT_REFUSE, "an unreadable transcript did not fail closed"


def _check_cli(root, blocking_payload):
    """The command line itself: mode dispatch, GITHUB_WORKSPACE, exit statuses."""
    import subprocess

    script = os.path.abspath(__file__)
    environment = dict(os.environ, GITHUB_WORKSPACE=root)
    lint_run = subprocess.run([sys.executable, script, "lint"], env=environment,
                              capture_output=True, text=True)
    assert lint_run.returncode == EXIT_VIOLATIONS, f"`lint` exited {lint_run.returncode}: {lint_run.stdout}"

    hook_run = subprocess.run([sys.executable, script, "hook"], input=json.dumps(blocking_payload),
                              capture_output=True, text=True)
    assert hook_run.returncode == EXIT_REFUSE, f"`hook` exited {hook_run.returncode}: {hook_run.stderr}"

    usage = subprocess.run([sys.executable, script, "nonsense"], capture_output=True, text=True)
    assert usage.returncode != EXIT_OK, "an unknown mode exited 0"


def selftest():
    """Prove both gates still fire - a rule that stopped matching looks like a clean file."""
    if not __debug__:
        raise SystemExit("selftest asserts; do not run it under python -O")

    # Pin the two external contracts in one place, so the cases below can use
    # the names without the names being able to drift away from the numbers.
    assert (EXIT_OK, EXIT_VIOLATIONS, EXIT_REFUSE) == (0, 1, 2), "exit statuses moved"

    import tempfile

    _check_rules()
    with tempfile.TemporaryDirectory() as directory:
        shapes = _transcripts(directory)
        _check_gate(shapes)
        _check_entry_points(directory, shapes["bare"])

    print("selftest ok")
    return EXIT_OK


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "lint"
    if mode == "hook":
        sys.exit(hook())
    if mode == "selftest":
        sys.exit(selftest())
    if mode == "lint":
        sys.exit(lint(os.environ.get("GITHUB_WORKSPACE") or os.getcwd()))
    sys.exit(f"usage: {sys.argv[0]} [lint|hook|selftest]")

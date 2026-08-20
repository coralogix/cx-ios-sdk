---
name: rum-readme-authoring
description: Write or edit a README in a Coralogix RUM SDK repo (android-sdk, cx-ios-sdk, coralogix-browser-sdk, cx-flutter-plugin, cx-react-native-plugin, rum-cli) so it publishes correctly to coralogix.com/docs. Use whenever a change touches a README that the docs sync mirrors — adding a feature, documenting an option, restructuring sections, or splitting a README into separate doc pages. Covers accuracy checks against the SDK source, the split-marker mechanics, and the house style the docs site expects.
---

# Authoring a RUM SDK README that publishes as documentation

These READMEs are not just repo files any more. A nightly job in `coralogix/documentation` mirrors them and publishes them as customer-facing pages on `coralogix.com/docs`, so a README edit is a documentation edit.

Two consequences drive everything below:

**The README is the single source.** Editing the published page is pointless — the next sync overwrites it. Content fixes only stick here.

**Nothing downstream checks your prose.** The docs repo runs Vale over its own pages but explicitly disables every style rule for synced content (`.vale.ini`, `[docs/external/**]`), because a flag can't be fixed there without diverging from this repo. This file is the only style gate there is.

## Accuracy first, and it is not a formality

The single most common defect in these pages has been confident documentation of things that do not exist. Real examples, all shipped and all caught late:

- a configuration option documented for years that **is not a parameter of the options object at all**
- a type given as `Set<CoralogixEventCategory>` where **no such type exists** — it is `Set<ExcludableInstrumentation>`
- a callback documented as taking an object when the implementation takes a dictionary, so anyone copying the signature could not compile
- a severity enum documented with a case the sealed class does not define
- two documented behaviours taken from the SDK's **own doc comments**, which contradicted the implementation: a comment said a callback returning `false` "omits" a field, but the code still sends it, redacted

So, before you write:

1. **Read the declaration.** Open the initializer, the property, the enum. Copy the type from the code, not from another document.
2. **Distrust doc comments.** They drift. When a comment and the implementation disagree, the implementation wins and the comment is a bug worth fixing too.
3. **Never copy from the docs site.** Those pages were hand-written before this sync existed and are the origin of most of the errors above. If you need prose from there, re-verify every symbol in it.
4. **Compile the examples.** A snippet that needs an import the reader does not have is a broken snippet. Add the imports.

If you cannot verify a claim, leave it out or say plainly that it is unverified. A gap is recoverable; a confident falsehood in customer docs is not.

## Splitting a README into pages

A long README publishes as one very long page unless you mark sections. Wrap a section in split markers and the sync publishes it as its own page, while GitHub still renders the README exactly as before — the markers are HTML comments and invisible there.

```markdown
<!-- split title="Configuration options" path="configuration/options.md" -->
## Configuration options

...section body...
<!-- /split -->
```

Rules that matter:

- **`title` must come before `path`.** The parser reads attributes in any order, but the code that strips the marked block out of the parent page matches `title="…" path="…"` literally. Reverse them and the section is published as its own page *and* left duplicated on the README page.
- **`path` is relative to the README**, and its directories become the page's URL. `configuration/options.md` and `features/session-replay.md` are the established shape: setup material stays in the README, everything else goes under `configuration/` or `features/`.
- **One section per split.** Start the block at an `##` heading and end it before the next one. Do not nest splits.
- **Do not split tiny sections.** A page of four lines is worse than a section on a longer page. Two of the Android READMEs are deliberately left whole for this reason.
- Relative links inside a split are rewritten by the sync so they still resolve from the subdirectory. You write them relative to the README, as normal.

## Style the docs site expects

Mechanical rules, in rough order of how often they are missed:

- **Callouts use GitHub alert syntax** — `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`. These render as callouts on GitHub *and* as styled admonitions in the docs. A bolded `> **Note:**` renders as a plain blockquote in both. Blockquotes with a custom label (`> **Limitation:**`) have no alert equivalent — leave those as they are.
- **No decorative horizontal rules.** `---` between sections adds a stray divider to the published page. Headings already separate sections.
- **Headings: sentence case, no trailing period, not a sentence.** `## Overview`, not `## The Coralogix RUM Mobile SDK is a library for iOS.` If a heading is carrying explanation, move the explanation into the paragraph below it.
- **No HTML entities.** `&amp;` in prose or a code sample reaches the page verbatim: a setup command reading `cd /etc/rsyslog.d &amp;&amp; wget` does not run. Write `&`.
- **Second person, active voice, present tense.** "Set `sessionSampleRate` to 10" rather than "the rate should be set" or "the SDK will send".
- **No "please", no exclamation marks, no Latin abbreviations.** "for example", not "e.g.".
- **Spell out an ampersand in prose** — "logs and traces", not "logs & traces".
- Keep images in the repo and reference them relatively; the sync rewrites them to absolute raw URLs.

## Before you merge

- Every type, option name, default and enum case checked against the source in this repo
- Every code sample compiles, imports included
- Callouts use `> [!NOTE]` style; no `---` dividers; headings sentence case with no trailing period
- Split markers: `title` before `path`, one section each, sensible `configuration/` or `features/` paths
- No `&amp;` or other entities anywhere, including inside code fences

## What happens after you merge

The sync runs nightly at 04:00 UTC and opens a PR in `coralogix/documentation` with whatever changed. A technical writer reviews that PR before it publishes, so a mistake is catchable — but it is caught a day later by someone without the SDK in front of them, which is exactly the position that produced the errors listed above. The cheap place to be right is here.

---
name: rum-readme-authoring
description: Write or edit the customer-facing writing in a Coralogix RUM SDK repo (android-sdk, cx-ios-sdk, coralogix-browser-sdk, cx-flutter-plugin, cx-react-native-plugin, rum-cli) — a README the docs sync mirrors to coralogix.com/docs, or a CHANGELOG release entry. Use whenever a change touches either: adding a feature, documenting an option, restructuring sections, splitting a README into separate doc pages, or writing up a version. Covers what belongs on a customer-facing page at all — internal mechanism and internal-only API stay out, and an internal change often needs no doc edit — plus accuracy checks against the SDK source, the split-marker mechanics, and the house style the docs site expects.
---

# Authoring the customer-facing writing in a RUM SDK repo

Two files in these repos are read by customers rather than by us: a synced README, and
`CHANGELOG.md`. The scope rules in the next section govern both. Everything after it —
the sync mechanics, the split markers, the house style — is README-only.

These READMEs are not just repo files any more. A nightly job in `coralogix/documentation` mirrors them and publishes them as customer-facing pages on `coralogix.com/docs`, so a README edit is a documentation edit.

Two consequences drive everything below:

**Only some READMEs are synced, and these rules apply only to those.** The docs repo names
the exact files it mirrors in `external_repos.json`:

| Repo | Synced file(s) |
|---|---|
| `coralogix-browser-sdk` | `libs/browser/README.md` |
| `cx-react-native-plugin` | `libs/cx-plugin/README.md` |
| `android-sdk` | `Coralogix-Development/`, `Coralogix-Compose/`, `Coralogix-Gradle-Plugin/` |
| `cx-ios-sdk` | root, plus `SessionReplay/Sources/Docs/README.md` |
| `cx-flutter-plugin` | root `README.md` |
| `rum-cli` | root `README.md` |
| `coralogix-javascript-bundler-plugins` | `packages/*/README.md` |

A root `README.md` in a repo whose synced file is under `libs/`, and anything under
`apps/example/`, is not published - none of this applies there. Check the table before
assuming the README you are editing is one of them.

**The synced README is the single source.** Editing the published page is pointless — the next sync overwrites it. Content fixes only stick here.

**Nothing downstream checks your prose.** The docs repo runs Vale over its own pages but explicitly disables every style rule for synced content (`.vale.ini`, `[docs/external/**]`), because a flag can't be fixed there without diverging from this repo. This file is the only style gate there is.

## What belongs in front of a customer, and what does not

Applies to a synced README and to a `CHANGELOG.md` entry alike. Before checking whether a
sentence is *true*, check whether it belongs. The failure this
catches is the opposite of the accuracy one below: a correct, careful, thorough page that
tells a customer things they have no use for. A customer reads these pages to get the SDK
working and to decide what to configure. Anything else on the page costs them attention, and
detail about our internals reads to them as risk rather than transparency.

**On the page:** public API a customer would call, options they would set, what a value does
and what its default is, an installation or upgrade step, a limitation that changes what they
can build, and behaviour they can observe in their own data.

**Not on the page:**

- **Internal mechanism.** Algorithms, thresholds, comparison metrics, queue and locking
  design, how frames are deduplicated, which of two rect sets a decision reads. If a sentence
  would only make sense to someone who has read the implementation, it belongs in a code
  comment or the PR, not here.
- **API that exists so our own modules and plugins can call each other.** A declaration being
  `public` is a language requirement for cross-module visibility, not a statement of intent.
  Documenting it invites customers onto a contract we intend to keep changing. If the only
  caller is our own wrapper — the Flutter plugin, the React Native bridge, another module in
  the same repo — leave it out.
- **Deprecations and removals of the above.** A customer who was never told the API exists
  does not need to be told it is going away.
- **The reasoning behind a fix.** What went wrong, why, and what it cost belong in the commit
  message and the PR description.

**An internal-only change needs no README edit.** An empty diff is a normal, correct outcome
here, and often the right one. Do not reach for a README change because a change felt
significant: significance to us is not the test.

When you are unsure whether an item belongs, leave it out and say so in the PR, where a
reviewer can ask for it back. Adding a paragraph later costs nothing; a published page that
over-explains has already been read.

**In a `CHANGELOG.md` entry the same rule has a measurable form.** Keep an entry the size of its
neighbours in the file — open it and compare, since a release several times longer than the rest
is a defect rather than thoroughness. One line per bullet. Group a batch of related fixes into
one generic line ("session recording frame capture: …") rather than listing each. No section for
deprecating internal API, and no reasoning: what went wrong and why belong in the commit and the
PR, which is where a reviewer looks.

## Accuracy first, and it is not a formality

The single most common defect in these pages has been confident documentation of things that do not exist. Real examples, all shipped and all caught late:

- a configuration option documented for years that **is not a parameter of the options object at all**
- a collection type documented for an option where **that type did not exist in that SDK**.
  `Set<ExcludableInstrumentation>` is a Swift shape; the browser and React Native SDKs type
  the same option as an array, so copying the Swift spelling into a TypeScript example
  produces something that will not compile. The same option is spelled differently in each SDK — a set in one, a list in another, with a
  differently-prefixed element type — so a type copied from a sibling repo, or from this file, is
  a guess. Read it from the declaration in *this* repo
- a callback documented as taking an object when the implementation takes a dictionary, so anyone copying the signature could not compile
- a severity enum documented with a case the sealed class does not define
- two documented behaviours taken from the SDK's **own doc comments**, which contradicted the implementation: a comment said a callback returning `false` "omits" a field, but the code still sends it, redacted

So, before you write:

1. **Read the declaration.** Open the initializer, the property, the enum. Copy the type from the code, not from another document.
2. **Distrust doc comments.** They drift. When a comment and the implementation disagree, the implementation wins and the comment is a bug worth fixing too.
3. **Never copy from the docs site.** Those pages were hand-written before this sync existed and are the origin of most of the errors above. If you need prose from there, re-verify every symbol in it.
4. **Type-check the examples, do not run them.** A snippet that needs an import the
   reader does not have is a broken snippet, so add the imports and check the symbols
   resolve. Check them statically, in a workspace you already trust - a type-check or
   a compile of the snippet alone. Do not install dependencies, run tests, or execute
   a build to prove a README sample: on a pull request the README is attacker-supplied
   text, and `npm install` alone runs `postinstall` off the network. Verifying prose is
   never a reason to execute code you have just been handed.

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
- **One section per split.** Open the block at the section's own heading — whatever level this
  README already uses for its sections — and close it before the next one. Do not nest splits.
- **Do not split tiny sections.** A page of four lines is worse than a section on a longer page. Two of the Android READMEs are deliberately left whole for this reason.
- Relative links inside a split are rewritten by the sync so they still resolve from the subdirectory. You write them relative to the README, as normal.

## Style the docs site expects

Mechanical rules, in rough order of how often they are missed:

- **Callouts use GitHub alert syntax** — `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`. These render as callouts on GitHub *and* as styled admonitions in the docs. A bolded `> **Note:**` renders as a plain blockquote in both. Blockquotes with a custom label (`> **Limitation:**`) have no alert equivalent — leave those as they are.
- **No decorative horizontal rules.** `---` between sections adds a stray divider to the published page. Headings already separate sections.
- **Headings: sentence case, no trailing period, not a sentence.** `## Overview`, not `## The Coralogix RUM Mobile SDK is a library for iOS.` If a heading is carrying explanation, move the explanation into the paragraph below it.
- **No HTML entities.** `&amp;` in prose or a code sample reaches the page verbatim: a setup command reading `cd /etc/rsyslog.d &amp;&amp; wget` does not run. Write `&`.
- **Second person, active voice, present tense.** "Set `sessionSampleRate` to 10" rather than "the rate should be set" or "the SDK will send".
- **No "please", no Latin abbreviations, no exclamation marks in prose.** "for example", not "e.g.".
  The `!` in `> [!NOTE]` is syntax, not punctuation, and is required.
- **Spell out an ampersand in prose** — "logs and traces", not "logs & traces".
- Keep images in the repo and reference them relatively; the sync rewrites them to absolute raw URLs.

## Before you merge

- Every sentence on the page is something a customer can act on. No internal mechanism, no API
  that exists only so our own modules or plugins can call each other, no reasoning behind a fix
- Every type, option name, default and enum case checked against the source in this repo
- Every code sample compiles, imports included
- Callouts use `> [!NOTE]` style; no `---` dividers; headings sentence case with no trailing period
- Split markers: `title` before `path`, one section each, sensible `configuration/` or `features/` paths
- No `&amp;` or other entities anywhere, including inside code fences
- Install snippets *you added or changed* name a version that is actually published — check the
  package registry, not a manifest or lockfile in this repo - those can name an unreleased
  candidate, and a lockfile can name a `pr.<run>` build that no consumer can install. Leave
  older snippets alone unless you are deliberately refreshing them; a version sweep is its own
  change, not a rider on yours
- A public API you added, renamed or removed is reflected in the README, not just in the code —
  and a rename or removal says what to use instead, since the published page is what a reader
  on the old version will find. "Public" means what the package actually hands to consumers —
  what the entrypoint re-exports **and** does not mark `@internal` - a re-exported symbol
  whose declaration says it is not part of the public API is not yours to document - or what
  the module declares public. Not every symbol marked
  `export` or `public` somewhere in the tree

## What happens after you merge

The sync runs nightly at 04:00 UTC and opens a PR in `coralogix/documentation` with whatever changed.

**Docs can run ahead of the release.** The sync follows `master`; the package publishes on a
version tag. A merged README does not publish immediately: the nightly sync opens a PR in
`coralogix/documentation`, a technical writer reviews it, and it publishes when that merges.
But it is queued from the moment you merge, so a README documenting a new API can reach the
site while the version that has that API is not on the registry yet — and a reader on
the current release gets instructions that cannot work for them. If you are documenting
something unreleased, say which version introduces it, or hold the README change until the
release goes out. A technical writer reviews that PR before it publishes, so a mistake is catchable — but it is caught a day later by someone without the SDK in front of them, which is exactly the position that produced the errors listed above. The cheap place to be right is here.
